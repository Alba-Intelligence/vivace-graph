---
id: EMB-003
title: Schema/MOP Integration — def-vertex :vector Slots
status: pending
epic: Vector Columnar Storage + Schema/MOP Integration
deity: vulcan
---

## Goal
Extend `def-vertex` macro and `node-type` struct to accept `:vector` slots with full option specification (`:dim`, `:element-type`, `:index`, `:metric`, `:index-params`). Register vector-slot metadata in schema, create per-class RW-lock coverage.

## Acceptance criteria
- [ ] `def-vertex` accepts slot spec: `(embedding :type vector :dim 384 :element-type :single-float :index :hnsw :metric :cosine :index-params (:m 16 :ef-construction 200))`
- [ ] Macro validates: `:dim` required, `:element-type` ∈ `(:single-float :double-float)`, `:index` ∈ `(nil :hnsw :ivf)`, `:metric` ∈ `(:cosine :l2 :dot)`, `:index-params` plist
- [ ] `node-type` struct gains `vector-slots` slot: alist of `(slot-name . vector-config)` where `vector-config` = `(:dim :element-type :index :metric :index-params)`
- [ ] `instantiate-node-type` validates vector config on graph open: creates HNSW config per (type, metric) if `:index :hnsw`
- [ ] Per-class RW-lock (existing `schema-class-locks`) covers vector column + HNSW index
- [ ] `schema.dat` (cl-store) persists `vector-slots` alist; `restore-schema-locks` recreates locks
- [ ] Duplicate vector slot name → macro error at compile time
- [ ] Dimension mismatch on existing graph → `open-graph` error with clear message
- [ ] Unit tests: `tests/vector-schema-tests.lisp` (macro expansion, validation, schema round-trip, lock creation)

## Affected files
- `schema.lisp` (extend `node-type` struct, `instantiate-node-type`, `def-node-type` macro)
- `node-class.lisp` (ensure `vector-slots` accessible via `data-slots`/`persistent-slot-names`)
- `graph-db.asd` (no new files, but `schema.lisp` already in core)

## Architecture context
> **Vector Slot Integration** (from .pantheon/architecture.md):
> **Responsibility**: MOP integration so `:vector` slots behave like other typed slots.
> - **Slot options**: `:dim` (required), `:element-type` (`:single-float` | `:double-float`), `:index` (NIL | `:hnsw` | `:ivf`), `:metric` (`:cosine` | :l2 | :dot), `:index-params` (plist: M, efConstruction).
> - **Generated methods**: `make-<type>` accepts vector slot; `save`/`update-node` serialize to columnar store; `delete-node` removes from HNSW; `lookup-<type>` materializes vector lazily.
> - **Schema registration**: Extends `node-type` struct with `vector-slots` alist (slot-name → config).
>
> **`def-vertex` Extension**:
> ```lisp
> (def-vertex document ()
>   ((title :type string)
>    (embedding :type vector :dim 384 :element-type :single-float
>               :index :hnsw :metric :cosine
>               :index-params (:m 16 :ef-construction 200)))
>   :my-graph)
> ```
> **Contract**: `:dim` required; `:element-type` defaults to `:single-float`; `:index` defaults to NIL (no ANN index); `:metric` defaults to `:cosine`; `:index-params` passed to HNSW constructor.
>
> **HNSW Config** (per vertex-type × metric):
> ```lisp
> (defstruct hnsw-config
>   (m 16 :type (unsigned-byte 8))
>   (ef-construction 200 :type (unsigned-byte 16))
>   (ef-search 50 :type (unsigned-byte 16))
>   (metric :cosine :type (member :cosine :l2 :dot))
>   (dim 1536 :type (unsigned-byte 16))
>   (element-type :single-float :type (member :single-float :double-float))
>   (max-layer 0 :type (unsigned-byte 8))
>   (entry-point 0 :type (unsigned-byte 64))
> )
> ```

## Out of scope
- Vector columnar storage implementation (`vectors.lisp`) — separate story (EMB-002)
- Serialization methods for vectors — separate story (EMB-004)
- HNSW index creation/insert/search — separate story (Epic 3)
- `make-<type>`/`save`/`update-node`/`delete-node` vector handling — separate story (Epic 3)
- Prolog predicates — separate story (Epic 4)

## Technical notes

### Macro Expansion (in `def-node-type` / `def-vertex`)
```lisp
;; Slot spec parsing:
;; (embedding :type vector :dim 384 :element-type :single-float :index :hnsw :metric :cosine :index-params (:m 16 :ef-construction 200))
;; → vector-config = (:dim 384 :element-type :single-float :index :hnsw :metric :cosine :index-params (:m 16 :ef-construction 200))
;; Stored in node-type.vector-slots alist
```

### `node-type` Struct Extension
```lisp
(defstruct node-type
  name
  parent-type
  id
  graph-name
  slots
  package
  constructor
  keep-revisions
  ;; NEW:
  vector-slots  ; alist: (slot-name . vector-config)
  hnsw-configs  ; hash-table: (type-id . metric) → hnsw-config
)
```

### `instantiate-node-type` Validation
```lisp
(defmethod instantiate-node-type ((meta node-type) (graph graph))
  ;; ... existing code ...
  ;; NEW: validate vector slots
  (dolist (vector-slot (node-type-vector-slots meta))
    (destructuring-bind (slot-name config) vector-slot
      (let ((dim (getf config :dim))
            (element-type (getf config :element-type :single-float))
            (index (getf config :index))
            (metric (getf config :metric :cosine)))
        ;; Validate dim
        (unless (and (integerp dim) (> dim 0))
          (error "VECTOR slot ~A requires positive integer :DIM, got ~A" slot-name dim))
        ;; Validate element-type
        (unless (member element-type '(:single-float :double-float))
          (error "VECTOR slot ~A :ELEMENT-TYPE must be :SINGLE-FLOAT or :DOUBLE-FLOAT, got ~A" slot-name element-type))
        ;; Validate index
        (unless (member index '(nil :hnsw :ivf))
          (error "VECTOR slot ~A :INDEX must be NIL, :HNSW, or :IVF, got ~A" slot-name index))
        ;; Validate metric
        (unless (member metric '(:cosine :l2 :dot))
          (error "VECTOR slot ~A :METRIC must be :COSINE, :L2, or :DOT, got ~A" slot-name metric))
        ;; If index = :hnsw, create/validate HNSW config
        (when (eq index :hnsw)
          (ensure-hnsw-config meta graph slot-name config)))))
```

### HNSW Config per (type, metric)
```lisp
(defun ensure-hnsw-config (meta graph slot-name config)
  (let* ((type-id (node-type-id meta))
         (metric (getf config :metric :cosine))
         (key (cons type-id metric))
         (hnsw-configs (node-type-hnsw-configs meta)))
    (or (gethash key hnsw-configs)
        (let ((new-config (make-hnsw-config
                           :m (getf (getf config :index-params) :m 16)
                           :ef-construction (getf (getf config :index-params) :ef-construction 200)
                           :ef-search (getf (getf config :index-params) :ef-search 50)
                           :metric metric
                           :dim (getf config :dim)
                           :element-type (getf config :element-type :single-float))))
          (setf (gethash key hnsw-configs) new-config)
          new-config))))
```

### ECL Compatibility
- `node-type` is `defstruct` → ECL needs `(setf node-type-vector-slots)` and `(setf node-type-hnsw-configs)` functions
- Hash-table for `hnsw-configs` uses `equalp` test (ECL requirement)
- No custom hash tests in vector-slot alist — use `assoc` with `equal` test

## Definition of Done Checklist
- [ ] `def-vertex` macro expands with `:vector` slot, validates all options
- [ ] `node-type` struct has `vector-slots` and `hnsw-configs` slots
- [ ] `instantiate-node-type` validates vector config on graph open
- [ ] HNSW config created per (type-id, metric) when `:index :hnsw`
- [ ] Per-class RW-lock covers vector column (existing mechanism)
- [ ] `schema.dat` round-trip: save → close → open → `vector-slots` preserved
- [ ] Duplicate vector slot name → compile-time error
- [ ] Dimension mismatch on existing graph → `open-graph` error: "Vector slot EMBEDDING dim 384 ≠ persisted dim 768"
- [ ] Unit tests pass: macro expansion, validation, schema persistence, lock creation
- [ ] Cross-implementation: SBCL, ECL 21.2.1, ECL 26.5.5, LispWorks