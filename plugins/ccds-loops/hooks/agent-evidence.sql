-- ccds-loops durable evidence sink (Primitive 4, durable tier).
--
-- Canonical DDL for the optional Postgres mirror of .claude/evidence/*.json.
-- The PostToolUse hook (posttooluse-evidence-log.py) runs this idempotently
-- before each INSERT, so the table self-provisions on first write. You can also
-- apply it by hand:  psql "$CCDS_EVIDENCE_DSN" -f agent-evidence.sql
--
-- Connection is via the CCDS_EVIDENCE_DSN env var ONLY — no credentials live in
-- this repo. The durable tier is entirely optional: unset the DSN (or lack psql)
-- and the mirror no-ops, keeping ccds stack-agnostic.

CREATE TABLE IF NOT EXISTS agent_evidence (
  id       bigserial PRIMARY KEY,
  cycle_id text NOT NULL,
  ts       timestamptz NOT NULL DEFAULT now(),
  task     text,
  verdict  text CHECK (verdict IN ('PASS','FAIL')),
  proof    jsonb,
  agent    text
);
CREATE INDEX IF NOT EXISTS idx_agent_evidence_verdict_ts
  ON agent_evidence (verdict, ts);
