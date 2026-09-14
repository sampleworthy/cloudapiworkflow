#!/usr/bin/env python3
"""Backend connectivity validation: prove the APIM -> backend runtime path for
every published API, and classify any failure.

A successful APIOps publish only means APIM accepted the configuration. This
check runs afterwards and walks the path in order:

  1. APIM configuration   API exists, policy routes to a backend entity, the entity's URL
                          matches the environment's expected URL (else: incorrect backend URL)
  2. DNS                  the backend host resolves; private-link answers are recognised
  3. Network              TCP 443 reachable from the runner (expected to fail for private backends)
  4. TLS                  certificate chain and hostname valid (APIM validates both)
  5. Private networking   private endpoint / private DNS / public access / VNet settings consistent
  6. Workload auth        APIM has a managed identity and the policy uses it for this backend
  7. Backend authz        the backend's built-in auth lists APIM's identity and the requested audience
  8. Backend /health      answered directly (401/403 expected: identity-locked) or unreachable (private)
  9. Gateway /health      GET <gateway>/<path>/health -> 200, i.e. APIM reached the backend
                          non-200 is classified from APIM's backend telemetry (App Insights)

Exit 0 only when every API's gateway request reached its backend. Findings go
to stdout and, when GITHUB_STEP_SUMMARY is set, to the job summary.

Usage: scripts/backend_path_check.py DEV [api-folder ...]
Env:   APIM_NAME_<S> APIM_RESOURCE_GROUP_<S> APIM_GATEWAY_URL_<S> AZURE_SUBSCRIPTION_ID_<S>
       LOG_ANALYTICS_WORKSPACE_ID_<S> API_AUDIENCE_<S> APIM_IDENTITY_CLIENT_ID_<S> (optional)
       BACKEND_URL_<API>_<S> / FOUNDRY_OPENAI_ENDPOINT_<S> (expected backend URLs)
Auth:  Azure CLI login with Reader on the resource group (the APIOps publisher identity)
"""
from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import re
import socket
import ssl
import subprocess
import sys
import time
import urllib.parse
import uuid

import requests
import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
ARM = "https://management.azure.com"
APIM_API = "2024-05-01"
PRIVATE_NETS = [("10.0.0.0", 8), ("172.16.0.0", 12), ("192.168.0.0", 16)]


# ----------------------------------------------------------------------------- helpers
def env(name: str, suffix: str, default: str | None = None) -> str | None:
    return os.environ.get(f"{name}_{suffix}") or os.environ.get(name) or default


def az(*args: str) -> tuple[int, str]:
    p = subprocess.run(["az", *args], capture_output=True, text=True)
    return p.returncode, (p.stdout or p.stderr).strip()


def arm_get(url: str) -> tuple[int, dict | str]:
    code, out = az("rest", "--method", "get", "--url", url, "-o", "json")
    if code != 0:
        return code, out
    try:
        return 0, json.loads(out or "{}")
    except json.JSONDecodeError:
        return 0, out


def is_private(ip: str) -> bool:
    try:
        n = int.from_bytes(socket.inet_aton(ip), "big")
    except OSError:
        return False
    for net, bits in PRIVATE_NETS:
        base = int.from_bytes(socket.inet_aton(net), "big")
        if n >> (32 - bits) == base >> (32 - bits):
            return True
    return False


class Report:
    """Collects (stage, status, detail, classification) rows per API."""

    def __init__(self, api: str):
        self.api, self.rows, self.failed = api, [], False

    def add(self, stage: str, status: str, detail: str, cause: str = "") -> None:
        self.rows.append((stage, status, detail, cause))
        if status == "FAIL":
            self.failed = True
        mark = {"PASS": "PASS", "FAIL": "FAIL", "WARN": "WARN", "SKIP": "skip", "INFO": "info"}[status]
        print(f"  {mark:4} {stage:<22} {detail}" + (f"  [{cause}]" if cause else ""))


def resolve_named_values(base: str, text: str) -> str:
    """Replace {{name}} references with the named value's current value in APIM."""
    def lookup(m: re.Match) -> str:
        code, nv = arm_get(f"{base}/namedValues/{m.group(1)}?api-version={APIM_API}")
        val = (nv.get("properties") or {}).get("value") if isinstance(nv, dict) else None
        return val or m.group(0)
    return re.sub(r"\{\{([^}]+)\}\}", lookup, text)


# ----------------------------------------------------------------------------- stages
def stage_apim_config(r: Report, s: str, api: str, folder: pathlib.Path, expected_url: str | None) -> dict:
    apim, rg, sub = env("APIM_NAME", s), env("APIM_RESOURCE_GROUP", s), env("AZURE_SUBSCRIPTION_ID", s)
    base = f"{ARM}/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{apim}"
    ctx = {"base": base, "backend_url": None, "backend_id": None, "mi_resource": None, "mock": False}
    code, a = arm_get(f"{base}/apis/{api}?api-version={APIM_API}")
    if code != 0 or not isinstance(a, dict) or "properties" not in a:
        r.add("APIM configuration", "FAIL", f"API '{api}' not found in {apim}", "APIM policy/route: API not published"); return ctx
    props = a["properties"]
    ctx["path"] = props.get("path", "") + (f"/{props['apiVersion']}" if props.get("apiVersion") else "")
    code, pol = arm_get(f"{base}/apis/{api}/policies/policy?api-version={APIM_API}&format=rawxml")
    # with format=rawxml ARM returns the XML body itself; older API versions wrap it in JSON
    xml = pol["properties"]["value"] if isinstance(pol, dict) and "properties" in pol else (pol if isinstance(pol, str) else "")
    if "<mock-response" in xml:
        ctx["mock"] = True
        r.add("APIM configuration", "INFO", "API is mocked at the gateway (no backend call)"); return ctx
    m = re.search(r'set-backend-service backend-id="([^"]+)"', xml)
    if not m:
        r.add("APIM configuration", "FAIL", "policy has no set-backend-service backend-id; APIM cannot route", "APIM policy"); return ctx
    ctx["backend_id"] = m.group(1)
    mi = re.search(r'authentication-managed-identity resource="([^"]+)"', xml)
    ctx["mi_resource"] = resolve_named_values(base, mi.group(1)) if mi else None
    code, b = arm_get(f"{base}/backends/{ctx['backend_id']}?api-version={APIM_API}")
    if code != 0 or not isinstance(b, dict) or "properties" not in b:
        r.add("APIM configuration", "FAIL", f"backend entity '{ctx['backend_id']}' missing in APIM", "APIM policy: backend entity not published"); return ctx
    ctx["backend_url"] = b["properties"]["url"].rstrip("/")
    tls = b["properties"].get("tls") or {}
    ctx["validate_tls"] = bool(tls.get("validateCertificateChain", True)) or bool(tls.get("validateCertificateName", True))
    if expected_url and urllib.parse.urlparse(ctx["backend_url"]).netloc.lower() != urllib.parse.urlparse(expected_url).netloc.lower():
        r.add("APIM configuration", "FAIL", f"backend '{ctx['backend_id']}' points at {ctx['backend_url']} but this environment expects {expected_url}", "Incorrect backend URL (configuration override not applied)")
    elif "placeholder.invalid" in ctx["backend_url"]:
        r.add("APIM configuration", "FAIL", f"backend '{ctx['backend_id']}' still has the placeholder URL {ctx['backend_url']}", "Incorrect backend URL (configuration override not applied)")
    else:
        r.add("APIM configuration", "PASS", f"API at /{ctx['path']} -> backend '{ctx['backend_id']}' = {ctx['backend_url']}")
    return ctx


def stage_dns(r: Report, host: str) -> list[str]:
    try:
        ips = sorted({ai[4][0] for ai in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)})
    except socket.gaierror as e:
        r.add("DNS resolution", "FAIL", f"{host} does not resolve from the runner ({e})", "DNS"); return []
    priv = [ip for ip in ips if is_private(ip)]
    if priv:
        r.add("DNS resolution", "INFO", f"{host} -> {', '.join(ips)} (private address: private-link DNS in effect on this network)")
    else:
        r.add("DNS resolution", "PASS", f"{host} -> {', '.join(ips)}")
    return ips


def stage_network(r: Report, host: str, private_expected: bool) -> bool:
    try:
        with socket.create_connection((host, 443), timeout=8):
            r.add("Network reachability", "PASS", f"TCP 443 to {host} open from the runner (public network)")
            return True
    except (socket.timeout, OSError) as e:
        if private_expected:
            r.add("Network reachability", "INFO", f"TCP 443 to {host} closed from the public internet ({e}); expected for a private backend - APIM reaches it over the VNet (proven by stage 9)")
        else:
            r.add("Network reachability", "FAIL", f"TCP 443 to {host} not reachable ({e})", "Routing / NSG / firewall (public backend expected)")
        return False


def stage_tls(r: Report, host: str, validate: bool) -> None:
    ctx = ssl.create_default_context()
    try:
        with socket.create_connection((host, 443), timeout=8) as sock, ctx.wrap_socket(sock, server_hostname=host) as tls:
            cert = tls.getpeercert()
            exp = cert.get("notAfter", "?"); subj = dict(x[0] for x in cert.get("subject", ()))
            r.add("TLS", "PASS", f"chain and hostname valid; CN={subj.get('commonName', '?')} expires {exp}; {tls.version()}")
    except ssl.SSLCertVerificationError as e:
        r.add("TLS", "FAIL" if validate else "WARN", f"certificate rejected: {e.verify_message}" if hasattr(e, 'verify_message') else str(e), "TLS (APIM validates chain and name)")
    except (socket.timeout, OSError) as e:
        r.add("TLS", "SKIP", f"no connection from the runner ({e})")


def stage_private(r: Report, s: str, host: str, private_expected: bool) -> None:
    sub, rg = env("AZURE_SUBSCRIPTION_ID", s), env("APIM_RESOURCE_GROUP", s)
    site = host.split(".")[0]
    code, w = arm_get(f"{ARM}/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/sites/{site}?api-version=2023-12-01")
    if code != 0 or not isinstance(w, dict) or "properties" not in w:
        r.add("Private networking", "SKIP", f"{site} is not a web app in {rg}; network settings not inspected"); return
    p = w["properties"]
    pna = p.get("publicNetworkAccess", "Enabled")
    vnet = bool(p.get("virtualNetworkSubnetId"))
    pes = p.get("privateEndpointConnections") or []
    code2, cfg = arm_get(f"{ARM}/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/sites/{site}/config/web?api-version=2023-12-01")
    restrictions = []
    if code2 == 0 and isinstance(cfg, dict):
        restrictions = [x for x in (cfg["properties"].get("ipSecurityRestrictions") or []) if x.get("action") == "Allow" and x.get("ipAddress") not in (None, "Any")]
    detail = f"publicNetworkAccess={pna}, vnetIntegration={'yes' if vnet else 'no'}, privateEndpoints={len(pes)}, ipAllowRules={len(restrictions)}"
    if private_expected:
        if pna != "Disabled" or not pes:
            r.add("Private networking", "FAIL", detail, "Private endpoint / access restriction: private mode expected but public access is enabled or no private endpoint exists"); return
        bad = [pe for pe in pes if (pe.get("properties", {}).get("privateLinkServiceConnectionState", {}).get("status") != "Approved")]
        if bad:
            r.add("Private networking", "FAIL", detail + "; a private endpoint connection is not Approved", "Private endpoint"); return
        code3, rs = arm_get(f"{ARM}/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net/A?api-version=2020-06-01")
        names = [x["name"] for x in rs.get("value", [])] if isinstance(rs, dict) else []
        if site not in names:
            r.add("Private networking", "FAIL", detail + f"; no A record for {site} in privatelink.azurewebsites.net", "Private DNS"); return
        r.add("Private networking", "PASS", detail + "; private endpoint approved and private DNS record present")
    else:
        r.add("Private networking", "INFO", detail + " (public backend, identity-locked; prod tfvars enable private endpoints)")


def stage_workload_auth(r: Report, s: str, ctx: dict) -> str | None:
    apim, rg = env("APIM_NAME", s), env("APIM_RESOURCE_GROUP", s)
    code, out = az("apim", "show", "-g", rg, "-n", apim, "--query", "identity.principalId", "-o", "tsv")
    if code != 0 or not out:
        r.add("Workload authentication", "FAIL", "APIM has no system-assigned managed identity", "Authentication (APIM identity)"); return None
    if not ctx.get("mi_resource"):
        r.add("Workload authentication", "FAIL", "API policy does not call the backend with authentication-managed-identity", "Authentication (APIM policy)"); return None
    client_id = env("APIM_IDENTITY_CLIENT_ID", s)
    if not client_id:
        c2, cid = az("ad", "sp", "show", "--id", out, "--query", "appId", "-o", "tsv")
        client_id = cid if c2 == 0 else None
    r.add("Workload authentication", "PASS", f"APIM system identity {out[:8]}… requests a token for {ctx['mi_resource']}")
    return client_id


def stage_backend_authz(r: Report, s: str, host: str, apim_client_id: str | None, mi_resource: str | None) -> None:
    sub, rg = env("AZURE_SUBSCRIPTION_ID", s), env("APIM_RESOURCE_GROUP", s)
    site = host.split(".")[0]
    code, a = arm_get(f"{ARM}/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/sites/{site}/config/authsettingsV2?api-version=2023-12-01")
    if code != 0 or not isinstance(a, dict) or "properties" not in a:
        r.add("Backend authorization", "SKIP", f"{site}: built-in auth settings not readable (not a web app or no permission)"); return
    p = a["properties"]
    if not (p.get("platform", {}).get("enabled")):
        r.add("Backend authorization", "WARN", f"{site}: built-in authentication is OFF - anyone who can reach the host can call it", "Authorization (backend not identity-locked)"); return
    aad = (p.get("identityProviders") or {}).get("azureActiveDirectory") or {}
    allowed_apps = (aad.get("validation") or {}).get("defaultAuthorizationPolicy", {}).get("allowedApplications") or []
    audiences = (aad.get("validation") or {}).get("allowedAudiences") or []
    problems = []
    if apim_client_id and apim_client_id not in allowed_apps:
        problems.append(f"APIM identity {apim_client_id} is not in allowedApplications {allowed_apps}")
    if mi_resource and mi_resource not in audiences and not any(mi_resource in x for x in audiences):
        problems.append(f"policy requests audience {mi_resource} but the backend accepts {audiences}")
    if problems:
        r.add("Backend authorization", "FAIL", "; ".join(problems), "Authorization (Easy Auth allow-list / audience mismatch)")
    else:
        r.add("Backend authorization", "PASS", f"built-in auth on; APIM identity allowed; audience {mi_resource} accepted; unauthenticated action {p.get('globalValidation', {}).get('unauthenticatedClientAction')}")


def stage_backend_health(r: Report, backend_url: str, reachable: bool, kind: str) -> None:
    if kind != "app_service":
        r.add("Backend /health", "SKIP", "not an App Service backend; reachability is proven by the gateway request"); return
    if not reachable:
        r.add("Backend /health", "SKIP", "not reachable from the runner (private backend)"); return
    try:
        resp = requests.get(f"{backend_url}/health", timeout=30, allow_redirects=False)
    except requests.RequestException as e:
        r.add("Backend /health", "FAIL", f"no HTTP response: {e}", "Backend availability"); return
    if resp.status_code in (401, 403):
        r.add("Backend /health", "PASS", f"HTTP {resp.status_code} for an anonymous caller: backend is up and identity-locked")
    elif resp.status_code == 200:
        r.add("Backend /health", "WARN", "HTTP 200 for an anonymous caller: the backend is NOT identity-locked", "Authorization (backend reachable without APIM)")
    elif resp.status_code >= 500:
        r.add("Backend /health", "FAIL", f"HTTP {resp.status_code} from the platform: the app is down or crash-looping", "Backend availability")
    else:
        r.add("Backend /health", "WARN", f"unexpected HTTP {resp.status_code}")


def classify_from_telemetry(s: str, correlation: str) -> tuple[str, str]:
    """Ask APIM's own telemetry what happened to the backend call for this correlation id."""
    ws = env("LOG_ANALYTICS_WORKSPACE_ID", s)
    if not ws:
        return "", "no workspace id; cannot read APIM backend telemetry"
    q = ("union AppDependencies, AppExceptions, AppRequests | where TimeGenerated > ago(30m) "
         f"| where tostring(Properties['Response-X-Correlation-Id']) == '{correlation}' or tostring(Properties['Request-X-Correlation-Id']) == '{correlation}' or OperationId has '{correlation}' or tostring(Properties['Reason']) != '' "
         "| project Type, ResultCode, Success, Name, Target, Reason = tostring(Properties['Reason']), Message = coalesce(tostring(Properties['Message']), OuterMessage) "
         "| take 20")
    for _ in range(16):
        code, out = az("monitor", "log-analytics", "query", "-w", ws, "--analytics-query", q, "-o", "json")
        rows = json.loads(out) if code == 0 and out.startswith("[") else []
        deps = [x for x in rows if x.get("Type") == "AppDependencies"]
        excs = [x for x in rows if x.get("Type") == "AppExceptions"]
        if deps or excs:
            for d in deps:
                rc = str(d.get("ResultCode", ""))
                if rc in ("401",):
                    return "Authentication (backend rejected APIM's token)", f"backend {d.get('Target')} answered 401"
                if rc in ("403",):
                    return "Authorization (backend refused APIM's identity)", f"backend {d.get('Target')} answered 403"
                if rc.startswith("5"):
                    return "Backend availability", f"backend {d.get('Target')} answered {rc}"
                if rc == "404":
                    return "Incorrect backend URL / path", f"backend {d.get('Target')} answered 404"
            for e in excs:
                msg = (e.get("Message") or e.get("Reason") or "").lower()
                if "no such host" in msg or "name or service not known" in msg or "nodename nor servname" in msg or "could not be resolved" in msg:
                    return "DNS (from APIM)", msg[:160]
                if "ssl" in msg or "certificate" in msg or "tls" in msg:
                    return "TLS (from APIM)", msg[:160]
                if "timed out" in msg or "refused" in msg or "unreachable" in msg or "backendconnectionfailure" in msg:
                    return "Routing / NSG / private endpoint (APIM cannot connect)", msg[:160]
                if "policy" in msg or "expression" in msg:
                    return "APIM policy", msg[:160]
            return "Backend failure (see telemetry)", json.dumps(rows[:3])[:300]
        time.sleep(15)
    return "", "no APIM backend telemetry for this request yet (ingestion delay)"


def stage_gateway(r: Report, s: str, ctx: dict) -> None:
    gw = env("APIM_GATEWAY_URL", s).rstrip("/")
    url = f"{gw}/{ctx['path']}/health"
    corr = f"bpc-{uuid.uuid4()}"
    last = None
    for attempt in range(12):
        try:
            resp = requests.get(url, headers={"X-Correlation-Id": corr}, timeout=45)
            last = resp
            if resp.status_code == 200:
                r.add("APIM gateway /health", "PASS", f"GET {url} -> 200 via APIM (correlation {corr}); the backend answered through the gateway")
                return
        except requests.RequestException as e:
            last = e
        time.sleep(10)
    code = getattr(last, "status_code", None)
    if code == 404:
        r.add("APIM gateway /health", "FAIL", f"GET {url} -> 404: no API/operation at this path", "APIM policy/route (API not published or wrong path)")
    elif code in (401, 403):
        r.add("APIM gateway /health", "FAIL", f"GET {url} -> {code}: the health operation is not anonymous at the gateway", "APIM policy")
    elif code is None:
        r.add("APIM gateway /health", "FAIL", f"GET {url}: no response ({last})", "Gateway unreachable")
    else:
        cause, detail = classify_from_telemetry(s, corr)
        r.add("APIM gateway /health", "FAIL", f"GET {url} -> {code}; {detail}", cause or "Backend failure")


# ----------------------------------------------------------------------------- main
def expected_backend_url(s: str, api_folder: str, rendered: dict) -> str | None:
    """The URL the environment's configuration override sets for this API's backend."""
    for b in rendered.get("backends") or []:
        if b["name"] == api_folder.rsplit("-v", 1)[0]:
            return (b.get("properties") or {}).get("url", "").rstrip("/") or None
    return None


def rendered_configuration(s: str) -> dict:
    p = ROOT / "apim" / f"configuration.{s.lower()}.yaml"
    if not p.exists():
        return {}
    text = p.read_text()
    text = re.sub(r"\{#([A-Z0-9_]+)#\}", lambda m: env(m.group(1), s, m.group(0)), text)
    return yaml.safe_load(text) or {}


def main(argv: list[str]) -> int:
    s = argv[1] if len(argv) > 1 else "DEV"
    apis = argv[2:] or sorted(p.name for p in (ROOT / "apim" / "artifacts" / "apis").iterdir() if p.is_dir())
    private_expected = (env("PRIVATE_ENDPOINTS_ENABLED", s, "false") or "false").lower() == "true"
    rendered = rendered_configuration(s)
    reports: list[Report] = []
    for api in apis:
        folder = ROOT / "apim" / "artifacts" / "apis" / api
        print(f"== {api}")
        r = Report(api); reports.append(r)
        ctx = stage_apim_config(r, s, api, folder, expected_backend_url(s, api, rendered))
        if ctx.get("mock") or not ctx.get("backend_url"):
            if not ctx.get("mock"):
                r.add("APIM gateway /health", "SKIP", "no backend configured; path not testable")
            continue
        host = urllib.parse.urlparse(ctx["backend_url"]).hostname or ""
        kind = "app_service" if host.endswith("azurewebsites.net") else "external"
        stage_dns(r, host)
        reachable = stage_network(r, host, private_expected and kind == "app_service")
        stage_tls(r, host, ctx.get("validate_tls", True)) if reachable else r.add("TLS", "SKIP", "no runner connection")
        stage_private(r, s, host, private_expected) if kind == "app_service" else r.add("Private networking", "SKIP", "not an App Service backend")
        apim_client_id = stage_workload_auth(r, s, ctx)
        stage_backend_authz(r, s, host, apim_client_id, ctx.get("mi_resource")) if kind == "app_service" else r.add("Backend authorization", "SKIP", "external backend; authorization proven by the gateway request")
        stage_backend_health(r, ctx["backend_url"], reachable, kind)
        stage_gateway(r, s, ctx)

    failed = [r for r in reports if r.failed]
    verdict = "DEPLOYMENT VERIFIED" if not failed else "DEPLOYMENT NOT VERIFIED"
    print(f"\n{verdict}: {len(reports) - len(failed)}/{len(reports)} API(s) reachable end to end through APIM")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(f"### Backend connectivity validation ({s}): **{verdict}**\n\n")
            for r in reports:
                f.write(f"#### `{r.api}` — {'FAIL' if r.failed else 'PASS'}\n\n| stage | status | detail | cause |\n|---|---|---|---|\n")
                for stage, status, detail, cause in r.rows:
                    f.write(f"| {stage} | {status} | {detail.replace('|', '/')} | {cause} |\n")
                f.write("\n")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
