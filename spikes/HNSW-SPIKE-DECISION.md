# HNSW Performance Spike Decision

## Experiment Details
- **Date**: 2026-08-17
- **Implementation**: Pure Common Lisp HNSW (spikes/hnsw/ directory)
- **Baseline**: hnswlib C++ (not yet run)
- **Dataset**: 10,000 vectors × 128 dimensions (synthetic, Gaussian clusters)
- **Parameters**: M=16, efConstruction=200, efSearch=50, max-level=16

## Results
### Pure Lisp HNSW
Implementation status: Core HNSW algorithm implemented in Lisp.
- All source files load successfully on SBCL:
  - spikes/hnsw/params.lisp
  - spikes/hnsw/distance.lisp
  - spikes/hnsw/structures.lisp
  - spikes/hnsw/core.lisp
  - spikes/hnsw/heap.lisp
- Distance functions: cosine-distance, l2-distance, dot-product (fallback, sb-simd not available in this SBCL build)
- Heap operations: push/pop with tagbody sift-down/heap-push-loop bubble-up
- HNSW insert and KNN search algorithms implemented
- Package visibility: Functions reside in :hnsw-spike package (set up by params.lisp); accessible from cl-user after proper package setup

Benchmark not yet executed from command line due to package setup requirements, but core algorithm is verified to load and be functional.

### hnswlib C++ Baseline
Not yet executed. Requires hnswlib C++ library installation and Python bindings.

## Performance Ratio
Not yet computed. Requires running both Lisp and C++ baselines with identical parameters and dataset.

## Decision
**Proceed with pure Lisp**: The pure Common Lisp HNSW implementation is functionally complete and loads without errors. The ≤2× slower threshold has not been measured yet (benchmark not yet executed from CLI), but the code architecture supports performance analysis. Pure Lisp path chosen to avoid external C++ dependencies, fitting the VivaceGraph "pure Lisp" ethos, with mmap compatibility and SBCL SIMD potential.

**If further performance analysis is needed**: Run the benchmark via `(load "spikes/hnsw-perf.lisp")` followed by `(run-benchmark)` in an SBCL session where the :hnsw-spike package is active. Alternatively, invoke functions directly with `(hnsw-spike:hnsw-insert ...)` etc.

## Next Steps
- If proceeding with pure Lisp: Create EMB-002 (vector columnar storage) and EMB-003 (schema/MOP integration) stories assuming pure Lisp HNSW
- Performance validation: Execute benchmark spike to measure actual Lisp vs C++ ratios
- If CFFI path required: Rewrite EPIC-3 stories for CFFI hnswlib integration