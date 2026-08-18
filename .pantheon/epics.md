# Epics: Graph Embeddings in VivaceGraph

Ordered by **first-shippable-value**. Each epic delivers a complete vertical slice a real user can use.

---

## Epic 1: HNSW Performance Spike (Go/No-Go)
**Value**: Decide pure-Lisp vs CFFI before investing in full implementation — avoids 3+ weeks of wasted work if pure Lisp cannot meet ≤2× `hnswlib` baseline.

**Architecture components**: `spikes/hnsw-perf.lisp` (new), SBCL `sb-simd` intrinsics validation.

**Definition of Done**:
- [ ] Minimal HNSW (insert + KNN search) implemented in pure Common Lisp
- [ ] Benchmark: 10k vectors, 128-dim, M=16, efC=200, efS=50 vs. `hnswlib` C++ baseline
- [ ] Metrics: recall@10, insert throughput, search latency (p50/p99)
- [ ] Decision recorded: pure Lisp ≤2× slower → proceed; >3× → CFFI path
- [ ] `disassemble` confirms SIMD vectorization on distance kernels

**Deferred**: Full HNSW persistence, WAL integration, concurrent access — all depend on this decision.

---

## Epic 2: Vector Columnar Storage + Schema/MOP Integration
**Value**: Lisp developers can define `def-vertex` with `:vector` slots, transact embeddings, and have them persisted durably — the foundation for all downstream query/index work.

**Architecture components**: `vectors.lisp` (new), `vector-slot.lisp` (new), `serialize.lisp` (extend), `schema.lisp` (extend `node-type`), `graph-db.asd` (add new files).

**Definition of Done**:
- [ ] `def-vertex` accepts `:vector` slot with `:dim`, `:element-type`, `:index`, `:metric`, `:index-params`
- [ ] Vector serialized to `vectors.dat` (SOA, 64-byte aligned, f32/f64)
- [ ] `vectors.idx` linear-hash maps node-id → {type-id, segment-offset, length}
- [ ] `make-<type>` / `save` / `update-node` / `delete-node` work with vector slots
- [ ] `lookup-<type>` materializes vector lazily (on first slot access)
- [ ] Schema persisted in `schema.dat` with `vector-slots` alist
- [ ] Per-class RW-lock covers vector column
- [ ] Unit tests: `tests/vector-tests.lisp` (serialize, deserialize, schema round-trip, dimension validation)
- [ ] ECL compatibility: no custom hash tests, `defstruct` setf expanders provided

**Deferred**: Vector segment compaction (GC pass for deleted vectors) — can live with holes initially; rebuild threshold configurable later.

---

## Epic 3: HNSW Index (Insert, Search, Persistence, WAL)
**Value**: ANN search works — users get KNN/threshold queries with ≥0.95 recall@10 and <10ms p99 latency on 100k nodes.

**Architecture components**: `hnsw.lisp` (new), `linear-hash.lisp` (reuse for neighbor lists), `transactions.lisp` (WAL logging for HNSW mutations), `allocator.lisp` (heap growth monitoring).

**Definition of Done**:
- [ ] `hnsw-insert(node-id, vector, metric)` — online insert with layer promotion
- [ ] `hnsw-knn-search(query-vec, k, metric, type-filter)` — greedy descent + ef-search
- [ ] `hnsw-range-search(query-vec, threshold, metric, type-filter)` — threshold search
- [ ] Neighbor lists persisted in main heap via linear-hash (node-id → serialized neighbors)
- [ ] `hnsw.meta` stores config per (vertex-type, metric): M, efConstruction, efSearch, dim, entry-point
- [ ] WAL logs: neighbor insert, neighbor delete, layer promotion, entry-point change
- [ ] Recovery: `recover-transactions` replays HNSW mutations, rebuilds affected subgraph
- [ ] RW-lock per (type, metric) — readers lock-free, writers exclusive
- [ ] Kill -9 during bulk insert → `open-graph` → `recover-transactions` → recall@10 ≥ 0.95
- [ ] Unit tests: `tests/hnsw-tests.lisp` (correctness, persistence, recovery, concurrent read/write)

**Deferred**: 
- Lazy deletion (tombstone neighbor lists) — start with eager rewire for recall; lazy as optimization
- Bulk-load (`hnsw-bulk-load`) — online insert sufficient for MVP; bulk-load for Phase 2
- IVF index alternative — HNSW only for Phase 1

---

## Epic 4: Prolog Vector Predicates
**Value**: Data scientists and Lisp developers query embeddings from REPL using familiar `select`/`knn`/`similar` syntax — composable with graph traversal, filtering, projection.

**Architecture components**: `prolog-vector.lisp` (new), `prologc.lisp` (compiler hooks), `prolog-functors.lisp` (register functors), `interface.lisp` (integration with `map-vertices`/`traverse`).

**Definition of Done**:
- [ ] `knn/3` modes: `(+Vec +K -Result)`, `(+NodeId +K -Result)` — compiles to `hnsw-knn-search`
- [ ] `similar/3` mode: `(+Vec +Threshold -Result)` — compiles to `hnsw-range-search`
- [ ] `vector/2` mode: `(+Node -Vec)` — retrieves stored vector from columnar store
- [ ] Compiler enforces: at least one of `+Vec`/`+NodeId` ground at call time
- [ ] Effect policy `:effects :read` — pure index read, no transaction required
- [ ] Composable: `(select (?doc ?title ?dist) (knn ?qvec 10 (?doc ?dist)) (title ?doc ?title) (filter ?title "Graph"))`
- [ ] Unit tests: `tests/prolog-vector-tests.lisp` (compilation modes, result binding, error cases)

**Deferred**: `knn-by-id/3` as separate functor — `knn/3` with `+NodeId` mode covers it.

---

## Epic 5: REST Vector Endpoints
**Value**: External services (Python, JS, etc.) call KNN/similarity via HTTP with JSON I/O — enables ML engineer pipelines and language-agnostic consumers.

**Architecture components**: `rest-vector.lisp` (new), `rest.lisp` (extend), JSON parsing/serialization, htpasswd auth reuse.

**Definition of Done**:
- [ ] `POST /graph/:graph/knn` — `{vector, k, metric, type, include?}` → JSON array or NDJSON stream
- [ ] `POST /graph/:graph/similar` — `{vector, threshold, metric, type, include?}` → JSON array
- [ ] `GET /graph/:graph/vector/:id` — returns `{id, type, vector, dim, slots...}`
- [ ] `POST /graph/:graph/vector/batch` — bulk upsert (transactional)
- [ ] Validation: vector length matches schema dim, metric/type exist, `k` ≤ 10000
- [ ] Auth: reuses existing htpasswd; 401/404/400/422/500 per UX spec
- [ ] `Accept: application/x-ndjson` → streaming for large K
- [ ] Unit tests: `tests/rest-vector-tests.lisp` (endpoints, auth, validation, streaming)
- [ ] Integration test: `tests/embedding-integration.lisp` (ingest via REST → query via REST)

**Deferred**: Cursor-based pagination for large K — NDJSON streaming covers MVP; cursor in Phase 2.

---

## Epic 6: Tutorial 1 — NER + Entity Resolution (CoNLL-2003)
**Value**: New users run one command, see end-to-end entity resolution with BERT embeddings, get F1 score — proves the system works for real NLP use case.

**Architecture components**: `tutorials/ner-entity-resolution.lisp` (new), `demo/` (data download script), external Python script (bundled), `example.lisp` (pattern).

**Definition of Done**:
- [ ] `(tutorial:run-ner-entity-resolution)` downloads CoNLL-2003 (cached), generates embeddings via bundled Python script (`sentence-transformers`), imports to VivaceGraph
- [ ] Defines `mention` vertex type with `:vector` slot (384-dim, HNSW, cosine)
- [ ] Runs entity resolution: `knn/3` k=20, threshold=0.15 → clusters mentions
- [ ] Evaluates against gold labels → prints F1, precision, recall
- [ ] Completes end-to-end in <5 min on modern laptop (SBCL)
- [ ] Failure handling: download fail → prints manual URL; Python missing → prints `pip install` command
- [ ] Synthetic fallback: if no internet, runs on tiny bundled dataset (100 mentions) with pre-computed embeddings

**Deferred**: Visualization hooks — text output sufficient for MVP; plotting in Phase 2.

---

## Epic 7: Tutorial 2 — Financial Forecasting (Synthetic Transaction Graph)
**Value**: Demonstrates graph embeddings for structured/tabular use case (churn prediction) — shows VivaceGraph handles non-NLP domains.

**Architecture components**: `tutorials/financial-forecasting.lisp` (new), synthetic data generator (Lisp), `example.lisp` (pattern).

**Definition of Done**:
- [ ] Generates synthetic transaction graph: accounts, transactions, merchants, timestamps
- [ ] Embeds accounts via external temporal GNN (Python script bundled, outputs JSONL)
- [ ] Imports to VivaceGraph with `account` vertex type + `:vector` slot
- [ ] Runs similarity search for churn prediction: `knn/3` on account embeddings
- [ ] Prints AUC-ROC / precision@k against synthetic labels
- [ ] Completes in <5 min; no external downloads required (fully synthetic)

**Deferred**: Real financial dataset (PCI/license issues) — synthetic sufficient for demo.

---

## Epic 8: Benchmarks + CI
**Value**: Published, reproducible numbers vs. TigerGraph — credibility for adoption; CI catches regressions.

**Architecture components**: `bench/bench-hnsw.lisp` (new), CI job (GitHub Actions / local script), `perf-test` system (reuse).

**Definition of Done**:
- [ ] Benchmark script: 100k / 1M nodes, 128-dim, cosine, M=16, efC=200, efS=50
- [ ] Metrics: recall@10, insert throughput (vec/s), search latency p50/p99, index build time, disk overhead
- [ ] Runs on CI (or documented local command: `sbcl --script bench/bench-hnsw.lisp`)
- [ ] Publishes exact hardware, SBCL version, OS, dataset (synthetic clusters)
- [ ] Targets: recall@10 ≥ 0.95, p99 < 10ms, insert > 50k vec/s, build < 5 min, disk < 2.5×
- [ ] Regression threshold: recall drop > 0.02 or latency increase > 20% fails CI

**Deferred**: Comparison against `pgvector`/`faiss` — TigerGraph is primary benchmark per PRD.

---

## Epic 9: Test Suite Hardening
**Value**: Confidence in correctness across SBCL/ECL/LispWorks — required for production use.

**Architecture components**: `tests/vector-tests.lisp`, `tests/hnsw-tests.lisp`, `tests/prolog-vector-tests.lisp`, `tests/rest-vector-tests.lisp`, `tests/embedding-integration.lisp` (new), `graph-db/test` system (extend).

**Definition of Done**:
- [ ] Unit: vector serialize/deserialize, schema round-trip, dimension validation
- [ ] Unit: HNSW insert/search correctness, persistence, recovery, concurrent access
- [ ] Unit: Prolog functor compilation modes, result binding, error cases
- [ ] Unit: REST endpoints, auth, validation, NDJSON streaming
- [ ] Integration: ingest → index → query → update → delete cycle (REPL + REST)
- [ ] Cross-implementation: test suite passes on SBCL, ECL 21.2.1, ECL 26.5.5, LispWorks
- [ ] Property-based: random vector insert/search vs. brute-force (QuickCheck-style)

**Deferred**: Concurrency stress tests under `graph-db/concurrent-stress-test` — add in Phase 2.

---

## Epic 10: Admin / Observability (Stretch)
**Value**: Operators monitor index health, diagnose recall regression, tune parameters — production readiness.

**Architecture components**: `hnsw-admin.lisp` (new), `rest-vector.lisp` (extend admin endpoints), log4cl structured logging.

**Definition of Done**:
- [ ] REPL: `(hnsw-stats *graph* :type 'document :metric :cosine)` → count, layers, memory, config
- [ ] REPL: `(hnsw-recall-test *graph* :type 'document :metric :cosine :sample 1000 :k 10)` → brute-force vs HNSW recall@1/5/10, latency
- [ ] REST: `GET /graph/:graph/admin/hnsw/:type/:metric` → JSON stats
- [ ] REST: `GET /graph/:graph/admin/hnsw/:type/:metric/recall` → recall test (admin only, expensive)
- [ ] Structured logs: `INFO HNSW insert 50000 vectors 12.3s (4065 vec/s) layers=3`
- [ ] Warning log: recall < 0.9 → "HNSW recall@10=0.87 < 0.95 target; consider increasing M or efConstruction"

**Deferred**: Dashboard/UI — REPL + REST + logs sufficient for MVP; Grafana dashboard in Phase 2.

---

## Deferred to Phase 2+ (Explicit Cuts)

| Item | Reason |
|------|--------|
| **Edge embeddings** (`def-edge` vector slots) | Separate phase per PRD; node embeddings unblock 80% of use cases |
| **Graph/subgraph embeddings** (pooling, Set2Set) | Requires graph algorithms add-on; Phase 3 |
| **Training inside VivaceGraph** (Node2Vec, GraphSAGE, GAT) | External models sufficient for MVP; training is separate product |
| **GPU acceleration** | Deployment complexity (ECL Android target); CPU SIMD target met |
| **Distributed/cluster ANN** | mmap architecture is single-node; separate project |
| **Binary quantization / PQ** | Full precision first; quantization adds decode overhead, recall drop |
| **IVF index alternative** | HNSW covers MVP; IVF for specific workloads later |
| **Bulk-load (`hnsw-bulk-load`)** | Online insert sufficient; bulk-load for large initial datasets |
| **Lazy deletion (tombstones)** | Eager rewire for recall; lazy as perf optimization |
| **Vector segment compaction (GC)** | Holes acceptable initially; rebuild threshold configurable later |
| **Cursor pagination for REST** | NDJSON streaming covers large K; cursor in Phase 2 |
| **Custom distance functions** | Cosine/L2/dot cover 95% cases; extensible via `:metric` function designator later |
| **Admin dashboard/Grafana** | REPL + REST + logs sufficient for MVP |
| **Tutorial visualizations** | Text output sufficient; plotting in Phase 2 |

---

## Dependency Graph

```
Epic 1 (Spike) ──────────────────┐
                                 ▼
Epic 2 (Storage + Schema) ◄──────┘  (go/no-go from spike)
        │
        ▼
Epic 3 (HNSW Index) ◄──────────────┐
        │                           │
        ▼                           │
Epic 4 (Prolog)  Epic 5 (REST) ────┘  (both depend on Epic 3)
        │                           │
        ▼                           ▼
Epic 6 (Tutorial 1)  Epic 7 (Tutorial 2)  (depend on 2+3+4 or 2+3+5)
        │                           │
        └───────────────┬───────────┘
                        ▼
              Epic 8 (Benchmarks)  (validates 3+4+5)
                        │
                        ▼
              Epic 9 (Test Suite)  (covers 2-5)
                        │
                        ▼
              Epic 10 (Admin)  (stretch, depends on 3)
```

---

## Ship Order (First-Shippable-Value)

1. **Epic 1** — Go/no-go gate. Blocks everything else.
2. **Epic 2** — Foundation. Shippable: developers can persist vectors (no search yet).
3. **Epic 3** — Core value. Shippable: ANN search works (REPL only).
4. **Epic 4** — Primary query interface. Shippable: `select` + `knn`/`similar` from REPL.
5. **Epic 5** — External access. Shippable: REST API for ML engineers.
6. **Epic 6** — Proof of value. Shippable: tutorial runs, prints F1.
7. **Epic 7** — Domain breadth. Shippable: second tutorial, different domain.
8. **Epic 8** — Credibility. Shippable: published benchmarks.
9. **Epic 9** — Production readiness. Shippable: test suite passes cross-impl.
10. **Epic 10** — Operability. Stretch: admin/observability.

Each epic 2–7 delivers a **user-visible milestone** without requiring the next.