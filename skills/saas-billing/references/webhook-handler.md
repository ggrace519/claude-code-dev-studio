# Idempotent provider-webhook handler skeleton

Stripe-flavored TypeScript; the pattern (verify raw body → dedupe by event ID →
fetch current state → derive entitlements → invalidate cache) is identical for
Paddle, Lago, and Chargebee.

```ts
// Route registration must give this handler the RAW body — a JSON body-parser
// upstream breaks signature verification.
app.post("/webhooks/stripe", express.raw({ type: "application/json" }), handle);

async function handle(req: Request, res: Response) {
  // 1. Verify signature against the raw body (Stripe tolerance: 300s).
  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(
      req.body, req.headers["stripe-signature"]!, env.STRIPE_WEBHOOK_SECRET);
  } catch {
    return res.status(400).send("bad signature");
  }

  // 2. Dedupe by provider event ID. INSERT ... ON CONFLICT DO NOTHING and
  //    bail if the row already existed — duplicates are normal, not errors.
  const fresh = await db.webhookEvents.insertIgnore({ id: event.id, type: event.type });
  if (!fresh) return res.status(200).send("duplicate");

  // 3. Acknowledge fast; process async. Providers retry on slow responses,
  //    which manufactures the duplicates step 2 exists to absorb.
  res.status(200).send("ok");
  await queue.enqueue("billing-event", { eventId: event.id, type: event.type,
    subscriptionId: extractSubscriptionId(event) });
}

async function processBillingEvent({ subscriptionId }: Job) {
  // 4. Out-of-order defense: ignore the event payload's snapshot entirely.
  //    Fetch the CURRENT subscription state and derive from that.
  const sub = await stripe.subscriptions.retrieve(subscriptionId);

  // 5. Derive entitlements from the price ID — one pure function, unit-testable.
  const entitlements = entitlementsForPrice(sub.items.data[0].price.id, sub.status);

  // 6. Upsert + invalidate in one transaction; bump a version so concurrent
  //    readers can't resurrect a stale cache entry.
  await db.tx(async (t) => {
    await t.entitlements.upsert({ customerId: sub.customer as string, ...entitlements });
    await t.entitlementVersion.increment(sub.customer as string);
  });
  await cache.del(`entitlements:${sub.customer}`);
}
```

## Failure-mode test checklist

- [ ] Same event delivered twice → second is a no-op (assert on side effects, not status code)
- [ ] `subscription.updated` (old snapshot) arriving *after* `subscription.deleted` → state stays canceled
- [ ] Signature invalid / body re-serialized → 400, nothing persisted
- [ ] `invoice.payment_failed` → access retained through grace period, revoked after
- [ ] Provider API down during processing → job retries; webhook row does not block redelivery forever (TTL or status column)
- [ ] Entitlement cache read between upsert and invalidation → version check prevents stale write-back
