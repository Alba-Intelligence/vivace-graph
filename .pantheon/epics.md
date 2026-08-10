# Epics: Import/Export — Ecosystem Interoperability

Ordered by **first-shippable-value**. Each epic is independently shippable — a user can `ql:quickload :graph-db/import-export` and immediately use the formats in that epic.

---

## Epic 1: Core Framework + JSONL Import/Export
**Value:** Users can round-trip graphs via JSONL (one JSON object per line) — the simplest, most universal interchange format — with full mapping DSL, conflict resolution, streaming, and resumability.

**Components Touched:**
- `import-export` package (protocol, mapping DSL, conflict policies)
- `import-export/streaming` (chunked TX manager, resume protocol, memory budget)
- `import-export/mapping` (spec parser, type coercion registry, geometry mapper)
- `import-export/reconciliation` (on-disk lhash ID map, upsert logic)
- `import-export/formats/jsonl.lisp` (streaming parser + serializer using `cl-json`)

**Definition of Done:**
- `(import-graph :format :jsonl ...)` imports 1M records in < 2 min (SBCL), constant heap < 500MB
- `(export-graph :format :jsonl ...)` exports typed vertex/edge scan to JSONL
- Round-trip: export → import → bit-identical graph for all supported slot types
- Resume token works: kill mid-import, restart with token → completes without duplicates
- Conflict policies `:upsert` (default), `:skip`, `:error` verified
- Mapping DSL loads from Lisp form AND JSON/YAML file
- Works on SBCL, ECL, CCL (Linux x86_64)

---

## Epic 2: CSV Import/Export
**Value:** Data scientists and analysts can import/export tabular data (the default output of spreadsheets, SQL exports, ETL pipelines) with automatic geometry detection (lat/lon → Point).

**Components Touched:**
- `import-export/formats/csv.lisp` (streaming parser + serializer using `cl-csv`)
- `import-export/mapping` (geometry auto-detection for `:type geometry :index t` slots)
- `import-export/reconciliation` (reuses ID map; no new code)

**Definition of Done:**
- CSV import: streaming row-by-row, handles quoted fields, configurable delimiter
- CSV export: one file per vertex type + one per edge type (or single file with `type` column)
- Geometry mapping: CSV `lat,lon` columns → `make-point` for geometry slots; `wkt` column → polygon
- Round-trip with JSONL: CSV export → JSONL import → identical graph
- Chunked transactions + resume token work identically to Epic 1

---

## Epic 3: GML Import/Export (Wrap Existing)
**Value:** Users migrating from NetworkX, Gephi, yEd, or `graph-db/algorithms-io` can import/export GML without data loss — leverages battle-tested parser already in codebase.

**Components Touched:**
- `import-export/formats/gml.lisp` (thin wrapper around `graph-db-aio:parse-gml` + `graph->dot`/`visualize`)
- `import-export/mapping` (GML `label`/`value` → slot mapping via DSL)
- `import-export/reconciliation` (reuses ID map)

**Definition of Done:**
- `import-gml` / `export-gml` work via `import-graph`/`export-graph` unified API
- Preserves node `id`, `label`, `value` and edge `source`, `target`, `value` (weight)
- Mapping DSL maps GML fields to VivaceGraph slots (e.g., GML `label` → `:name` slot)
- Round-trip with JSONL/CSV: GML → JSONL → GML → identical topology + properties
- **Non-streaming** (DOM parser) — documented limitation; GML typically < 100K nodes

---

## Epic 4: Parquet Import/Export
**Value:** Columnar, typed, compressed format for big-data pipelines (Spark, Pandas, Arrow) — enables high-performance analytics workflows.

**Components Touched:**
- `import-export/formats/parquet.lisp` (using `cl-arrow` or `cffi` + Apache Arrow C++)
- `import-export/mapping` (Parquet schema → mapping spec auto-generation)
- `import-export/streaming` (row-group streaming for constant memory)

**Definition of Done:**
- **Import**: streams row-groups, applies mapping, chunked TX, resume token
- **Export**: writes typed Parquet with schema derived from vertex/edge types
- Type fidelity: integer/float/boolean/string/geometry preserved (no stringly-typed columns)
- Optional behind `#+sbcl` initially if `cl-arrow` FFI fails on ECL/CCL — documented
- Round-trip with JSONL/CSV: Parquet → JSONL → Parquet → identical graph
- 1M records import < 3 min (SBCL), heap < 500MB

---

## Epic 5: Wikidata Streaming Import
**Value:** Knowledge-graph researchers can ingest the full Wikidata dump (100GB+ JSONL.bz2) directly into VivaceGraph — streaming, resumable, no external database required.

**Components Touched:**
- `import-export/formats/wikidata.lisp` (streaming JSONL parser with bz2/gz pipe via `trivial-shell`)
- `import-export/mapping` (Wikidata entity schema → mapping spec template included)
- `import-export/reconciliation` (Q-number → UUID map; Q-number preserved as `:wikidata-id` slot)

**Definition of Done:**
- Imports `latest-all.json.bz2` via `bzcat | import-graph :format :wikidata` (stdin streaming)
- Mapping template extracts: `id` (Q-number), `labels`, `descriptions`, `claims` (property → value)
- Chunked TX + resume token: crash at 50M entities → restart from token → completes
- Heap stays < 500MB throughout 100GB import
- 1M entities < 10 min (SBCL) — meets PRD success metric
- **Import only** (Wikidata export not in scope — use JSONL/Parquet export)

---

## Epic 6: YAGO Import
**Value:** Researchers can ingest YAGO knowledge graph (TSV/NTriples) for academic/workload benchmarking.

**Components Touched:**
- `import-export/formats/yago.lisp` (TSV streaming via `cl-csv` or NTriples parser)
- `import-export/mapping` (YAGO schema → mapping spec template)

**Definition of Done:**
- Streams YAGO TSV/NTriples dump (format confirmed at implementation start)
- Mapping template extracts entities, types, facts
- Chunked TX + resume token + heap budget work identically
- **Import only** (YAGO export not in scope)

---

## Deferred: Epic 7 — TuringDB / Ladybug Native Export
**Status:** Deferred pending documented wire format specifications.
**Trigger:** If/when TuringDB or Ladybug publish import specs, add `turingdb.lisp` / `ladybug.lisp` format files — no core changes needed (protocol extensible).

---

## Cut Scope (Explicitly Not In These Epics)
| Item                                        | Reason             | Tracking                                    |
| ------------------------------------------- | ------------------ | ------------------------------------------- |
| SPARQL endpoint ingestion                   | Non-goal per PRD   | Separate PRD if needed                      |
| Real-time CDC / change capture              | Non-goal per PRD   | Separate PRD                                |
| Graph transformation/cleaning during import | User pre-processes | Document ETL best practices                 |
| Visualization                               | Separate PRD       | Epic in Web UI PRD                          |
| Vector embeddings import/export             | Separate PRD       | "Vector Embeddings & Similarity Search" PRD |
| TuringDB/Ladybug native export              | No spec found      | Deferred epic above                         |

---

## Dependency Order
```
Epic 1 (Core + JSONL) ──┬── Epic 2 (CSV)
                        ├── Epic 3 (GML)  [independent, wraps existing]
                        ├── Epic 4 (Parquet) [needs Epic 1 streaming]
                        ├── Epic 5 (Wikidata) [needs Epic 1 streaming + JSONL parser]
                        └── Epic 6 (YAGO) [needs Epic 1 streaming + CSV parser]
```
Epic 1 **must** ship first — all others depend on its framework. Epics 2–6 can be developed in parallel after Epic 1 is stable.