---
name: ecom-inventory
description: Inventory and fulfillment specialist. Owns inventory model (on-hand, reserved, available-to-sell), multi-location allocation, reservation TTLs, oversell prevention, and OMS/WMS integration. Auto-invoked for inventory, stock, allocation, or fulfillment code.
---

# E-commerce Inventory

Overselling is a trust-breaking failure; undersupply is silent lost revenue.
Inventory must stay correct during traffic spikes, with stale caches and async
writes in play — the happy path is never where it breaks.

## When to reach for this

- Designing or changing the inventory model (on-hand / reserved / available-to-sell)
- Writing reservation, allocation, or stock-decrement code paths
- Debugging an oversell or a phantom out-of-stock
- Wiring OMS / WMS / ERP sync jobs and deciding which system is truth

## Principles

1. **Atomic decrement, never read-then-write.** Use a row lock, atomic counter,
   or compare-and-swap (`UPDATE ... SET available = available - 1 WHERE available >= 1`
   and check rows-affected). Two concurrent checkouts reading the same count is
   the canonical oversell.
2. **Reservations carry a TTL.** A cart hold without expiry is a slow stockout.
   Typical holds: 10–20 minutes from checkout-start; expired reservations
   auto-release via a sweeper, not via the next read.
3. **Allocate at order confirm, not add-to-cart** — unless the SKU is scarce or
   the business promises cart-level holds (ticketing, drops). Cart-time
   allocation multiplies reserved stock by abandonment rate (~70% of carts).
4. **Buffer scarce SKUs.** Keep a small safety-stock buffer (even 1–2 units) so
   concurrent check+decrement races degrade to "sold out one unit early," not
   oversold.
5. **One source of truth per timescale.** OMS/commerce DB is truth in real time;
   ERP/WMS is truth at reconciliation. Nightly recon compares the two and the
   *delta report* is a first-class artifact, not a log line.

## Reservation lifecycle

| State | Entered on | Stock effect | Exits via |
|---|---|---|---|
| `available` | recon / restock / release | counts toward ATS | reservation created |
| `reserved (soft)` | checkout-start (or add-to-cart for scarce SKUs) | excluded from ATS | confirm, TTL expiry, cart abandon |
| `allocated` | order confirmed + payment authorized | committed; picks against a location | shipment, cancel |
| `shipped` | WMS ship confirm | decrements on-hand | — |
| `released` | TTL sweep / cancel / payment failure | returns to ATS atomically | — |

Allocation rules to decide explicitly (and record as an ADR): location-selection
priority (proximity vs stock depth vs cost), split-shipment threshold, and
backorder policy per SKU class.

## Pitfalls

- Computing available-to-sell in application code from cached on-hand minus
  cached reservations — derive it in one query or one materialized counter
- Releasing reservations only on user action; abandoned sessions never fire one
- Decrementing at payment capture instead of authorization — a capture-at-ship
  flow can oversell for days
- Treating the ERP nightly sync as authoritative intraday (it's hours stale)
- Tests that never run two checkouts concurrently against the last unit

---
*Related: `ecom-payments` (auth/capture timing drives allocation timing),
`ecom-search-merch` (how stock status surfaces in results),
`ecom-storefront-perf` (caching stock badges) · domain agent: `ecom-architect`
(order/checkout boundary, OMS topology) · output/ADR format: `playbook-conventions`*
