# PRD: Import/Export — Ecosystem Interoperability

## Problem
VivaceGraph must plug into existing graph/database ecosystems. Import/export is critical for adoption — users cannot migrate existing graphs in, nor exchange data with TuringDB, Ladybug, or knowledge graphs (Wikidata, YAGO) out.

## Users
- **Internal team** — tooling, migration, testing
- **External VivaceGraph users** — library consumers building applications
- **Data scientists / KG researchers** — batch ingestion of Wikidata, YAGO, custom datasets
- **Application developers** — runtime import/export for hybrid workflows

## Goals
1. **Import** (priority order): GML → JSONL → CSV → Parquet → Wikidata dump → YAGO
2. **Export** (priority order): GML → JSONL → CSV → Parquet → TuringDB native (if spec exists) → Ladybug native (if spec exists)
3. **Streaming** — constant memory for large datasets (100M+ entities)
4. **Transactional** — all-or-nothing import; resumable on failure
5. **Schema mapping** — declarative mapping from source columns to VivaceGraph slots/types
6. **Conflict resolution** — upsert / skip / error policies per import
7. **Round-trip fidelity** — export → import → identical graph (modulo unsupported features)

## Non-Goals
- Real-time CDC / change capture
- Graph transformation/cleaning during import (separate ETL step)
- Visualization (separate PRD)
- SPARQL endpoint ingestion (Wikidata: use JSON/NTriples dumps)

## Success Metrics
- Import 1M Wikidata entities in < 10 minutes (SBCL)
- Round-trip export → import → bit-identical graph for supported types
- Zero data loss on schema mismatch (explicit error or mapped default)
- Streaming import: constant heap < 500MB regardless of input size
- Works on SBCL, ECL, CCL (Linux x86_64)

## Constraints
- **Reuse existing Quicklisp packages** — no reinventing parsers
- **Pure Common Lisp where possible**; FFI only for Parquet (Apache Arrow via `cl-arrow` or `cffi`)
- **SBCL/ECL/CCL compatibility** — no implementation-specific APIs without fallback
- Streaming + transactional where implementation permits (e.g., JSONL/CSV/Parquet stream; GML may need DOM)
- Leverage existing `graph-db/algorithms-io` (GML/Graphviz/Pajek) as foundation

## Open Questions
1. **TuringDB/Ladybug native formats** — are wire formats documented? If not, export to these is deferred.
2. **Wikidata dump source** — JSON dump (latest-all.json.bz2), RDF/NTriples, or both? JSON is ~100GB compressed.
3. **YAGO format** — TSV? NTriples? Confirm schema.
4. **Schema mapping DSL** — Lisp-based (plist/alist), external config file (JSON/YAML), or both?
5. **Conflict resolution default** — upsert (merge by ID), skip, or error?
6. **Parquet library** — `cl-arrow` maturity? Fallback to `cffi` + Apache Arrow C++?
7. **Geometry mapping** — CSV lat/lon columns → VivaceGraph `:type geometry` (Point) automatically?
8. **ID reconciliation** — source IDs (Wikidata Q-numbers) → VivaceGraph UUIDs? Preserve as property?
