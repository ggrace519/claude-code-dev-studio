---
name: ai-safety
description: AI content safety and prompt-injection defense specialist. Auto-invoked when user-generated input reaches an LLM, when tools are exposed to an agent, or when content filters, refusal policies, and jailbreak defenses are being designed.
---

# AI Safety

Every user-controlled string that reaches an LLM is an attack surface — user
messages, retrieved chunks, tool outputs, file contents. No single filter holds;
defense is layered.

## When to reach for this

- User-generated or third-party content flows into a prompt (chat, RAG, email, web pages)
- An agent gets tools that act — file writes, payments, messages, code execution
- Designing content filters, refusal policy, or a jailbreak/injection red-team suite
- Model output is rendered, executed, or sent onward without a human in the loop

## Principles

1. **Treat all model input as untrusted.** Retrieved chunks and tool outputs are
   injection vectors exactly like user messages — delimit them in tagged blocks
   and instruct the model they are data, not instructions.
2. **Privilege separation.** The context that decides "should this tool run" must
   not be steerable by the content the tool returns; where stakes warrant, keep
   planning and content-consumption in separate model calls.
3. **Confirmations gate side effects.** Irreversible or external actions (writes,
   sends, payments) require explicit user confirmation or a pre-approved policy —
   plus a kill switch that stops the agent mid-run.
4. **Least-capability tools.** Read-only by default, allowlist over blocklist,
   validated arguments, per-session credentials over standing ones.
5. **Post-filter what you can't pre-prevent.** Output filtering (secret/PII
   patterns, content classifier) is the last line — assume some injections get
   through the prompt layer.
6. **Red-team in CI.** An adversarial set (injections, jailbreaks, exfil attempts)
   runs on every prompt/model change, exactly like the quality golden set.
7. **Log refusals and near-misses.** Refusal rate is a product metric, and blocked
   injection attempts are free threat intel — feed them back into the red-team set.

## Layered defense checklist

- [ ] Untrusted content delimited/tagged; system prompt asserts the data-vs-instruction boundary
- [ ] Input pre-filter for known injection patterns and policy-violating content
- [ ] Tool schemas minimal: scoped capabilities, validated arguments, allowlisted targets
- [ ] Side-effecting tools behind confirmation or policy approval; kill switch wired
- [ ] Output post-filter: secret/PII patterns (keys, tokens, emails) and unsafe-content classifier
- [ ] Rendered model output sanitized — remote images and links in markdown/HTML are exfiltration channels
- [ ] No secrets in the system prompt (anything in context can be exfiltrated)
- [ ] Red-team suite in CI with a pass-rate gate; failures triaged into a taxonomy
- [ ] Refusal rate, filter-hit rate, and blocked-injection counts dashboarded with alerts
- [ ] Residual risk written down — what the current layers do **not** cover

## Pitfalls

- Defending the user message while trusting RAG chunks and tool outputs
- "The system prompt says to ignore injected instructions" treated as sufficient —
  it's one layer, and the weakest one
- Model output rendered as markdown with remote images enabled — the classic
  exfil channel for injected instructions
- Static red-team set while attacks evolve; fold real blocked attempts back in
- Refusal policy tuned only against attacks, regressing benign traffic — track
  false-refusal rate alongside attack pass rate
- Safety filters applied at one entry point while a second code path reaches the
  model unfiltered

---
*Related: `ai-prompt-engineer` (delimiting and prompt structure), `ai-eval`
(red-team harness in CI), `security-checklist` (application-layer security and
severity rating) · domain agent: `ai-architect` (data policy) · output/ADR
format: `playbook-conventions`*
