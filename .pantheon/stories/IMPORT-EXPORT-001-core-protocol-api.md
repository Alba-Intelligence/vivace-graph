---
id: IMPORT-EXPORT-001
title: Core format protocol, format registry, and public API (import-graph/export-graph)
status: completed
epic: Epic 1: Core Framework + JSONL Import/Export
deity: vulcan
---
## Goal
Establish the `graph-db/import-export` ASDF system with the format protocol (generic functions), format registry, and the public `import-graph` / `export-graph` API entry points. This story creates the skeleton that all format implementations plug into.

## Acceptance criteria
- [ ] New ASDF system `graph-db/import-export` defined in `graph-db.asd` with `:depends-on (:graph-db/core :cl-json :cl-ppcre)` and `:serial t`
- [ ] Package `graph-db.import-export` defined in `import-export/package.lisp` exporting: `import-graph`, `export-graph`, `*format-registry*`, `register-format`, `format-streaming-p`, `format-supports-export`
- [ ] Generic functions defined in `import-export/protocol.lisp`:
  - `import-format (format source graph mapping opts)` → (values stats resume-token)
  - `export-format (format target graph mapping opts)` → stats
  - `format-streaming-p (format)` → boolean
  - `format-supports-export (format)` → boolean
- [ ] Format registry `*format-registry*` (hash-table format-keyword → format-object) with `register-format` function
- [ ] Public API in `import-export/api.lisp`:
  - `import-graph` with keys: `:format`, `:source`, `:graph`, `:mapping`, `:conflict-policy`, `:chunk-size`, `:resume-token` → (values stats resume-token)
  - `export-graph` with keys: `:format`, `:target`, `:graph`, `:vertex-types`, `:edge-types`, `:mapping`, `:include-geometry` → stats
  - Both validate format exists in registry, delegate to `import-format`/`export-format`
- [ ] System loads without errors on SBCL/ECL/CCL
- [ ] Unit test: register a dummy format, call `import-graph`/`export-graph`, verify delegation works

## Affected files
- graph-db.asd (modified - add graph-db/import-export system)
- import-export/package.lisp (new)
- import-export/protocol.lisp (new)
- import-export/api.lisp (new)

## Architecture context
> ### 1. `import-export` package (new system: `graph-db/import-export`)
> Core orchestration layer. Defines:
> - **Format protocols** — generic functions `import-format`, `export-format` dispatching on format keyword
> - **Schema mapping DSL** — Lisp-based mapping spec (plist/alist) + optional external JSON/YAML config
> - **Conflict resolution policies** — `:upsert`, `:skip`, `:error` per import
> - **Streaming coordinator** — chunked transactional imports with resume tokens
> - **ID reconciliation** — source ID → VivaceGraph UUID mapping (preserve as property)
>
> ### Public API (package `graph-db`)
> ```lisp
> ;; Import
> (import-graph :format :jsonl
>               :source "/path/to/file.jsonl"
>               :graph *graph*
>               :mapping *my-mapping-spec*
>               :conflict-policy :upsert
>               :chunk-size 1000
>               :resume-token nil)  ; or token from previous partial import
>   → (values stats resume-token)
>
> ;; Export
> (export-graph :format :csv
>               :target "/path/to/output/"
>               :graph *graph*
>               :vertex-types '(person customer)
>               :edge-types '(likes sells)
>               :mapping *my-export-mapping*
>               :include-geometry t)  ; adds lat/lon columns for geometry slots
>   → stats
> ```
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

## Out of scope
- Mapping DSL parsing (Story 002)
- Reconciliation table (Story 003)
- Streaming coordinator / chunked transactions (Story 004)
- JSONL format implementation (Story 005)
- Any format-specific code beyond the registry protocol