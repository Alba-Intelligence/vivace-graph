# Architecture: Import/Export — Ecosystem Interoperability

## Components

### 1. `import-export` package (new system: `graph-db/import-export`)
Core orchestration layer. Defines:
- **Format protocols** — generic functions `import-format`, `export-format` dispatching on format keyword
- **Schema mapping DSL** — Lisp-based mapping spec (plist/alist) + optional external JSON/YAML config
- **Conflict resolution policies** — `:upsert`, `:skip`, `:error` per import
- **Streaming coordinator** — chunked transactional imports with resume tokens
- **ID reconciliation** — source ID → VivaceGraph UUID mapping (preserve as property)

### 2. `import-export/formats` (sub-package)
One file per format, loaded on demand:
| File            | Import            | Export            | Dependencies                            |
| --------------- | ----------------- | ----------------- | --------------------------------------- |
| `gml.lisp`      | ✓ (wrap existing) | ✓ (wrap existing) | `graph-db/algorithms-io`                |
| `jsonl.lisp`    | ✓                 | ✓                 | `cl-json` (already in core)             |
| `csv.lisp`      | ✓                 | ✓                 | `cl-csv` (Quicklisp)                    |
| `parquet.lisp`  | ✓                 | ✓                 | `cl-arrow` or `cffi` + Apache Arrow C++ |
| `wikidata.lisp` | ✓                 | —                 | `cl-json`, streaming JSON parser        |
| `yago.lisp`     | ✓                 | —                 | `cl-csv` (TSV) or RDF parser            |
| `turingdb.lisp` | —                 | ?                 | Deferred pending spec                   |
| `ladybug.lisp`  | —                 | ?                 | Deferred pending spec                   |

### 3. `import-export/streaming`
- **Chunked transaction manager** — groups N records per transaction, commits, checkpoints resume token (file position + last committed IDs)
- **Resume protocol** — on failure, restart from token; skip already-imported via ID reconciliation table
- **Memory budget** — enforces < 500MB heap via bounded buffers + forced GC between chunks

### 4. `import-export/mapping`
- **Mapping spec** — `(source-field → target-slot + type-coercion + transform-fn)`
- **Geometry mapper** — CSV lat/lon columns → `:type geometry` Point auto-detection
- **Type coercion registry** — string → UUID, integer, float, boolean, geometry, vector (future)
- **Default value / error-on-missing** per slot

### 5. `import-export/reconciliation`
- **ID mapping table** — persistent (on-disk lhash) or in-memory: source-id ↔ VG-UUID
- **Upsert logic** — lookup by source-id property; if exists, update; else create
- **Conflict policy** — `:upsert` (default), `:skip`, `:error`

---

## Data Flow

```
IMPORT (e.g., Wikidata JSONL)
────────────────────────────────────────────────────────────────────
1. OPEN file → streaming parser (JSONL: line-by-line; CSV: row-by-row; Parquet: row-group)
2. FOR each record:
     a. PARSE raw record → plist/alist
     b. APPLY mapping spec → normalized slot values (with type coercion)
     c. RESOLVE ID: lookup source-id in reconciliation table
        - found → existing VG-UUID (upsert path)
        - not found → generate new VG-UUID, record mapping
     d. BUILD vertex/edge constructor args
     e. ACCUMULATE in chunk buffer (size = :chunk-size, default 1000)
3. WHEN chunk full OR end-of-file:
     a. WITH-TRANSACTION:
          - FOR each buffered record: MAKE-VERTEX / MAKE-EDGE (or UPDATE via COPY+SAVE)
          - ON conflict: apply :upsert/:skip/:error policy
     b. COMMIT → persist reconciliation table + write resume token (file pos + last IDs)
     c. CLEAR buffer, force GC if heap > threshold
4. RETURN import stats: counts, errors, resume token (for resumability)

EXPORT (e.g., JSONL)
────────────────────────────────────────────────────────────────────
1. OPEN output stream
2. MAP-VERTICES / MAP-EDGES (typed scan for MVCC snapshot consistency)
3. FOR each node:
     a. EXTRACT slot values per export mapping (or all slots)
     b. APPLY inverse type coercion (VG-UUID → string, geometry → {lat,lon}, etc.)
     c. SERIALIZE to format (JSONL: one JSON object per line)
     d. WRITE to stream
4. FLUSH stream, return stats
```

---

## Interfaces & Contracts

### Public API (package `graph-db`)

```lisp
;; Import
(import-graph :format :jsonl
              :source "/path/to/file.jsonl"
              :graph *graph*
              :mapping *my-mapping-spec*
              :conflict-policy :upsert
              :chunk-size 1000
              :resume-token nil)  ; or token from previous partial import
  → (values stats resume-token)

;; Export
(export-graph :format :csv
              :target "/path/to/output/"
              :graph *graph*
              :vertex-types '(person customer)
              :edge-types '(likes sells)
              :mapping *my-export-mapping*
              :include-geometry t)  ; adds lat/lon columns for geometry slots
  → stats

;; Mapping spec (Lisp form — also loadable from JSON/YAML file)
(defparameter *my-mapping-spec*
  '(:vertex-types
    (person
     (:source-id "id" :target-slot :id :coerce uuid)  ; WKT ID → VG UUID
     (:source-field "name" :target-slot :first-name)
     (:source-field "email" :target-slot :email :coerce email))
    :edge-types
    (knows
     (:source-from "from_id" :target-from :from)
     (:source-to "to_id" :target-to :to)
     (:source-field "since" :target-slot :weight :coerce float))))
```

### Format Protocol (internal)

```lisp
(defgeneric import-format (format source graph mapping opts)
  (:documentation "Import from SOURCE into GRAPH per MAPPING. Returns (values stats resume-token)."))

(defgeneric export-format (format target graph mapping opts)
  (:documentation "Export GRAPH to TARGET per MAPPING. Returns stats."))

(defgeneric format-streaming-p (format)
  (:documentation "True if format supports constant-memory streaming (JSONL, CSV, Parquet)."))

(defgeneric format-supports-export (format)
  (:documentation "True if format has export implementation."))
```

### Mapping DSL

```lisp
;; Coercion types: uuid, string, integer, float, boolean, geometry, email, vector (future)
;; Transform: optional lambda (raw-value → coerced-value) for custom logic
(:source-field "raw_col" :target-slot :slot-name :coerce integer :transform #'(lambda (x) (* x 1000)))
```

---

## Storage

### Reconciliation Table (per graph, optional)
- **On-disk**: lhash at `<graph-location>/import-id-map/` — key: source-id (string), value: VG-UUID (16-byte array)
- **In-memory**: hash-table for small imports (< 100K records)
- **Persisted** at each chunk commit; survives crash/restart for resumability
- **GC**: entries never expire (needed for future upserts); admin can rebuild

### Resume Token
- **Structure**: `(file-position . (last-vertex-id last-edge-id))`
- **Serialized** as JSON sidecar: `<source-file>.vg-import-token.json`
- **Used** to skip already-processed records on restart

### Geometry Handling
- **Import**: Detect `:type geometry :index t` slots → auto-map CSV `lat,lon` or `wkt` columns → `make-point`
- **Export**: Geometry slot → add `lat`, `lon` columns (Point) or `wkt` column (Polygon)

---

## Trade-offs

| Decision                                            | Rationale                                                                 | Cost                                                               |
| --------------------------------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| **Lisp mapping DSL + optional JSON/YAML**           | Native Lisp users get full power; config-file users get portability       | Two parsers to maintain                                            |
| **Chunked transactions (not single giant TX)**      | MVCC + OCC: large TX = high conflict risk, huge read-set, memory pressure | More commits = slower; tunable `:chunk-size`                       |
| **Reconciliation table on-disk (lhash)**            | Survives crash, works for 100M+ records, same engine as vertex table      | Extra disk I/O per chunk; mitigated by batching                    |
| **Streaming JSONL/CSV/Parquet; DOM for GML**        | GML is inherently hierarchical; JSONL/CSV/Parquet are record-oriented     | GML import not constant-memory (acceptable: GML typically smaller) |
| **Reuse `cl-json`, `cl-csv`; FFI only for Parquet** | Quicklisp packages exist and are mature                                   | Parquet needs `cl-arrow` or Arrow C++ FFI — evaluate maturity      |
| **Wikidata via JSONL dump (not SPARQL)**            | Streaming; no endpoint dependency; 100GB JSONL is standard                | Must download dump first (external step)                           |
| **Defer TuringDB/Ladybug export**                   | No documented wire format found                                           | If spec appears later, add format file without core changes        |

---

## Risks

1. **Parquet library maturity** — `cl-arrow` may be immature on ECL/CCL. Mitigation: FFI to Apache Arrow C++ as fallback; make Parquet format optional (load-time feature flag).

2. **Wikidata JSON dump size** — 100GB+ compressed. Streaming parser must handle bz2/gz transparently. Mitigation: use `trivial-shell` to pipe `bzcat`/`zcat` → stdin, or `cl-bzip2`/`gzip-stream` if available.

3. **ID space collision** — Wikidata Q-numbers vs. VG UUIDs. Mitigation: always preserve source ID as property (`:source-id`), never use as VG UUID.

4. **Schema drift during long import** — User adds `def-vertex` mid-import. Mitigation: import acquires schema read-lock per chunk; schema changes wait (existing rw-lock protocol).

5. **MVCC snapshot consistency** — Export uses typed `map-vertices`/`map-edges` (snapshot-consistent). Import creates new nodes (no read-set conflict). Verified.

6. **ECL/CCL compatibility** — `cl-arrow` FFI may not work on ECL. Mitigation: Parquet format behind `#+sbcl` initially; document limitation.

7. **Geometry coercion ambiguity** — CSV may have `lat,lon` OR `wkt` OR `geojson`. Mitigation: mapping spec declares `:coerce geometry` + `:geometry-format :latlon|:wkt|:geojson`.

---

## Out-of-Scope

- Real-time CDC / change capture (separate PRD)
- Graph transformation/cleaning during import (user pre-processes)
- SPARQL endpoint ingestion (use JSON/NTriples dumps)
- TuringDB/Ladybug native export (deferred pending spec)
- Visualization (separate PRD)
- Vector embeddings import/export (separate PRD: "Vector Embeddings & Similarity Search")

---

## Implementation Phases

| Phase | Deliverable                                                                                    | Formats    |
| ----- | ---------------------------------------------------------------------------------------------- | ---------- |
| 1     | Core framework: protocol, mapping DSL, reconciliation table, chunked TX, streaming coordinator | —          |
| 2     | JSONL import/export (simplest, line-oriented)                                                  | JSONL      |
| 3     | CSV import/export (tabular, common)                                                            | CSV        |
| 4     | GML import/export (wrap existing `algorithms-io`)                                              | GML        |
| 5     | Parquet import/export (evaluate `cl-arrow` vs Arrow C++ FFI)                                   | Parquet    |
| 6     | Wikidata JSONL import (streaming, 100GB-scale)                                                 | Wikidata   |
| 7     | YAGO import (TSV/NTriples)                                                                     | YAGO       |
| 8     | TuringDB/Ladybug export (if specs found)                                                       | (deferred) |

---

## Dependencies (Quicklisp)

| Package                    | Purpose                      | Status                          |
| -------------------------- | ---------------------------- | ------------------------------- |
| `cl-json`                  | JSON/JSONL parse + serialize | Already in core deps            |
| `cl-csv`                   | CSV parse + serialize        | Add to `graph-db/import-export` |
| `cl-arrow`                 | Parquet via Apache Arrow     | Evaluate; optional              |
| `yason` / `jonathan`       | Alternative JSON (faster)    | Benchmark vs `cl-json`          |
| `gzip-stream` / `cl-bzip2` | Compressed Wikidata streams  | Optional                        |

No new core dependencies. `graph-db/import-export` system declares its own `:depends-on`.