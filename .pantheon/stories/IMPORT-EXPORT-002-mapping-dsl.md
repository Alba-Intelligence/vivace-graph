---
id: IMPORT-EXPORT-002
title: Mapping DSL — Lisp spec parser, JSON/YAML file loader, type coercion registry
status: completed
epic: Epic 1: Core Framework + JSONL Import/Export
deity: vulcan
---
## Goal
Implement the schema mapping DSL: Lisp-form spec parser, optional JSON/YAML file loader, and the type coercion registry (string → UUID, integer, float, boolean, geometry, email, etc.). This is the translation layer between source fields and VivaceGraph slots.

## Acceptance criteria
- [ ] `import-export/mapping.lisp` defines:
  - `parse-mapping-spec (spec)` — accepts Lisp form (plist/alist) per architecture DSL, returns normalized internal representation
  - `load-mapping-file (path)` — detects .json/.yaml/.yml extension, parses to same internal representation
  - `validate-mapping-spec (spec graph)` — verifies all target vertex/edge types exist in graph schema, all target slots exist on those types
- [ ] Type coercion registry `*coercion-registry*` (hash-table coercion-name → function) with built-in coercions:
  - `uuid` — string → 16-byte UUID array (uses `uuid:make-uuid-from-string`)
  - `integer` — string/number → integer
  - `float` — string/number → double-float
  - `boolean` — string/number/t/nil → boolean
  - `string` — passthrough
  - `email` — string → string (validates `@` present)
  - `geometry` — handled specially (see geometry mapper below)
- [ ] `coerce-value (coercion-name raw-value)` — looks up coercion function, applies it, signals typed error on failure
- [ ] Geometry mapper: `map-geometry (raw-value format-spec)` where format-spec is `:latlon` (expects plist with :lat :lon), `:wkt` (string), `:geojson` (object) → returns `geometry` object via `make-point`/`make-polygon`
- [ ] Mapping spec supports per-field `:transform` lambda (raw → coerced) for custom logic
- [ ] Mapping spec supports `:default` value and `:required` boolean per field
- [ ] Unit tests: parse Lisp spec, load JSON/YAML file, validate against example schema, coerce all built-in types, geometry mapping

## Affected files
- import-export/mapping.lisp (new)
- import-export/package.lisp (modified - export new symbols)
- import-export/coercions.lisp (new - coercion registry + built-ins)
- import-export/geometry-map.lisp (new - geometry mapper)

## Architecture context
> ### 4. `import-export/mapping`
> - **Mapping spec** — `(source-field → target-slot + type-coercion + transform-fn)`
> - **Geometry mapper** — CSV lat/lon columns → `:type geometry` Point auto-detection
> - **Type coercion registry** — string → UUID, integer, float, boolean, geometry, vector (future)
> - **Default value / error-on-missing** per slot
>
> ### Mapping DSL
> ```lisp
> ;; Coercion types: uuid, string, integer, float, boolean, geometry, email, vector (future)
> ;; Transform: optional lambda (raw-value → coerced-value) for custom logic
> (:source-field "raw_col" :target-slot :slot-name :coerce integer :transform #'(lambda (x) (* x 1000)))
> ```
>
> ### Data Flow (import step 2a-2b)
> ```
> 2. FOR each record:
>      a. PARSE raw record → plist/alist
>      b. APPLY mapping spec → normalized slot values (with type coercion)
> ```

## Out of scope
- Format-specific parsing (JSONL/CSV/Parquet record → plist) — that's in format implementation stories
- Reconciliation table lookup (source-id → VG-UUID) — Story 003
- Chunked transaction execution — Story 004
- Public API `import-graph`/`export-graph` — Story 001