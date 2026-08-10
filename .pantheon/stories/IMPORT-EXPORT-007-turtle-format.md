---
id: IMPORT-EXPORT-007
title: Turtle format import (YAGO dump)
status: in-progress
epic: Epic 1: Core Framework + JSONL Import/Export
deity: vulcan
---
## Goal
Implement Turtle (TTL) format import from YAGO 4.6 dumps. Parses standard Turtle syntax, resolves URIs to UUIDs, extracts typed triples (rdf:type + predicates), and populates vertex/edge types using existing mapping or schema inference.

## Acceptance criteria
- [ ] New ASDF system component `graph-db/import-export-turtle` with depend on :graph-db/core
- [ ] Package `graph-db/import-export.turtle` exporting `import-turtle`
- [ ] Turtle parser in `import-export/turtle.lisp`:
  - Parse raw Turtle file into triple stream: (subject predicate object)
  - Handle `:prefix` declarations, `rdf:type` extraction, blank nodes
  - Default mapping: subject → vertex UUID, predicate → slot-name, object → slot-value
  - Source-ID preserved as property (e.g., `:uri`), using reconciliation table
- [ ] Import API `import-turtle` in `graph-db/import-export` (mirror `import-graph` signature but dedicated to Turtle)
- [ ] Schema inference: when no mapping, infer vertex type from `rdf:type` and slot names from unique predicates
- [ ] Memory-efficient streaming parser (lines or tokens) for GB-size YAGO dumps
- [ ] Integration test `tests/import-export/turtle-roundtrip.lisp`:
  - Load YAGO 4.6 sample
  - Verify vertices/edges created with correct slots/values
  - Verify URI preservation via reconciliation table

## Architecture context
> ### 6. `import-export/turtle`
> - **Turtle parser** — lightweight, streaming, CL-native (no external lib)
> - **Schema inference** — auto-infer vertex types and slots from RDF vocabulary
> - **URI handling** — preserve original URIs as `:uri` slot, UUID resolves via reconciliation
> - **YAGO dump support** — optimized for YAGO 4.6 structure and common predicates (`rdf:type`, `rdfs:label`, `dbo:homepage`, etc.)
>
> ### Integration points
> - Reuses existing mapping DSL (`parse-mapping-spec`) when provided, otherwise auto-generates
> - Uses reconciliation table for deterministic UUIDs (source-id → VG-UUID)
> - Integrates with streaming coordinator (`with-import-stream`) for memory efficiency
> - Compatible with existing `import-graph` command-line interface
>
> ### Format configuration (for future extensibility)
> ```lisp
> ;; YAGO Turtle import (auto-infer schema)
> (import-turtle
>   :format :turtle
>   :source "yago-4-6.ttl"
>   :graph *graph*
>   :conflict-policy :upsert
>   :chunk-size 500
>   :in-memory-reconciliation t)
> ```

## Out of scope
- Export Turtle functionality (separate story)
- YAGO ontology processing beyond simple extraction
- External tool dependencies (prefer pure CL parser)
- Complex RDF reasoning (e.g., inference, consistency checks)