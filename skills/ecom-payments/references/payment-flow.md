# Idempotent auth → capture → refund skeleton

Stripe-flavored TypeScript; the pattern (stable idempotency keys derived from
your order, webhook-driven state, transition guard, refund accounting) is the
same for Adyen, Braintree, and PayPal.

```ts
// 1. AUTH at order placement — capture deferred until shipment.
//    Idempotency key derived from YOUR order ID, so a retried request
//    (timeout, double-click, job retry) returns the same intent.
async function authorize(order: Order) {
  return stripe.paymentIntents.create(
    {
      amount: order.totalMinor,            // integer minor units, never floats
      currency: order.currency,
      capture_method: "manual",            // auth now, capture at ship
      customer: order.gatewayCustomerId,
      metadata: { orderId: order.id },     // the join key for reconciliation
    },
    { idempotencyKey: `auth:${order.id}` },
  );
}

// 2. CAPTURE at ship — possibly partial (split shipment).
//    Key includes the shipment ID so each split captures exactly once.
async function captureForShipment(order: Order, shipment: Shipment) {
  assertTransition(order.paymentState, "captured");   // guard, see step 4
  return stripe.paymentIntents.capture(
    order.paymentIntentId,
    { amount_to_capture: shipment.amountMinor },
    { idempotencyKey: `capture:${order.id}:${shipment.id}` },
  );
}

// 3. REFUND — check cumulative prior refunds first; over-refund is a
//    finance incident, not a 400 from the gateway (some gateways allow it).
async function refund(order: Order, amountMinor: number, reasonId: string) {
  const alreadyRefunded = await db.refunds.sumFor(order.id);
  if (alreadyRefunded + amountMinor > order.capturedMinor) {
    throw new OverRefundError(order.id);
  }
  return stripe.refunds.create(
    { payment_intent: order.paymentIntentId, amount: amountMinor },
    { idempotencyKey: `refund:${order.id}:${reasonId}` },
  );
}

// 4. WEBHOOK is the single writer of payment state. Verify against the RAW
//    body, dedupe by event ID, and guard transitions so an out-of-order or
//    replayed event can't regress state (e.g. refunded → captured).
const ALLOWED: Record<PaymentState, PaymentState[]> = {
  requires_action: ["authorized", "failed"],
  authorized: ["captured", "partially_captured", "voided", "expired"],
  captured: ["refunded", "partially_refunded", "disputed"],
  // terminal states allow nothing
};

function assertTransition(from: PaymentState, to: PaymentState) {
  if (!ALLOWED[from]?.includes(to)) throw new IllegalTransition(from, to);
}
```

## Failure-mode test checklist

- [ ] Auth request retried (same key) → one intent, one hold on the card
- [ ] Capture webhook delivered twice → order ships once, ledger has one entry
- [ ] Capture attempted after auth expiry (~7 days) → reauth path taken, not a silent failure
- [ ] Two partial refunds whose sum exceeds the capture → second is rejected locally
- [ ] `charge.refunded` replayed after a later `charge.dispute.created` → state stays `disputed`
- [ ] Redirect return hits the success page but webhook never arrives → order remains pending, alert fires
- [ ] Daily reconciliation run against a settlement report with one injected missing transaction → delta flagged
