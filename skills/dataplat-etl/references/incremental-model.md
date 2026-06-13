# Idempotent incremental model with backfill-safe windowing

dbt-flavored SQL; the pattern (merge on a unique key → window on the logical
date → trailing lookback for late data) is identical in raw Spark or SQL ELT.

```sql
-- models/marts/fct_orders.sql
{{
  config(
    materialized = 'incremental',
    unique_key   = 'order_id',          -- merge, not append: re-runs are no-ops
    incremental_strategy = 'merge',
    partition_by = {'field': 'order_date', 'data_type': 'date'},
  )
}}

with source as (

    select * from {{ ref('stg_shop__orders') }}

    {% if is_incremental() %}
    -- Lookback window: reprocess the trailing N days so late-arriving and
    -- updated rows are healed on every run. Tune via var, default 3 days.
    where order_date >= date_sub(
        {{ var('data_interval_end', 'current_date') }},
        interval {{ var('lookback_days', 3) }} day)
      and order_date <  {{ var('data_interval_end', 'current_date') }}
    {% endif %}

)

select
    order_id,
    customer_id,
    order_date,
    status,
    amount_cents,
    loaded_at
from source
```

Backfill any historical window without touching the model:

```bash
# The scheduler passes its logical window through; the model never calls now().
dbt run -s fct_orders \
  --vars '{data_interval_end: "2026-03-01", lookback_days: 30}'

# Periodic heal for schema/logic drift accumulated in the incremental table:
dbt run -s fct_orders --full-refresh   # schedule weekly/monthly, off-peak
```

## Idempotency test checklist

- [ ] Run the same window twice → row count and aggregates identical (assert on
      the target table, not on job success)
- [ ] Kill the job mid-run, retry → no duplicates (merge key absorbs partials)
- [ ] Inject a row whose `order_date` is 2 days old → next scheduled run picks
      it up via the lookback
- [ ] Update an existing source row inside the lookback → target reflects the
      new values (merge, not insert-only)
- [ ] Backfill an old window → rows outside that window untouched
- [ ] `--full-refresh` result matches the incrementally-built table (drift
      detector; diff aggregates per partition)
