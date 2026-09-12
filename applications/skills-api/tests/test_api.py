def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_list_skills(client):
    r = client.get("/skills")
    assert r.status_code == 200
    ids = {s["id"] for s in r.json()}
    assert "terraform" in ids


def test_filter_by_category(client):
    r = client.get("/skills", params={"category": "security"})
    assert r.status_code == 200
    assert all(s["category"] == "security" for s in r.json())
    assert len(r.json()) >= 1


def test_invalid_category_rejected(client):
    assert client.get("/skills", params={"category": "cooking"}).status_code == 422


def test_get_skill_not_found(client):
    assert client.get("/skills/does-not-exist").status_code == 404


def test_correlation_header_echoed(client):
    r = client.get("/health", headers={"X-Correlation-Id": "abc-123"})
    assert r.headers["X-Correlation-Id"] == "abc-123"
