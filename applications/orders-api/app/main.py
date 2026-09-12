"""Orders API backend. See applications/skills-api/app/main.py for the
platform conventions (Easy Auth in front, correlation id logging)."""

import logging
import os
from itertools import count
from typing import Literal

from fastapi import FastAPI, HTTPException, Request, status
from pydantic import BaseModel, Field

API_NAME = os.getenv("API_NAME", "orders-api")
API_VERSION = os.getenv("API_VERSION", "v1")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(API_NAME)

app = FastAPI(title="Orders API", version="1.0.0")

OrderStatus = Literal["pending", "confirmed", "shipped", "cancelled"]


class OrderItem(BaseModel):
    sku: str
    quantity: int = Field(ge=1)
    unitPrice: float = Field(ge=0)


class NewOrder(BaseModel):
    customerId: str
    items: list[OrderItem] = Field(min_length=1)
    currency: str = Field(min_length=3, max_length=3)


class Order(BaseModel):
    id: str
    customerId: str
    status: OrderStatus
    total: float
    currency: str
    items: list[OrderItem]


class Health(BaseModel):
    status: str
    api: str
    version: str


_ids = count(1001)
ORDERS: dict[str, Order] = {}


def _seed() -> None:
    o = Order(
        id=f"ord-{next(_ids)}",
        customerId="cust-42",
        status="confirmed",
        total=129.99,
        currency="USD",
        items=[OrderItem(sku="SKU-1", quantity=1, unitPrice=129.99)],
    )
    ORDERS[o.id] = o


_seed()


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


@app.get("/orders", response_model=list[Order])
def list_orders(status: OrderStatus | None = None) -> list[Order]:
    items = list(ORDERS.values())
    if status:
        items = [o for o in items if o.status == status]
    return items


@app.post("/orders", response_model=Order, status_code=status.HTTP_201_CREATED)
def create_order(new: NewOrder) -> Order:
    order = Order(
        id=f"ord-{next(_ids)}",
        customerId=new.customerId,
        status="pending",
        total=round(sum(i.quantity * i.unitPrice for i in new.items), 2),
        currency=new.currency.upper(),
        items=new.items,
    )
    ORDERS[order.id] = order
    return order


@app.get("/orders/{order_id}", response_model=Order)
def get_order(order_id: str) -> Order:
    order = ORDERS.get(order_id)
    if order is None:
        raise HTTPException(status_code=404, detail={"code": "NotFound", "message": f"order '{order_id}' not found"})
    return order
