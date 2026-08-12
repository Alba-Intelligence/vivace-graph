---
id: IMPORT-EXPORT-003
title: Reconciliation table — on-disk lhash ID map (source-id ↔ VG-UUID) + upsert logic
status: completed
epic: Epic 1: Core Framework + JSONL Import/Export
deity: vulcan
---
## Goal
Implement the persistent reconciliation table that maps source IDs (e.g., Wikidata Q-numbers, CSV primary keys) to VivaceGraph UUIDs. This enables upsert semantics, resumability, and round-trip fidelity. Uses the existing lhash engine (same as vertex/edge tables).

## Acceptance criteria
- [ ] `import-export/reconciliation.lisp` defines:
  - `make-reconciliation-table (graph &key location)` — creates/opens lhash at `<graph-location>/import-id-map/` with key-test `string=`, value-bytes 16 (UUID array), bucket-size 24, base-buckets 8
  - `reconcile-id (table source-id)` — returns (values vg-uuid created-p); if source-id exists, returns stored UUID + nil; else generates new UUID (gen-vertex-id), stores it, returns UUID + t
  - `lookup-reconciliation (table source-id)` — returns VG-UUID or nil
  - `persist-reconciliation (table)` — flushes lhash to disk (called at each chunk commit)
  - `close-reconciliation (table)` — closes lhash cleanly
- [ ] In-memory fallback: `make-reconciliation-table` accepts `:in-memory t` for small imports (< 100K) — uses hash-table instead of lhash
- [ ] Upsert logic in `import-export/upsert.lisp`:
  - `upsert-vertex (graph type-id slot-data source-id conflict-policy)` — looks up source-id in reconciliation table; if found, COPY existing vertex, apply slot-data, SAVE; else MAKE-VERTEX with new UUID; records mapping
  - `upsert-edge (graph type-id from-source-id to-source-id weight slot-data source-id conflict-policy)` — resolves both endpoint source-ids via reconciliation, then upsert edge
  - `conflict-policy` = `:upsert` (default, update existing), `:skip` (keep existing, ignore new), `:error` (signal error on conflict)
- [ ] Source ID preserved as `:source-id` slot on vertex/edge (if slot exists in schema) — never used as VG UUID
- [ ] Unit tests: create table, reconcile 10K IDs, persist, reopen, verify all mappings intact; test upsert-vertex with all three conflict policies; test edge upsert with endpoint resolution

## Affected files
- import-export/reconciliation.lisp (new)
- import-export/upsert.lisp (new)
- import-export/package.lisp (modified - export new symbols)

## Architecture context
> ### 5. `import-export/reconciliation`
> - **ID mapping table** — persistent (on-disk lhash) or in-memory: source-id ↔ VG-UUID
> - **Upsert logic** — lookup by source-id property; if exists, update; else create
> - **Conflict policy** — `:upsert` (default), `:skip`, `:error`
>
> ### Storage — Reconciliation Table (per graph, optional)
> - **On-disk**: lhash at `<graph-location>/import-id-map/` — key: source-id (string), value: VG-UUID (16-byte array)
> - **In-memory**: hash-table for small imports (< 100K records)
> - **Persisted** at each chunk commit; survives crash/restart for resumability
> - **GC**: entries never expire (needed for future upserts); admin can rebuild
>
> ### Data Flow (import step 2c-2d)
> ```
>      c. RESOLVE ID: lookup source-id in reconciliation table
>         - found → existing VG-UUID (upsert path)
>         - not found → generate new VG-UUID, record mapping
>      d. BUILD vertex/edge constructor args
> ```

## Out of scope
- Streaming coordinator / chunked transactions (Story 004)
- JSONL format parser (Story 005)
- Mapping DSL application (Story 002 — provides normalized slot-data to upsert)
- Public API — Story 001