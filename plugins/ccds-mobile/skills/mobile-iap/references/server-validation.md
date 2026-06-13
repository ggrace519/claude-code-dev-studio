# Server-side IAP validation and entitlement skeleton

TypeScript-flavored; the pattern (verify signed payload → dedupe by original
transaction ID → derive entitlement from current store state → durable grant →
acknowledge/finish) is the same for App Store Server Notifications V2 and Play
RTDN — only the verification step differs.

```ts
// --- Path 1: client reports a purchase (StoreKit 2 / Play Billing) ---------
app.post("/iap/verify", async (req, res) => {
  // 1. Verify the signed payload SERVER-SIDE. Never trust client-decoded JSON.
  //    iOS: verify the JWS chain (x5c → Apple root) or call the App Store
  //    Server API with the transaction ID. Android: purchases.subscriptionsv2
  //    .get via the Play Developer API with the purchase token.
  const tx = await store.verifyAndFetchCurrent(req.body.platform, req.body.token);
  if (!tx) return res.status(400).send("invalid transaction");

  // 2. Idempotent grant keyed on ORIGINAL transaction ID (iOS) / first purchase
  //    token in the linked chain (Android). Restore, retries, and the
  //    notification race all hit this same key.
  const granted = await grantEntitlement(tx);
  res.json({ entitled: granted.active, expiresAt: granted.expiresAt });
  // 3. Client finishes/acknowledges ONLY after this 200. Play auto-refunds
  //    unacknowledged purchases after 3 days; finishing early loses the sale
  //    if the server write failed.
});

// --- Path 2: store-to-server notifications (ASSN V2 / RTDN) ----------------
app.post("/iap/notifications/:platform", async (req, res) => {
  const event = await store.verifyNotification(req.params.platform, req.body);
  if (!event) return res.status(401).send("bad signature");
  res.status(200).send("ok"); // ack fast; process async

  // Out-of-order defense: ignore the notification's snapshot. Fetch the
  // CURRENT subscription state from the store API and derive from that.
  await queue.enqueue("iap-event", { originalTxId: event.originalTransactionId,
    platform: req.params.platform });
});

async function processIapEvent({ originalTxId, platform }: Job) {
  const sub = await store.fetchSubscriptionStatus(platform, originalTxId);
  // One pure, unit-testable function: store state -> entitlement.
  const ent = entitlementFor(sub.productId, sub.state, sub.expiresAt);
  await db.tx(async (t) => {
    await t.entitlements.upsert({ key: originalTxId, userId: sub.appAccountToken, ...ent });
    await t.entitlementVersion.increment(sub.appAccountToken);
  });
}
```

`entitlementFor` state mapping: `active` / `grace_period` → entitled;
`billing_retry` / `account_hold` → policy choice (default: not entitled at
hold); `expired` / `revoked` / `refunded` → not entitled, effective at the
store-provided timestamp.

## Reconciliation job (daily)

For each entitlement row near or past `expiresAt`, re-fetch store status; diff
against the DB; auto-heal mismatches and emit a metric. Alert if mismatch rate
exceeds ~0.1% — that means notifications are being dropped.

## Failure-mode test checklist

- [ ] Same transaction submitted twice (client verify + notification) → one grant
- [ ] Refund notification after the client already verified → entitlement revoked
- [ ] Restore on a fresh install → original transaction found, no duplicate row
- [ ] Server down when client purchases → purchase recovered on next launch
      (unfinished StoreKit transaction / unacknowledged Play purchase replayed)
- [ ] Upgrade mid-period → old product's entitlement replaced, not stacked
- [ ] Notification arrives before the client verify call → both paths converge
      on the same row
