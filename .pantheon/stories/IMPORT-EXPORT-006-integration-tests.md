---
id: IMPORT-EXPORT-006
title: Integration tests — round-trip verification, performance benchmarks, SBCL/ECL/CCL compatibility
status: completed
epic: Epic 1: Core Framework + JSONL Import/Export
deity: vulcan
---
## Goal
End-to-end integration tests proving the full Epic 1 pipeline works: import-graph → export-graph → import-graph round-trip fidelity, performance targets met, and cross-implementation compatibility (SBCL, ECL, CCL on Linux x86_64).

## Acceptance criteria
- [ ] Test file `tests/import-export/roundtrip.lisp` (loaded via new `graph-db/import-export-test` system in `graph-db.asd`):
  - Defines test schema: vertex types `person` (first-name, last-name, email), `product` (name, upc), edge type `likes` (weight)
  - Creates graph, imports 10K JSONL records (mixed vertices/edges) via `import-graph :format :jsonl`
  - Exports same graph via `export-graph :format :jsonl`
  - Imports exported JSONL into fresh graph → verifies:
    - Vertex count matches
    - Edge count matches
    - All slot values equal (string= for strings, = for numbers)
    - UUIDs preserved via reconciliation table (source-id → same VG-UUID)
    - Edge from/to UUIDs match
- [ ] Conflict policy tests: import same data twice with `:upsert` (idempotent), `:skip` (no changes), `:error` (signals error)
- [ ] Resume token test: import 5K records, kill process (simulate by throwing), restart with token → completes 5K remaining, total 10K, no duplicates
- [ ] Memory test: import 100K records with chunk-size 1000 → monitor `(room)` after each chunk, assert heap < 500MB throughout
- [ ] Performance benchmark (SBCL): import 1M JSONL records in < 2 min; export 1M vertices+edges in < 2 min
- [ ] Cross-implementation test: document that test suite passes on SBCL, ECL, CCL (Linux x86_64) — note any implementation-specific limitations
- [ ] Mapping DSL test: load mapping from Lisp form AND from JSON file → same internal representation
- [ ] Geometry test: vertex with `:type geometry :index t` slot → export includes `{lat, lon}`, import reconstructs Point correctly

## Affected files
- graph-db.asd (modified - add graph-db/import-export-test system)
- tests/import-export/roundtrip.lisp (new)
- tests/import-export/package.lisp (new)
- tests/import-export/suite.lisp (new)
- import-export/package.lisp (no change)
- example-import-export.lisp (new - demonstration script like example.lisp)

## Architecture context
> ### Definition of Done (Epic 1)
> - `(import-graph :format :jsonl ...)` imports 1M records in < 2 min (SBCL), constant heap < 500MB
> - `(export-graph :format :jsonl ...)` exports typed vertex/edge scan to JSONL
> - Round-trip: export → import → bit-identical graph for all supported slot types
> - Resume token works: kill mid-import, restart with token → completes without duplicates
> - Conflict policies `:upsert` (default), `:skip`, `:error` verified
> - Mapping DSL loads from Lisp form AND JSON/YAML file
> - Works on SBCL, ECL, CCL (Linux x86_64)
>
> ### Success Metrics (PRD)
> - Import 1M Wikidata entities in < 10 minutes (SBCL)
> - Round-trip export → import → bit-identical graph for supported types
> - Zero data loss on schema mismatch (explicit error or mapped default)
> - Streaming import: constant heap < 500MB regardless of input size
> - Works on SBCL, ECL, CCL (Linux x86_64)

## Out of scope
- CSV/Parquet/GML/Wikidata/YAGO format tests — separate epic stories
- Visualization tests — separate PRD
- Vector embeddings tests — separate PRD
- Load testing beyond 1M records (Wikidata-scale tested in Epic 5)