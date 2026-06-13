# Double-entry ledger schema skeleton

Postgres-flavored SQL; the pattern (append-only journal → balancing entries →
derived balances → idempotent posting) is identical for MySQL or a
ledger-as-a-service backend.

```sql
CREATE TABLE accounts (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  path        text NOT NULL UNIQUE,          -- e.g. 'liability:customer:42'
  type        text NOT NULL CHECK (type IN ('asset','liability','equity','revenue','expense')),
  currency    char(3) NOT NULL,              -- ISO 4217; one currency per account
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE transactions (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  idempotency_key  text NOT NULL UNIQUE,     -- replay returns the original row
  description      text NOT NULL,
  reverses_tx_id   bigint REFERENCES transactions(id),  -- set for compensating entries
  posted_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE entries (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tx_id       bigint NOT NULL REFERENCES transactions(id),
  account_id  bigint NOT NULL REFERENCES accounts(id),
  -- Integer minor units (cents, satoshi, ...). Positive = debit, negative = credit.
  amount      bigint NOT NULL CHECK (amount <> 0),
  currency    char(3) NOT NULL               -- must match the account's currency
);

-- Append-only: enforce in the database, not by convention.
CREATE OR REPLACE FUNCTION forbid_mutation() RETURNS trigger AS $$
BEGIN RAISE EXCEPTION 'ledger is append-only'; END $$ LANGUAGE plpgsql;
CREATE TRIGGER entries_immutable BEFORE UPDATE OR DELETE ON entries
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
CREATE TRIGGER tx_immutable BEFORE UPDATE OR DELETE ON transactions
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();

-- Sum-to-zero per transaction per currency: deferred constraint trigger,
-- checked at COMMIT so multi-row inserts can complete first.
CREATE OR REPLACE FUNCTION check_tx_balanced() RETURNS trigger AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM entries WHERE tx_id = NEW.tx_id
             GROUP BY currency HAVING sum(amount) <> 0) THEN
    RAISE EXCEPTION 'transaction % does not balance', NEW.tx_id;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE CONSTRAINT TRIGGER tx_balanced AFTER INSERT ON entries
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION check_tx_balanced();
```

```sql
-- Balance = projection over entries. As-of queries fall out for free.
SELECT coalesce(sum(e.amount), 0) AS balance_minor_units
FROM entries e
JOIN transactions t ON t.id = e.tx_id
WHERE e.account_id = $1
  AND t.posted_at <= $2;   -- omit for current balance
```

Posting flow: `INSERT transactions ... ON CONFLICT (idempotency_key) DO NOTHING`;
if no row was inserted, fetch and return the existing transaction (replay).
Otherwise insert all entries in the same database transaction and commit — the
deferred trigger rejects unbalanced postings atomically.

## Invariant test checklist

- [ ] Every committed transaction sums to zero per currency (property test over the whole journal, not just new code paths)
- [ ] Same idempotency key posted twice → one transaction, identical response both times (run the two requests concurrently)
- [ ] UPDATE or DELETE against `entries`/`transactions` raises, even as the app role
- [ ] Reversal links `reverses_tx_id` and mirrors every entry; original remains visible
- [ ] Cached/materialized balances reconcile against the journal projection (scheduled job, alert on any mismatch)
- [ ] Cross-currency transfer produces balanced legs in *both* currencies through an FX account
- [ ] Rounding remainders land in the rounding account, never silently dropped
