---
id: EMB-001
title: HNSW Performance Spike — Pure Lisp vs CFFI Go/No-Go
status: pending
epic: HNSW Performance Spike
deity: vulcan
---

## Goal
Implement a minimal HNSW (Hierarchical Navigable Small World) index in pure Common Lisp and benchmark it against the `hnswlib` C++ baseline to decide whether to proceed with pure Lisp or fall back to CFFI. This is the critical go/no-go gate for the entire embeddings feature.

## Acceptance criteria
- [ ] `spikes/hnsw-perf.lisp` implements HNSW insert + KNN search in pure Common Lisp (SBCL)
- [ ] Distance kernels use `sb-simd` intrinsics for cosine/L2/dot product
- [ ] Benchmark runs: 10,000 vectors × 128-dim, M=16, efConstruction=200, efSearch=50
- [ ] Metrics collected: recall@10, insert throughput (vec/s), search latency p50/p99
- [ ] Comparison against `hnswlib` C++ baseline (same parameters, same dataset)
- [ ] Decision recorded in `spikes/HNSW-SPIKE-DECISION.md`: pure Lisp ≤2× slower → proceed; >3× → CFFI path
- [ ] `disassemble` output confirms SIMD vectorization on distance kernels (no generic function calls in hot path)

## Affected files
- `spikes/hnsw-perf.lisp` (new)
- `spikes/HNSW-SPIKE-DECISION.md` (new, output)
- `graph-db.asd` (add `spikes` system or load spike manually)

## Architecture context
> **HNSW Implementation Decision** (from .pantheon/architecture.md):
> | Decision | Chosen | Rejected Alternatives | Rationale |
> |----------|--------|----------------------|-----------|
> | **HNSW implementation** | Pure Common Lisp (port `hnswlib` logic) | CFFI to `hnswlib` / `faiss` | No external C++ deps; fits VivaceGraph "pure Lisp" ethos; mmap compatibility; SBCL compiler generates fast SIMD via `(declare (optimize (speed 3)))` + `sb-simd` intrinsics. Perf validation via spike (see Risks). |
>
> **Risk**: Pure Lisp HNSW too slow (Medium likelihood, High impact)
> **Mitigation**: Spike required before Phase 1 commit. Implement minimal HNSW in `spikes/hnsw-perf.lisp`, benchmark 10k vectors vs. `hnswlib` C++ baseline. Target: ≤2× slower. If >3×, fall back to CFFI `hnswlib`.

## Out of scope
- Full HNSW persistence (mmapped neighbor lists, linear-hash integration)
- WAL integration for mutation logging
- Concurrent read/write access (RW-locks)
- IVF index alternative
- Bulk-load (`hnsw-bulk-load`)
- Lazy deletion (tombstones)
- Vector columnar storage (`vectors.dat`) — this spike uses in-memory vectors only
- Schema/MOP integration (`def-vertex` `:vector` slots)
- Prolog predicates (`knn/3`, `similar/3`)
- REST endpoints
- Tutorials and benchmarks

## Technical notes

### HNSW Algorithm (minimal subset for spike)
1. **Node structure**: `node-id`, `vector`, `neighbors[layer]` (vector of neighbor node-ids per layer)
2. **Parameters**: M (max neighbors per layer), efConstruction, efSearch, max-layer
3. **Insert**:
   - Compute entry point distance to query vector
   - For layer = max-layer down to 1: greedy search with ef=1 to find entry point for next layer
   - Layer 0: full efConstruction search, select M nearest neighbors with heuristic pruning
   - Promote to higher layers with probability `exp(-layer)`
4. **Search (KNN)**:
   - Start at top-layer entry point
   - For layer = max-layer down to 1: greedy search with ef=1
   - Layer 0: priority queue search with efSearch, track visited set
   - Return top-k by distance

### Distance Kernels (SIMD-critical)
```lisp
;; Cosine distance = 1 - (A·B) / (|A|×|B|)
;; Pre-normalize vectors at insert → cosine = 1 - dot(A, B)
;; L2 distance = sqrt(sum((A-B)²)) → compute squared L2, sqrt at end
;; Dot product = sum(A*B)

;; SBCL sb-simd intrinsics:
(sb-simd:make-simd-pack-4 &rest values)     ; pack 4 floats
(sb-simd:simd-dot pack1 pack2)              ; dot product
(sb-simd:simd-add pack1 pack2)              ; vector add
(sb-simd:simd-mul pack1 pack2)              ; vector mul
(sb-simd:simd-sqrt pack)                    ; sqrt
```

### Benchmark Dataset
- Synthetic: 10,000 vectors, 128-dim, 10 Gaussian clusters (known ground truth)
- Fixed random seed for reproducibility
- Same dataset used for both pure Lisp and `hnswlib` runs

### hnswlib Baseline
```bash
# Install hnswlib (C++)
git clone https://github.com/nmslib/hnswlib
cd hnswlib && mkdir build && cd build && cmake .. && make
# Python bindings for quick benchmark
pip install hnswlib
```
Python script to run baseline with identical parameters.

## Definition of Done Checklist
- [ ] `spikes/hnsw-perf.lisp` loads and runs without errors on SBCL
- [ ] Insert 10k vectors completes in reasonable time (<60s)
- [ ] KNN search for 100 random queries returns results
- [ ] Recall@10 computed against brute-force ground truth
- [ ] Latency percentiles (p50, p99) measured
- [ ] `hnswlib` baseline run with same dataset/parameters
- [ ] Ratio: (Lisp latency) / (C++ latency) ≤ 2.0 for search; ≤ 3.0 for insert
- [ ] Decision document written with raw numbers, conclusion, and next steps
- [ ] If proceed: Epic 3 stories created with pure Lisp assumption
- [ ] If CFFI: Epic 3 stories rewritten for CFFI path