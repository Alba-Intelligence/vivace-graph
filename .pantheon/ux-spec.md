# UX Specification: Graph Embeddings in VivaceGraph

## Users & Goals

| User | Primary Goal | Context |
|------|--------------|---------|
| **Lisp Developer** | Define schema with vector slots, transact embeddings, query via Prolog | REPL-driven, Emacs/Slime, rapid iteration |
| **Data Scientist** | Load pre-computed embeddings, run similarity search, evaluate results | Jupyter-adjacent, batch scripts, interactive exploration |
| **ML Engineer** | Build pipeline: graph → external model → embeddings → downstream queries | CI/CD, automated, REST API consumer |
| **External Service** | KNN/similarity search via HTTP, JSON I/O | Stateless, high-throughput, language-agnostic |

---

## Key Flows

### Flow 1: Schema Definition (Lisp Developer)
**Trigger**: Developer adds `:vector` slot to `def-vertex` in source file, recompiles.
**Steps**:
1. Edit `def-vertex` form → add `(embedding :type vector :dim 384 :element-type :single-float :index :hnsw :metric :cosine :index-params (:m 16 :ef-construction 200))`
2. Reload system → `def-vertex` macro expands, registers vector-slot metadata in schema
3. Open/create graph → `instantiate-node-type` validates dimension, creates HNSW config per (type, metric)
4. Verify: `(describe (lookup-node-type-by-name 'document :vertex))` shows `vector-slots` alist
**Success**: Schema persisted to `schema.dat`; HNSW config in `hnsw.meta`; no errors on graph open.
**Failure states**:
- Missing `:dim` → macro error at compile time: "VECTOR slot EMBEDDING requires :DIM"
- Duplicate vector slot name → macro error: "Duplicate slot name EMBEDDING"
- Invalid `:metric` → runtime error on graph open: "Unknown metric :cosine-similarity, expected :cosine | :l2 | :dot"
- Dimension mismatch on existing graph → `open-graph` error: "Vector slot EMBEDDING dim 384 ≠ persisted dim 768"

### Flow 2: Embedding Ingestion (Data Scientist / ML Engineer)
**Trigger**: External model produces embeddings (JSONL/CSV/NPY); user runs import script.
**Steps**:
1. Prepare data: JSONL lines `{ "id": "...", "text": "...", "embedding": [0.1, ...] }` or CSV with vector column
2. Run import script (Lisp or Python → JSONL → Lisp):
   ```lisp
   (with-transaction ()
     (dolist (record records)
       (make-document :id (read-id record.id)
                      :title record.text
                      :embedding record.embedding)))
   ```
3. Transaction commits → vectors written to `vectors.dat` (SOA), HNSW updated, WAL logged
4. Progress: log shows `Inserted 10000/100000 vectors (HNSW build 45s)`
5. Verify: `(select (?v) (knn ?query-vec 5 ?v))` returns results
**Success**: All vectors persisted; HNSW recall@10 ≥ 0.95 on spot-check; `vectors.dat` size ≈ 4 bytes × dim × count.
**Failure states**:
- Vector dimension mismatch → transaction rolls back; error: "Vector dim 768 ≠ schema dim 384 for type DOCUMENT"
- Duplicate ID → `duplicate-key-error` → retry with new ID (if `:retry-p t`) or abort
- OOM during HNSW build → `grow-memory` extends mmap; if reservation exhausted → error: "Index region reservation exhausted, increase *default-index-size*"
- Kill -9 mid-ingest → `.dirty` file remains; `open-graph` refuses; `recover-transactions` replays WAL → HNSW rebuilt

### Flow 3: Prolog Similarity Query (Lisp Developer / Data Scientist)
**Trigger**: User enters query at REPL or in source file.
**Steps**:
1. Bind query vector: `(let ((qvec (make-array 384 :element-type 'single-float :initial-contents ...)))`
2. Run: `(select (?doc ?dist) (knn qvec 10 (?doc ?dist)) (vector ?doc ?vec))`
3. Compiler: `knn/3` → `hnsw-knn-search` with `ef-search` from HNSW config
4. Results stream back: list of `(?doc ?dist)` bindings
5. Optional: project slots → `(title ?doc ?title)`
**Success**: Results returned in <10ms p99; distances sorted ascending; `?doc` is vertex instance with lazy slots.
**Failure states**:
- Unbound query vector → compile error: "KNN requires ground vector or node-id"
- No HNSW index on type → runtime error: "No HNSW index for type DOCUMENT metric :cosine; add :index :hnsw to slot"
- Empty graph → returns NIL (no error)
- Query vector wrong dim → runtime error: "Query vector dim 768 ≠ index dim 384"

### Flow 4: REST KNN Search (External Service)
**Trigger**: HTTP POST to `/graph/:graph/knn`
**Request**:
```json
POST /graph/my-graph/knn
Content-Type: application/json
Authorization: Basic ...
{
  "vector": [0.1, -0.3, ...],
  "k": 10,
  "metric": "cosine",
  "type": "document",
  "include": ["title", "embedding"]
}
```
**Steps**:
1. Auth → validate user, graph exists
2. Parse JSON → validate `vector` length matches schema dim for `type`
3. Call `hnsw-knn-search` with `ef-search` from config
4. For each result: fetch included slots from heap (lazy materialization)
5. Stream response as NDJSON (if `Accept: application/x-ndjson`) or JSON array
**Response**:
```json
{ "results": [
    { "id": "abc123...", "distance": 0.042, "title": "Introduction to Graph Embeddings" },
    { "id": "def456...", "distance": 0.087, "title": "Vector Search in Lisp" }
  ]
}
```
**Success**: 200 OK, p99 < 10ms, correct Content-Type, distances ascending.
**Failure states**:
- 401 Unauthorized → invalid/missing credentials
- 404 Graph not found → `:graph` name unknown
- 400 Bad Request → `vector` length mismatch, unknown `type`, invalid `metric`
- 422 Unprocessable → `k` > 10000 (configurable limit), `include` references non-existent slot
- 500 Internal → HNSW index corrupted, mmap error → logs error, returns `{ "error": "index_unavailable" }`

### Flow 5: Tutorial Execution (Data Scientist / New User)
**Trigger**: User runs `(ql:quickload :graph-db/tutorials)` then `(tutorial:run-ner-entity-resolution)`
**Steps**:
1. Tutorial script downloads CoNLL-2003 (if not cached) → `~/data/conll2003/`
2. External Python script (bundled) runs BERT → `conll2003_embeddings.jsonl`
3. Lisp script: `make-graph` → `def-vertex` → import JSONL → `with-transaction` batch insert
4. Query: entity resolution via `knn/3` on mention embeddings → cluster by distance threshold
5. Evaluate: compare clusters to gold labels → print F1, precision, recall
6. Cleanup: `close-graph` → optionally `delete-graph`
**Success**: Runs end-to-end in <5 min; prints F1 ≥ 0.85; no manual steps.
**Failure states**:
- Download fails → script exits with URL + manual instructions
- Python/BERT not installed → error with `pip install sentence-transformers` command
- OOM on embed → fallback to smaller batch size (auto)
- F1 < threshold → warning logged, not error (dataset variance)

### Flow 6: Index Monitoring & Debugging (Operator / Developer)
**Trigger**: User wants to verify index health, tune parameters, diagnose recall regression.
**Steps**:
1. REPL: `(hnsw-stats *graph* :type 'document :metric :cosine)`
   → Returns: `{:count 100000 :max-layer 3 :entry-point #x... :ef-search 50 :m 16 :memory-mb 245}`
2. REPL: `(hnsw-recall-test *graph* :type 'document :metric :cosine :sample 1000 :k 10)`
   → Runs brute-force vs. HNSW on sample → prints recall@1, @5, @10, latency p50/p99
3. REST: `GET /graph/:graph/admin/hnsw/:type/:metric` → JSON stats
4. Logs: `INFO HNSW insert 50000 vectors 12.3s (4065 vec/s) layers=3`
**Success**: Stats returned instantly; recall test completes in <30s; metrics match expectations.
**Failure states**:
- Index not built → `:count 0 :max-layer 0`
- Recall < 0.9 → warning: "HNSW recall@10=0.87 < 0.95 target; consider increasing M or efConstruction"
- Corrupted neighbor list → error on search → `recover-transactions` needed

---

## Screens & States

### REPL Interaction (Primary Interface)
```
CL-USER> (def-vertex document ()
           ((title :type string)
            (embedding :type vector :dim 384 :element-type :single-float
                       :index :hnsw :metric :cosine
                       :index-params (:m 16 :ef-construction 200)))
           :my-graph)
; DEF-VERTEX expands → registers vector slot, creates HNSW config
; Compiler output shows generated MAKE-DOCUMENT, LOOKUP-DOCUMENT, DOCUMENT-P

CL-USER> (make-graph "my-graph" :location #p"/var/tmp/my-graph/")
; Creates graph dir, initializes vectors.dat, hnsw.dat, hnsw.meta

CL-USER> (with-transaction ()
           (make-document :title "Graph Embeddings"
                          :embedding #(0.1 0.2 ...)))
; Returns #<DOCUMENT ...> with vector persisted

CL-USER> (select (?doc ?dist)
            (knn #(0.1 0.2 ...) 5 (?doc ?dist))
            (vector ?doc ?vec))
((#<DOCUMENT ...> 0.023) (#<DOCUMENT ...> 0.041) ...)
```

### REST API (Swagger/OpenAPI)
- `POST /graph/:graph/knn` — KNN search
- `POST /graph/:graph/similar` — Threshold search
- `GET /graph/:graph/vector/:id` — Retrieve vector + metadata
- `POST /graph/:graph/vector/batch` — Bulk upsert
- `GET /graph/:graph/admin/hnsw/:type/:metric` — Index stats
- `GET /graph/:graph/admin/hnsw/:type/:metric/recall` — Recall test (expensive, admin only)

### Tutorial Output
```
;; Running NER Entity Resolution Tutorial
[1/5] Downloading CoNLL-2003... done (cached)
[2/5] Generating BERT embeddings... 14,041 mentions → embeddings.jsonl (45s)
[3/5] Creating graph & importing... 14,041 vertices (12s)
[4/5] Building HNSW index... M=16 efC=200 → 3 layers (8s)
[5/5] Entity resolution (knn k=20, threshold=0.15)... 1,247 clusters
F1: 0.873  Precision: 0.891  Recall: 0.856
Tutorial completed in 65s.
```

### Error States (All Interfaces)
| Context | Error | User Action |
|---------|-------|-------------|
| Schema def | `:dim` missing | Add `:dim N` to slot spec |
| Ingest | Dim mismatch | Fix external model or schema |
| Query | No HNSW index | Add `:index :hnsw` to slot |
| REST | 400 vector length | Check schema dim for type |
| Tutorial | Download fail | Run manual `wget` per printed URL |
| Admin | Recall < 0.9 | Increase M/efConstruction, rebuild |

---

## Accessibility & Developer Experience

1. **REPL-first**: All functionality accessible from REPL; no separate CLI needed.
2. **Self-documenting**: `describe` on vertex type shows vector config; `documentation` on generated functions.
3. **Composable**: Vector predicates work inside larger Prolog queries (joins, filters, projections).
4. **Observable**: Structured logging (log4cl) for ingest, index build, query latency; REST admin endpoints.
5. **Recoverable**: WAL + `recover-transactions` handles crashes; `.dirty` sentinel prevents silent corruption.
6. **Tutorials runnable**: Zero-config (downloads data, generates embeddings) for new users.
7. **Benchmark reproducible**: Scripts publish exact hardware, SBCL version, dataset, commands.