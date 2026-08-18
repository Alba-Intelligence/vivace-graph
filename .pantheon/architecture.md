# Architecture: Graph Embeddings in VivaceGraph

## Components

### 1. Vector Columnar Storage (`vectors.lisp` — new)
**Responsibility**: SOA (Structure of Arrays) columnar storage for dense vectors, allocated from the existing mmap heap. One contiguous segment per vector dimension per vertex type.
- **Files**: `vectors.dat` (data), `vectors.idx` (linear-hash: node-id → {type-id, dim-offset, length})
- **Format**: Fixed-width f32/f64 arrays. Type declared in `def-vertex` (`:vector :dim 128 :element-type :single-float`).
- **Alignment**: 64-byte aligned for AVX-512; padding for SIMD tail handling.
- **Integration**: `serialize`/`deserialize` methods for new type tag `+embedding-vector+` (31); `make-serialized-key` routes to linear-hash.

### 2. HNSW Index (`hnsw.lisp` — new)
**Responsibility**: Hierarchical Navigable Small World graph for ANN search, persisted in mmap.
- **Files**: `hnsw.dat` (graph layers), `hnsw.meta` (config: M, efConstruction, efSearch, metric, dim)
- **Structure**: Layer 0 = all vectors; higher layers = exponentially sparser entry points. Each node: `node-id` + `neighbors[layer]` (variable-length uint32 arrays).
- **Persistence**: Separate allocator region (`hnsw-heap`) or embedded in main heap via linear-hash (node-id → neighbor list). Chosen: **embedded in main heap via linear-hash** — reuses existing allocator, single mmap window, simpler recovery.
- **Concurrency**: RW-lock per HNSW instance (per vertex-type × metric combo). Readers traverse lock-free (immutable layers after build); writers take write lock for insert/delete.
- **Recovery**: WAL logs HNSW mutations (insert neighbor, delete neighbor, layer promotion). On replay, rebuild affected subgraph.

### 3. Vector Slot Integration (`vector-slot.lisp` — new)
**Responsibility**: MOP integration so `:vector` slots behave like other typed slots.
- **Slot options**: `:dim` (required), `:element-type` (`:single-float` | `:double-float`), `:index` (NIL | `:hnsw` | `:ivf`), `:metric` (`:cosine` | :l2 | :dot), `:index-params` (plist: M, efConstruction).
- **Generated methods**: `make-<type>` accepts vector slot; `save`/`update-node` serialize to columnar store; `delete-node` removes from HNSW; `lookup-<type>` materializes vector lazily.
- **Schema registration**: Extends `node-type` struct with `vector-slots` alist (slot-name → config).

### 4. Prolog Vector Predicates (`prolog-vector.lisp` — new)
**Responsibility**: Compile-time translation of vector functors to efficient index scans.
- **Functors**:
  - `knn/3` `(?vec ?k ?result)` — K nearest neighbors of query vector `?vec` (bound or computed), binds `?result` to list of (node-id distance).
  - `similar/3` `(?vec ?threshold ?result)` — all vectors within distance `?threshold`.
  - `vector/2` `(?node ?vec)` — retrieve stored vector for node.
  - `knn-by-id/3` `(?node-id ?k ?result)` — KNN from stored vector of `?node-id`.
- **Compilation**: `prologc.lisp` detects these functors, emits calls to `hnsw-knn`/`hnsw-range` with bound variables resolved at runtime.
- **Effect policy**: `:effects :read` (pure index read).

### 5. REST Vector Endpoints (`rest-vector.lisp` — new)
**Responsibility**: HTTP API for external consumers.
- **Endpoints**:
  - `POST /graph/:graph/knn` — `{vector: [...], k: 10, metric: "cosine", type: "user"}` → `[{id, distance, slots...}]`
  - `POST /graph/:graph/similar` — `{vector: [...], threshold: 0.8, metric: "cosine"}` → `[{id, distance, slots...}]`
  - `GET /graph/:graph/vector/:id` — returns vector + metadata.
  - `POST /graph/:graph/vector/batch` — bulk insert/update vectors.
- **Serialization**: JSON arrays for vectors; `application/x-ndjson` streaming for large KNN results.
- **Auth**: Reuses existing htpasswd.

### 6. Tutorials & Benchmarks (`tutorials/`, `bench/` — new)
**Responsibility**: End-to-end runnable examples and performance validation.
- **Tutorial 1** (`ner-entity-resolution.lisp`): Load CoNLL-2003, embed with BERT (external Python script → JSONL), import, run entity resolution via `knn/3`, evaluate F1.
- **Tutorial 2** (`financial-forecasting.lisp`): Synthetic transaction graph, embed accounts with temporal GNN (external), similarity search for churn prediction.
- **Benchmarks**: `bench-hnsw.lisp` — 100k/1M nodes, 128-dim, recall@10, latency, throughput vs. TigerGraph published numbers.

---

## Data Flow

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  External   │────▶│  JSONL/CSV   │────▶│  make-<type>    │
│  Model      │     │  Import      │     │  (transaction)  │
│  (BERT,     │     │  (demo/)     │     └────────┬────────┘
│   Sentence  │     └──────────────┘              │
│   Transf.)  │                                   ▼
└─────────────┘                         ┌─────────────────┐
                                        │  serialize      │
                                        │  vector slot    │
                                        └────────┬────────┘
                                                 │
                    ┌────────────────────────────┼────────────────────────────┐
                    ▼                            ▼                            ▼
            ┌───────────────┐            ┌───────────────┐            ┌───────────────┐
            │ Columnar      │            │ HNSW Index    │            │ WAL /         │
            │ vectors.dat   │            │ (hnsw.dat)    │            │ txn-log       │
            │ (SOA, mmap)   │            │ (linear-hash) │            │ (durability)  │
            └───────┬───────┘            └───────┬───────┘            └───────┬───────┘
                    │                            │                            │
                    └────────────────────────────┴────────────────────────────┘
                                                 │
                                                 ▼
                                        ┌─────────────────┐
                                        │ Prolog Query    │
                                        │ knn/3, similar/3│
                                        │ vector/2        │
                                        └────────┬────────┘
                                                 │
                                                 ▼
                                        ┌─────────────────┐
                                        │ REST / REPL     │
                                        │ Results         │
                                        └─────────────────┘
```

**Transaction flow** (insert with vector):
1. `with-transaction` begins → read-set/write-set allocated.
2. `make-<type>` creates vertex instance; vector slot validated (dim, type).
3. `save` → `create-node`:
   - Allocates heap slot for node head (existing).
   - Serializes non-vector slots to heap (existing).
   - **Serializes vector to columnar segment** (new): appends to type-dim segment, records offset in `vectors.idx` linear-hash.
   - **Inserts into HNSW** (new): `hnsw-insert(node-id, vector, metric)` → traverses layers, updates neighbor lists, logs mutations to WAL.
4. Type index / VE index / VEV index updated (existing).
5. `commit` → validate read-set → write WAL record (including HNSW mutations) → fsync → release locks.

**Query flow** (`knn/3`):
1. Prolog compiler resolves `knn/3` → emits call to `hnsw-knn-search(query-vec, k, metric, type-filter)`.
2. `hnsw-knn-search`:
   - Entry point: top-layer nearest to query vector (linear scan of layer-L entry points).
   - Greedy descent: at each layer, explore neighbors, keep best `ef` candidates.
   - Layer 0: full ef-search with pruning.
   - Returns top-k (node-id, distance).
3. Optional: join with vertex slots (fetch `data` from heap) for projection.
4. Bind results to Prolog variables → continue unification.

---

## Interfaces & Contracts

### `def-vertex` Extension
```lisp
(def-vertex document ()
  ((title :type string)
   (embedding :type vector :dim 384 :element-type :single-float
              :index :hnsw :metric :cosine
              :index-params (:m 16 :ef-construction 200)))
  :my-graph)
```
**Contract**: `:dim` required; `:element-type` defaults to `:single-float`; `:index` defaults to NIL (no ANN index); `:metric` defaults to `:cosine`; `:index-params` passed to HNSW constructor.

### HNSW Config (per vertex-type × metric)
```lisp
(defstruct hnsw-config
  (m 16 :type (unsigned-byte 8))           ; max neighbors per layer
  (ef-construction 200 :type (unsigned-byte 16))
  (ef-search 50 :type (unsigned-byte 16))
  (metric :cosine :type (member :cosine :l2 :dot))
  (dim 1536 :type (unsigned-byte 16))
  (element-type :single-float :type (member :single-float :double-float))
  (max-layer 0 :type (unsigned-byte 8))    ; computed on first insert
  (entry-point 0 :type (unsigned-byte 64)) ; node-id of top-layer entry
)
```

### Prolog Functors (Phase 1)
| Functor     | Mode                                       | Description                                                                       |
| ----------- | ------------------------------------------ | --------------------------------------------------------------------------------- |
| `knn/3`     | `(+Vec +K -Result)` `(+NodeId +K -Result)` | K nearest neighbors. `+Vec` = vector literal or bound var; `+NodeId` = vertex id. |
| `similar/3` | `(+Vec +Threshold -Result)`                | All vectors within distance threshold.                                            |
| `vector/2`  | `(+Node -Vec)`                             | Retrieve stored vector for node.                                                  |

**Compilation contract**: At least one of `+Vec`/`+NodeId` must be ground at call time (enforced by compiler).

### REST API (Phase 1)
```
POST /graph/:graph/knn
Content-Type: application/json
{ "vector": [0.1, ...], "k": 10, "metric": "cosine", "type": "document", "include": ["title"] }
→ 200 { "results": [{ "id": "...", "distance": 0.05, "title": "..." }] }

POST /graph/:graph/similar
{ "vector": [...], "threshold": 0.15, "metric": "cosine", "type": "document" }
→ 200 { "results": [...] }

GET /graph/:graph/vector/:id
→ 200 { "id": "...", "type": "document", "vector": [...], "dim": 384 }
```

---

## Storage

### On-Disk Layout (per graph directory)
```
graph-dir/
├── heap.dat              # existing: node/edge heads + data
├── indexes.dat           # existing: skip-lists, ve-index, etc.
├── vectors.dat           # NEW: columnar vector segments (SOA)
├── vectors.idx           # NEW: linear-hash (node-id → {type-id, seg-offset, length})
├── hnsw.dat              # NEW: HNSW graph (linear-hash: node-id → neighbor-list per layer)
├── hnsw.meta             # NEW: HNSW config per (type, metric)
├── schema.dat            # existing: + vector-slot metadata
├── .dirty                # existing
└── wal/                  # existing: + HNSW mutation records
```

### Columnar Vector Segment (`vectors.dat`)
```
Segment header (per type-id + dim + element-type):
  u64 magic (0xE5E5E5E5E5E5E5E5)
  u16 type-id
  u16 dim
  u8  element-type (1=f32, 2=f64)
  u8  flags (bit 0 = has-padding)
  u32 count (vectors in segment)
  u64 next-segment-offset (0 = none)
  --- 64-byte aligned ---
  f32/f64[dim * count]   # contiguous SOA: all dim-0, then all dim-1, ...
  padding to 64-byte boundary
```
**Why SOA**: SIMD loads 8×f32 (AVX2) or 16×f32 (AVX-512) per instruction. AOS (interleaved) requires gather/shuffle → 3-5× slower distance computation.

### HNSW Persistence (`hnsw.dat` via linear-hash)
```
Key: node-id (16 bytes)
Value: serialized neighbor lists
  u8  max-layer
  u64 entry-point (for this node's top layer)
  for layer = 0 .. max-layer:
    u16 neighbor-count
    u64[neighbor-count]  # node-ids of neighbors at this layer
```
**Linear-hash value bytes**: Variable (use `+overflow-magic-byte+` for long neighbor lists). Max neighbors per layer = M (default 16) → max ~256 bytes per node.

### Schema Extension (`schema.dat` via cl-store)
`node-type` struct gains:
```lisp
(vector-slots
  ((embedding
    (dim 384)
    (element-type :single-float)
    (index :hnsw)
    (metric :cosine)
    (index-params (m 16 ef-construction 200)))))
```
Per-class RW-lock (existing) covers vector column + HNSW index.

---

## Trade-offs

| Decision                 | Chosen                                                     | Rejected Alternatives            | Rationale                                                                                                                                                                                                           |
| ------------------------ | ---------------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **HNSW implementation**  | Pure Common Lisp (port `hnswlib` logic)                    | CFFI to `hnswlib` / `faiss`      | No external C++ deps; fits VivaceGraph "pure Lisp" ethos; mmap compatibility; SBCL compiler generates fast SIMD via `(declare (optimize (speed 3)))` + `sb-simd` intrinsics. Perf validation via spike (see Risks). |
| **Vector dimensions**    | Fixed per schema (declared in `def-vertex`)                | Dynamic/jagged                   | Fixed enables SOA columnar, SIMD, predictable HNSW memory. Dynamic needs jagged arrays → no SIMD, complex index.                                                                                                    |
| **Index persistence**    | HNSW neighbor lists in linear-hash (embedded in main heap) | Separate `hnsw-heap` mmap region | Single mmap window, simpler recovery, reuses allocator. Separate heap adds reservation complexity (see `mmap.lisp` *mmap-reservation-multiplier*).                                                                  |
| **Similarity metrics**   | Cosine, L2, dot (all Phase 1)                              | Cosine only                      | Cosine = normalized dot; L2 = Euclidean. All three are O(dim) with same SIMD kernels. Dot needed for unnormalized embeddings.                                                                                       |
| **Vector element type**  | f32 + f64 (both)                                           | f32 only                         | f64 for scientific workloads (drug discovery). Storage 2×; computation 2× slower. Opt-in via `:element-type :double-float`.                                                                                         |
| **Quantization (PQ/SQ)** | Not in Phase 1                                             | Binary/PQ                        | Full precision first. Quantization adds decode overhead; HNSW recall drops 2-5%. Defer to Phase 2+.                                                                                                                 |
| **GPU**                  | CPU SIMD only                                              | CUDA/ROCm via FFI                | VivaceGraph targets embeddable/offline (ECL Android). GPU adds massive deployment complexity. CPU AVX-512 reaches ~50% of GPU throughput for 128-dim.                                                               |
| **Distributed ANN**      | Single-node                                                | Cluster HNSW                     | mmap architecture is single-node. Distributed requires consensus on index mutations → separate project.                                                                                                             |

---

## Risks

| Risk                               | Likelihood | Impact | Mitigation                                                                                                                                                                                                                |
| ---------------------------------- | ---------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Pure Lisp HNSW too slow**        | Medium     | High   | **Spike required before Phase 1 commit**: Implement minimal HNSW (insert + search) in `spikes/hnsw-perf.lisp`, benchmark 10k vectors vs. `hnswlib` C++ baseline. Target: ≤2× slower. If >3×, fall back to CFFI `hnswlib`. |
| **SBCL SIMD not auto-vectorizing** | Medium     | Medium | Use `sb-simd` intrinsics (`sb-simd:make-simd-pack-4`, `sb-simd:simd-dot`) for distance kernels. Verify with `disassemble`.                                                                                                |
| **ECL compatibility**              | High       | Medium | ECL: no custom hash tests → HNSW linear-hash uses `equalp` keys; `defstruct` setf expanders only → provide `(setf hnsw-config-m)` etc. Test on ECL 21.2.1 + 26.5.5.                                                       |
| **Mmap growth with HNSW**          | Low        | High   | HNSW neighbor lists grow unpredictably. Reserve extra in `*default-index-size*` (default 1GB). Monitor `unallocated-memory-available` in `allocate`.                                                                      |
| **Recovery complexity**            | Medium     | High   | WAL must log HNSW mutations (insert neighbor, delete, layer promotion). Replay rebuilds affected subgraph. Test: kill -9 during bulk insert → `open-graph` → `recover-transactions` → verify recall.                      |
| **Tutorial data licensing**        | Low        | Low    | CoNLL-2003, FewRel, MoleculeNet are free for research. Bundle only synthetic data in repo; download scripts fetch real data at runtime.                                                                                   |
| **Benchmark vs. TigerGraph**       | Medium     | Medium | TigerGraph uses GPU + distributed. Our target: CPU single-node. Document hardware/config exactly. Publish reproducible benchmark script.                                                                                  |

---

## Out-of-Scope (This PRD)

1. **Training embeddings inside VivaceGraph** (Node2Vec, GraphSAGE, GAT) — external only.
2. **GPU acceleration** — CPU SIMD only.
3. **Distributed/cluster ANN** — single-node mmap.
4. **Binary quantization / Product Quantization** — full precision f32/f64 first.
5. **Edge embeddings** — Phase 2.
6. **Graph/subgraph embeddings** — Phase 3.
7. **AutoML / hyperparameter tuning** for HNSW.
8. **Vector compression** (delta encoding, etc.) — columnar is already compact.
9. **Custom distance functions** beyond cosine/L2/dot — extensible via `:metric` function designator in Phase 2.
10. **Streaming index build** (online HNSW) — batch build via `hnsw-bulk-load` in Phase 1; online insert supported.

---

## Open Questions (Resolve Before Implementation)

1. **HNSW pure Lisp perf spike** — allocate 2 days. If fails, CFFI path.
2. **Vector segment compaction** — deleted vectors leave holes. GC pass? Or mark-deleted + rebuild threshold?
3. **HNSW delete** — lazy deletion (mark neighbor list tombstone) vs. eager rewire. Lazy simpler; eager better recall. Start lazy.
4. **REST pagination for large K** — cursor-based (`after_id`) or offset/limit? Cursor.
5. **Benchmark dataset** — OGB-Products (2.4M nodes) too large for CI. Use synthetic 100k/1M with known clusters.
6. **`def-view` on vectors** — map-reduce over vectors? Defer to Phase 2.
7. **Transaction isolation for HNSW reads** — HNSW is immutable after build (layers only grow). Readers see consistent snapshot without locks. Writers take RW-lock. Valid?
8. **Memory profiling** — `vectors.dat` + `hnsw.dat` overhead target <2.5× raw vectors. Track in benchmarks.

---

## Implementation Order (Phase 1)

1. **Spike**: `spikes/hnsw-perf.lisp` — pure Lisp HNSW insert+search vs. `hnswlib`.
2. **Vector columnar storage** — `vectors.lisp`: serialize/deserialize, linear-hash index, SOA layout.
3. **Schema + MOP integration** — `vector-slot.lisp`: `def-vertex` `:vector` slot options, `node-type` extension.
4. **HNSW index** — `hnsw.lisp`: insert, search (KNN, range), linear-hash persistence, WAL logging.
5. **Prolog predicates** — `prolog-vector.lisp`: `knn/3`, `similar/3`, `vector/2` compilation.
6. **REST endpoints** — `rest-vector.lisp`: `/knn`, `/similar`, `/vector/:id`.
7. **Tutorial 1** — `tutorials/ner-entity-resolution.lisp` + CoNLL-2003 download script.
8. **Tutorial 2** — `tutorials/financial-forecasting.lisp` + synthetic data generator.
9. **Benchmarks** — `bench/bench-hnsw.lisp` + CI job.
10. **Tests** — `tests/vector-tests.lisp` (unit), `tests/hnsw-tests.lisp` (correctness), `tests/embedding-integration.lisp` (end-to-end).