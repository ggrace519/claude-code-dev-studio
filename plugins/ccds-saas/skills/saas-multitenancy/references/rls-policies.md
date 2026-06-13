# Postgres RLS policy set for pooled multitenancy

The complete pattern: role setup, session-variable binding, per-command policies,
connection-pool hygiene, and the negative tests that prove it holds. Postgres-flavored;
the structure (bind context per transaction → policy filters every command → app role
cannot bypass) maps to SQL Server's `SESSION_CONTEXT` + security policies.

## Role setup — where most RLS deployments silently fail

```sql
-- RLS does not apply to superusers, ever, and not to the table owner or
-- BYPASSRLS roles unless forced. The app must connect as none of those.
CREATE ROLE app_user LOGIN PASSWORD '...' NOSUPERUSER NOBYPASSRLS;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_user;

ALTER TABLE app.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.projects FORCE ROW LEVEL SECURITY;  -- covers the owner too
```

## Policies

```sql
-- Fail closed: current_setting(..., true) returns NULL when unset, and
-- `tenant_id = NULL` is never true → zero rows, not an error page and not a leak.
CREATE POLICY tenant_select ON app.projects FOR SELECT
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- WITH CHECK guards writes: without it, a tenant could INSERT/UPDATE rows
-- carrying another tenant's ID even though they can't read them back.
CREATE POLICY tenant_insert ON app.projects FOR INSERT
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_update ON app.projects FOR UPDATE
  USING      (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_delete ON app.projects FOR DELETE
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
```

## Binding tenant context — middleware and jobs

```ts
// One transaction per unit of work; SET LOCAL dies with the transaction, so
// transaction-mode pooling (PgBouncer) can never leak context between requests.
// Plain SET would persist on the pooled connection — that is the classic leak.
async function withTenant<T>(tenantId: string, fn: (tx: Tx) => Promise<T>) {
  if (!isUuid(tenantId)) throw new Error("invalid tenant context"); // fail closed
  return db.tx(async (tx) => {
    // Parameterized via format/quoting helper — SET LOCAL takes no bind params.
    await tx.none("SELECT set_config('app.tenant_id', $1, true)", [tenantId]);
    return fn(tx);
  });
}

// HTTP: tenant ID from the authenticated session only.
app.use((req, _res, next) => { req.tenantId = req.session.tenantId; next(); });

// Jobs: the payload carries tenant_id; the worker re-binds per job.
worker.process(async (job) => withTenant(job.data.tenantId, (tx) => run(job, tx)));
```

Indexing: the policy predicate adds `tenant_id = $X` to every query — composite
indexes must lead with `tenant_id` or every lookup degrades to a wider scan.

## Negative-test checklist

Run these as the `app_user` role against a seeded two-tenant fixture:

- [ ] SELECT with tenant A bound returns zero tenant-B rows (assert on count, not error)
- [ ] SELECT with **no** tenant bound returns zero rows (fail-closed check)
- [ ] INSERT/UPDATE attempting to set `tenant_id` = tenant B fails the `WITH CHECK`
- [ ] UPDATE ... WHERE id = <tenant B's row id> affects 0 rows
- [ ] Two sequential requests on the **same pooled connection** with different
      tenants each see only their own rows (catches `SET` vs `SET LOCAL`)
- [ ] A background job processed without explicit binding fails or returns nothing
- [ ] `SELECT current_user;` in CI asserts the app role is not the table owner and
      `rolbypassrls` is false
- [ ] EXPLAIN on the hottest tenant-scoped query confirms the tenant-leading index
      is used with the policy applied (the performance-tax check)

## Escape hatch: audited cross-tenant access

Never disable RLS for admin tools. Add a separate, narrowly-granted policy keyed
to an explicit support context, and log every use:

```sql
CREATE POLICY support_read ON app.projects FOR SELECT
  USING (current_setting('app.support_actor', true) IS NOT NULL);
-- Application layer: setting app.support_actor requires an authorization check
-- and writes an audit row (actor, target tenant, reason, timestamp) first.
```
