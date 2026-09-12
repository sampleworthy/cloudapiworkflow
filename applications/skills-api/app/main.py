"""Skills API backend.

Runs behind Azure API Management. App Service built-in authentication (Easy
Auth) has already rejected any request that did not carry a token issued for
this app's registration by the APIM managed identity, so the code trusts the
X-MS-CLIENT-PRINCIPAL-* headers for logging only and does no auth itself.
"""

import logging
import os
from typing import Literal

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel

API_NAME = os.getenv("API_NAME", "skills-api")
API_VERSION = os.getenv("API_VERSION", "v1")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(API_NAME)

app = FastAPI(title="Skills API", version="1.0.0")

Category = Literal["cloud", "data", "security", "platform"]
Level = Literal["beginner", "intermediate", "advanced", "expert"]


class Skill(BaseModel):
    id: str
    name: str
    category: Category
    level: Level


class Health(BaseModel):
    status: str
    api: str
    version: str


SKILLS: dict[str, Skill] = {
    s.id: s
    for s in [
        Skill(id="terraform", name="Terraform", category="platform", level="expert"),
        Skill(id="azure-apim", name="Azure API Management", category="cloud", level="expert"),
        Skill(id="entra-id", name="Microsoft Entra ID", category="security", level="advanced"),
        Skill(id="github-actions", name="GitHub Actions", category="platform", level="advanced"),
        Skill(id="kql", name="Kusto Query Language", category="data", level="intermediate"),
    ]
}


@app.middleware("http")
async def correlation(request: Request, call_next):
    cid = request.headers.get("x-correlation-id", "-")
    caller = request.headers.get("x-ms-client-principal-name", "anonymous")
    response = await call_next(request)
    log.info("cid=%s caller=%s %s %s -> %s", cid, caller, request.method, request.url.path, response.status_code)
    response.headers["X-Correlation-Id"] = cid
    return response


@app.get("/health", response_model=Health)
def health() -> Health:
    return Health(status="ok", api=API_NAME, version=API_VERSION)


@app.get("/skills", response_model=list[Skill])
def list_skills(category: Category | None = None) -> list[Skill]:
    items = list(SKILLS.values())
    if category:
        items = [s for s in items if s.category == category]
    return items


@app.get("/skills/{skill_id}", response_model=Skill)
def get_skill(skill_id: str) -> Skill:
    skill = SKILLS.get(skill_id)
    if skill is None:
        raise HTTPException(status_code=404, detail={"code": "NotFound", "message": f"skill '{skill_id}' not found"})
    return skill
