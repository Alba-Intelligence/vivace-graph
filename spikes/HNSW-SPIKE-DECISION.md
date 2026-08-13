# HNSW Performance Spike Decision

## Experiment Details
- **Date**: $(date)
- **Implementation**: Pure Common Lisp HNSW
- **Baseline**: hnswlib C++ (to be implemented)
- **Dataset**: 10,000 vectors × 1536 dimensions
- **Parameters**: M=16, efConstruction=200, efSearch=50

## Results
### Pure Lisp HNSW
- Insert throughput: TODO vec/s
- Search latency p50: TODO ms
- Search latency p99: TODO ms
- Recall@10: TODO

### hnswlib C++ Baseline
- Insert throughput: TODO vec/s
- Search latency p50: TODO ms
- Search latency p99: TODO ms
- Recall@10: TODO

## Performance Ratio
- Insert: Lisp/C++ = TODO
- Search p50: Lisp/C++ = TODO
- Search p99: Lisp/C++ = TODO

## Decision
**TODO**: Proceed with pure Lisp if ≤2× slower, fallback to CFFI if >3× slower

## Next Steps
- If pure Lisp: Implement EMB-002 (vector columnar storage) and EMB-003 (schema/MOP integration)
- If CFFI: Rewrite stories for CFFI hnswlib integration