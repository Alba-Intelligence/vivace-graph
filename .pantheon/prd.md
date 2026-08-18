# Product Requirements Document: Graph Embeddings in VivaceGraph

## Problem
VivaceGraph lacks native support for vector embeddings on nodes, edges, and subgraphs. Users cannot store, index, or query semantic representations alongside graph structure. This blocks use cases requiring similarity search, entity resolution, link prediction, and ML-driven graph analytics.

Current workaround: external vector stores (pgvector, Pinecone, etc.) with manual sync — fragile, slow, loses ACID guarantees.

## Users
1. **Lisp application developers** embedding VivaceGraph — need `def-vertex` slots for vectors, transactional `save`/`update`, Prolog queries combining graph + vector predicates.
2. **Data scientists in REPL** — need interactive loading of pre-computed embeddings (BERT, SentenceTransformers, etc.), similarity search, clustering, visualization hooks.
3. **External services via REST** — need `/embeddings/similar`, `/embeddings/knn`, `/embeddings/project` endpoints with JSON I/O.
4. **ML engineers** — need pipeline: graph → external model (PyTorch/TensorFlow) → embeddings back into VivaceGraph → downstream graph queries.

All users expect ACID, mmap-based persistence, and integration with existing schema/index/view machinery.

## Goals
**Phase 1 (MVP)** — Node embeddings only
- Store dense vectors (f32/f64) as typed slots on vertices via `def-vertex`
- Linear-hash + HNSW/IVF index for ANN search (cosine, L2, dot)
- `select` / Prolog predicates: `knn/3`, `similar/3`, `vector/2`
- Transactional insert/update/delete with WAL durability
- REST endpoints for KNN and similarity
- Unit tests + 2 tutorials: (a) NER + entity resolution on CoNLL-2003, (b) Financial forecasting on synthetic transaction graph

**Phase 2** — Edge embeddings
- `def-edge` vector slots
- Edge-level similarity, path embedding composition
- Tutorial: Relationship classification on FewRel

**Phase 3** — Graph/subgraph embeddings
- Whole-graph pooling (mean, attention, Set2Set)
- Subgraph sampling + embedding
- Tutorial: Drug discovery on MoleculeNet / OGB-MolPCBA

**Cross-cutting**
- Columnar vector storage (SOA layout) for SIMD-friendly similarity search
- HNSW index persisted in mmap (compatible with allocator/linear-hash)
- Benchmarks vs. TigerGraph on 100k nodes / 1M edges / 128-dim / CPU-only

## Non-Goals
- Training GNNs inside VivaceGraph (Node2Vec, GraphSAGE, GAT) — external only for Phase 1-3
- GPU acceleration — CPU SIMD (AVX2/AVX-512) only
- Distributed/cluster ANN — single-node mmap
- Binary quantization / PQ — full precision f32/f64 first
- AutoML / hyperparameter tuning

## Success Metrics
| Metric | Target |
|--------|--------|
| ANN recall@10 (100k nodes, 128-dim, HNSW M=16, ef=200) | ≥ 0.95 |
| KNN latency (p99, 100k nodes) | < 10 ms |
| Insert throughput (1M vectors, batched, sync) | > 50k vec/s |
| Index build time (1M vectors) | < 5 min |
| Disk overhead vs. raw vectors | < 2.5x (HNSW graph + vectors) |
| Tutorial runtime (end-to-end) | < 5 min each |

## Constraints
1. **On-disk format**: mmap + allocator + linear-hash + ve-index unchanged. New vector columnar segment files (`vectors.dat`, `hnsw.dat`) must coexist.
2. **MOP integration**: Vector slots behave like other typed slots — `def-vertex` `:vector` type, `make-instance`, `save`, `update-node`, `delete-node` all work.
3. **Transactions**: Vector writes participate in read-set/write-set validation; HNSW index updates are logged for recovery.
4. **Prolog**: New functors `knn/3`, `similar/3`, `vector/2` compile to efficient index scans.
5. **Schema**: Per-class rw-locks extend to vector columns; `def-view` supports vector aggregations.
6. **References**: Study `overgraph` (columnar + HNSW in Go) and `ArcadeDB` (multi-model, vector index) for layout patterns.
7. **Implementations**: SBCL (primary), ECL, LispWorks. CCL Linux only. No FFI to C++ HNSW — pure Lisp or minimal CFFI to `hnswlib`.

## Open Questions
1. **HNSW implementation**: Pure Common Lisp (port `hnswlib` logic) vs. CFFI to `hnswlib` vs. `faiss`? CFFI adds deployment complexity; pure Lisp fits VivaceGraph ethos but needs perf validation.
2. **Vector dimension limits**: Fixed per-schema (declare in `def-vertex`) or dynamic? Fixed enables columnar SOA; dynamic needs jagged arrays.
3. **Index persistence format**: HNSW graph as separate linear-hash (node-id → neighbor list) or custom mmap segment? Affects recovery complexity.
4. **Similarity metrics**: Cosine, L2, dot product — all three in Phase 1?
5. **REST pagination**: Cursor-based for large KNN results?
6. **Benchmark dataset**: Use OGB-Products (2.4M nodes) or synthetic? TigerGraph benchmarks use LDBC SNB — replicate subset?
7. **Tutorial data licensing**: CoNLL-2003 (free), FewRel (free), MoleculeNet (free) — confirm redistribution rights for demo bundle.
8. **ECL compatibility**: `defstruct` setf expanders, no custom hash tests — vector index must use `equalp` keys.