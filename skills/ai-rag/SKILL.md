---
name: ai-rag
description: Retrieval-augmented generation specialist. Auto-invoked when retrieval, chunking, embeddings, reranking, hybrid search, or RAG evaluation is being built.
---

# AI RAG

The retrieval layer is the single largest source of quality delta in most LLM
apps. Better retrieval beats better prompts, consistently — and retrieval work
without labeled eval pairs is vibes.

## When to reach for this

- Designing or changing chunking, embedding, indexing, or reranking
- Retrieval quality complaints ("the model ignores our docs") — usually recall, not the prompt
- Building the ingestion pipeline (extraction, dedupe, freshness)
- Standing up retrieval evals before/after a pipeline change

## Principles

1. **Chunk for the retrieval question, not the document.** The chunk is the unit
   that gets retrieved and judged — optimize its self-containedness for that.
2. **Hybrid beats dense-only.** BM25 + embeddings + rerank is the default
   starting point, not the upgrade. Keyword search wins on IDs, names, and codes
   that embeddings smear.
3. **Rerank > more chunks.** A cross-encoder over top-50 beats a bigger embedding
   model over top-5, at a fraction of the cost of re-embedding the corpus.
4. **Eval with labeled pairs first.** Build query → expected-chunk pairs
   (50–200 is enough to start) before touching the pipeline, or you cannot tell
   improvement from noise.
5. **Freshness is a retrieval property.** Time-filter, dedupe superseded
   versions at ingestion, re-embed on source change — stale chunks outrank fresh
   ones because they've had longer to accumulate signal.
6. **Track context precision in production.** Log per-query-class whether the
   right chunk was in the served context; this is the metric that catches drift.

## Defaults that survive contact

| Knob | Starting point | Move when |
|---|---|---|
| Chunk size (prose) | 300–500 tokens, 10–15% overlap | answers span chunks → bigger; precision low → smaller |
| Chunk size (code/markdown) | structural — function / heading boundaries | fixed-size only as last resort |
| First-stage retrieval | hybrid, top-50 | recall@50 is fine but answers bad → fix rerank, not k |
| Rerank | cross-encoder top-50 → keep 5–8 | latency budget < ~150 ms → smaller reranker, not none |
| Query rewriting | off initially | multi-hop or conversational queries → multi-query / HyDE |
| Eval gate | recall@k and MRR on labeled pairs, run on every pipeline change | — |

## Pitfalls

- Tuning the generation prompt to compensate for bad retrieval (fix recall first)
- Comparing embedding models without holding chunking constant
- Dedupe skipped at ingestion — near-duplicate chunks crowd out diverse context
- Metadata filters applied after vector search truncate recall silently; filter
  in the index query, not in post-processing
- "We improved it" claims with no before/after recall@k on the same labeled set

---
*Related: `ai-prompt-engineer` (the prompt consuming retrieved context),
`ai-eval` (eval harness design), `ai-inference-perf` (latency budget) · domain
agent: `ai-architect` (serving topology, RAG-vs-finetune) · output/ADR format:
`playbook-conventions`*
