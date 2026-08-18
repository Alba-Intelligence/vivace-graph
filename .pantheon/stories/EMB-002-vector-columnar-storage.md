---
id: EMB-002
title: Vector Columnar Storage — vectors.lisp (SOA layout, mmap)
status: pending
epic: Vector Columnar Storage + Schema/MOP Integration
deity: vulcan
---

## Goal
Implement `vectors.lisp` providing SOA (Structure of Arrays) columnar storage for dense vectors in the mmap heap. One contiguous segment per (vertex-type-id, dimension, element-type) tuple. Persisted as `vectors.dat` + `vectors.idx` linear-hash.

## Acceptance criteria
- [ ] `vectors.lisp` defines `vector-segment` struct: header (magic, type-id, dim, element-type, flags, count, next-segment-offset) + aligned data array
- [ ] `allocate-vector-segment(type-id dim element-type)` → returns segment offset, creates new segment if current full
- [ ] `append-vector(segment-offset vector)` → writes vector to SOA layout (all dim-0, then dim-1, ...), 64-byte aligned, returns vector index within segment
- [ ] `read-vector(segment-offset index)` → returns vector as `(simple-array single-float/double-float (dim))`
- [ ] `vectors.idx` linear-hash: key = node-id (16 bytes), value = `{type-id, segment-offset, index-in-segment, length}`
- [ ] Segment chaining: when segment full (configurable, default 10k vectors), allocate new segment, link via `next-segment-offset`
- [ ] Integration with `allocator.lisp`: segments allocated from main heap via `allocate`/`free`
- [ ] 64-byte alignment for AVX-512 SIMD loads (pad segment header to 64 bytes, pad data to 64-byte boundary)
- [ ] Element types: `:single-float` (f32), `:double-float` (f64) — controlled by schema
- [ ] Unit tests: `tests/vector-storage-tests.lisp` (allocate, append, read, segment chaining, alignment verification)

## Affected files
- `vectors.lisp` (new)
- `graph-db.asd` (add `vectors` to `graph-db/core` components, after `allocator`)

## Architecture context
> **Vector Columnar Storage** (from .pantheon/architecture.md):
> **Responsibility**: SOA (Structure of Arrays) columnar storage for dense vectors, allocated from the existing mmap heap. One contiguous segment per vector dimension per vertex type.
> - **Files**: `vectors.dat` (data), `vectors.idx` (linear-hash: node-id → {type-id, dim-offset, length})
> - **Format**: Fixed-width f32/f64 arrays. Type declared in `def-vertex` (`:vector :dim 128 :element-type :single-float`).
> - **Alignment**: 64-byte aligned for AVX-512; padding for SIMD tail handling.
> - **Integration**: `serialize`/`deserialize` methods for new type tag `+embedding-vector+` (31); `make-serialized-key` routes to linear-hash.
>
> **Columnar Vector Segment (`vectors.dat`)**:
> ```
> Segment header (per type-id + dim + element-type):
>   u64 magic (0xE5E5E5E5E5E5E5E5)
>   u16 type-id
>   u16 dim
>   u8  element-type (1=f32, 2=f64)
>   u8  flags (bit 0 = has-padding)
>   u32 count (vectors in segment)
>   u64 next-segment-offset (0 = none)
>   --- 64-byte aligned ---
>   f32/f64[dim * count]   # contiguous SOA: all dim-0, then all dim-1, ...
>   padding to 64-byte boundary
> ```
> **Why SOA**: SIMD loads 8×f32 (AVX2) or 16×f32 (AVX-512) per instruction. AOS (interleaved) requires gather/shuffle → 3-5× slower distance computation.

## Out of scope
- Schema/MOP integration (`def-vertex` `:vector` slots) — separate story
- Serialization methods (`serialize`/`deserialize` for vectors) — separate story
- HNSW index integration — separate story (Epic 3)
- Vector segment compaction (GC for deleted vectors) — deferred
- Prolog predicates — separate story (Epic 4)

## Technical notes

### Segment Header Layout (64 bytes)
```lisp
(defstruct (vector-segment-header (:conc-name vs-hdr-))
  (magic #xE5E5E5E5E5E5E5E5 :type (unsigned-byte 64))
  (type-id 0 :type (unsigned-byte 16))
  (dim 0 :type (unsigned-byte 16))
  (element-type 0 :type (unsigned-byte 8))  ; 1=f32, 2=f64
  (flags 0 :type (unsigned-byte 8))
  (count 0 :type (unsigned-byte 32))
  (next-segment-offset 0 :type (unsigned-byte 64))
  (reserved 0 :type (unsigned-byte 64))     ; pad to 64 bytes
)
```

### SOA Data Layout
For dim=128, count=1000, element-type=f32:
```
segment-offset + 64 (header) → start of data
dim-0: 1000 f32 values (4000 bytes)
dim-1: 1000 f32 values
...
dim-127: 1000 f32 values
Total: 128 * 1000 * 4 = 512,000 bytes
Padded to 64-byte boundary
```

### Linear-Hash Value Format (`vectors.idx`)
```
node-id (16 bytes) → value (24 bytes):
  u16 type-id
  u64 segment-offset
  u32 index-in-segment
  u16 dim (for validation)
  u8  element-type
  u8  flags (reserved)
```

### Allocation Strategy
- Segments allocated from main heap via `allocate` (uses `normalize-allocation-data-size`)
- Default segment capacity: 10,000 vectors (configurable via `*vector-segment-capacity*`)
- On segment full: `allocate` new segment, write `next-segment-offset` in old header, update segment registry
- Segment registry: in-memory hash-table `type-id → (dim element-type) → current-segment-offset` for fast append

### ECL Compatibility
- No custom hash-table tests — use `equalp` for segment registry keys
- `defstruct` setf expanders only — provide `(setf vs-hdr-count)` etc. if needed
- `sb-simd` not available on ECL — distance kernels only used in HNSW (separate story), not here

## Definition of Done Checklist
- [ ] `vectors.lisp` compiles on SBCL, ECL, LispWorks
- [ ] `allocate-vector-segment` creates properly aligned segment
- [ ] `append-vector` writes SOA layout correctly (verify with `read-vector`)
- [ ] `read-vector` returns correct `(simple-array single-float (dim))`
- [ ] Segment chaining works: fill segment → new segment allocated → old `next-segment-offset` set
- [ ] `vectors.idx` linear-hash inserts/lookups work for node-id → segment mapping
- [ ] Alignment verified: `logand (segment-data-offset) 63 = 0`
- [ ] Unit tests pass: allocate, append, read, chain, alignment
- [ ] No memory leaks: `free` on segment works (for compaction later)