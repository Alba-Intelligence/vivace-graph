---
id: IMPORT-EXPORT-005
title: JSONL format implementation — streaming parser + serializer using cl-json
status: completed
epic: Epic 1: Core Framework + JSONL Import/Export
deity: vulcan
---
## Goal
Implement the JSONL (JSON Lines) format: streaming line-by-line parser for import, and serializer for export. Registers with format registry as `:jsonl`. Uses `cl-json` (already in core deps) for JSON encoding/decoding.

## Acceptance criteria
- [ ] `import-export/formats/jsonl.lisp` defines:
  - **Import**: `make-jsonl-parser (source)` — returns iterator function that reads one line at a time from SOURCE (pathname or stream), parses via `cl-json:decode-json-from-string`, returns plist/alist or `:eof`
  - **Export**: `make-jsonl-serializer (target-stream)` — returns function that takes a plist, encodes via `cl-json:encode-json-to-string`, writes line + newline to stream
  - **Format object** registered via `register-format`:
    - `:import-parser` → `make-jsonl-parser`
    - `:export-serializer` → `make-jsonl-serializer`
    - `:streaming-p` → t
    - `:supports-export` → t
- [ ] Import handles: file path (opens for reading), stream (uses directly), stdin (if source is `:stdin`)
- [ ] Export handles: file path (opens for writing), stream (uses directly), stdout (if target is `:stdout`)
- [ ] Vertex serialization: extracts all slots (or per mapping spec) → JSON object with `__type: "vertex"`, `__vg_type: "person"`, `__vg_id: "uuid-string"`, plus slot values
- [ ] Edge serialization: extracts all slots + from/to/weight → JSON object with `__type: "edge"`, `__vg_type: "likes"`, `__vg_id: "uuid-string"`, `__vg_from: "uuid-string"`, `__vg_to: "uuid-string"`, `__vg_weight: 1.0`, plus slot values
- [ ] Geometry slots: serialized as `{lat: ..., lon: ...}` for Point, `{wkt: "..."}` for Polygon
- [ ] Round-trip test: export graph to JSONL file → import into empty graph with same schema → verify bit-identical (all slots, types, IDs preserved via reconciliation table)
- [ ] Performance test: import 100K JSONL records in < 30 sec (SBCL), heap < 500MB
- [ ] Unit tests: parser handles malformed lines (skip + count error), empty lines, UTF-8; serializer produces valid JSONL

## Affected files
- import-export/formats/jsonl.lisp (new)
- import-export/package.lisp (modified - export format registration function)
- import-export/serialization.lisp (new - vertex/edge → JSON plist helpers shared by export)

## Architecture context
> ### 2. `import-export/formats` (sub-package)
> | File | Import | Export | Dependencies |
> |------|--------|--------|--------------|
> | `jsonl.lisp` | ✓ | ✓ | `cl-json` (already in core) |
>
> ### Format Protocol (internal)
> ```lisp
> (defgeneric import-format (format source graph mapping opts)
>   (:documentation "Import from SOURCE into GRAPH per MAPPING. Returns (values stats resume-token)."))
>
> (defgeneric export-format (format target graph mapping opts)
>   (:documentation "Export GRAPH to TARGET per MAPPING. Returns stats."))
>
> (defgeneric format-streaming-p (format)
>   (:documentation "True if format supports constant-memory streaming (JSONL, CSV, Parquet)."))
>
> (defgeneric format-supports-export (format)
>   (:documentation "True if format has export implementation."))
> ```
>
> ### Data Flow — EXPORT (JSONL)
> ```
> 1. OPEN output stream
> 2. MAP-VERTICES / MAP-EDGES (typed scan for MVCC snapshot consistency)
> 3. FOR each node:
>      a. EXTRACT slot values per export mapping (or all slots)
>      b. APPLY inverse type coercion (VG-UUID → string, geometry → {lat,lon}, etc.)
>      c. SERIALIZE to format (JSONL: one JSON object per line)
>      d. WRITE to stream
> 4. FLUSH stream, return stats
> ```

## Out of scope
- CSV/Parquet/GML/Wikidata/YAGO formats — separate stories
- Mapping DSL — Story 002
- Reconciliation table — Story 003
- Streaming coordinator — Story 004 (JSONL parser plugs into it)
- Public API — Story 001