def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["api"] == "orders-api"


def test_list_orders_seeded(client):
    r = client.get("/orders")
    assert r.status_code == 200
    assert any(o["id"] == "ord-1001" for o in r.json())


def test_create_order_computes_total(client):
    body = {"customerId": "cust-7", "currency": "usd", "items": [{"sku": "A", "quantity": 2, "unitPrice": 10.5}]}
    r = client.post("/orders", json=body)
    assert r.status_code == 201
    assert r.json()["total"] == 21.0
    assert r.json()["currency"] == "USD"
    assert r.json()["status"] == "pending"


def test_create_order_requires_items(client):
    r = client.post("/orders", json={"customerId": "cust-7", "currency": "USD", "items": []})
    assert r.status_code == 422


def test_get_order_not_found(client):
    assert client.get("/orders/ord-999999").status_code == 404


def test_demo_order_1024_exists(client):
    r = client.get("/orders/ord-1024")
    assert r.status_code == 200
    assert r.json()["status"] == "shipped"
