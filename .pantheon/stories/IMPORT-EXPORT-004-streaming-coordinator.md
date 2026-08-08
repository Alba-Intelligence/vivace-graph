---
id: IMPORT-EXPORT-004
title: Streaming coordinator — chunked transaction manager, resume protocol, memory budget
status: completed
epic: Epic 1: Core Framework + JSONL Import/Export
deity: vulcan
---
## Goal
Implement the streaming import coordinator that processes records in chunks, wraps each chunk in a transaction, checkpoints resume tokens, and enforces the < 500MB heap budget. This is the engine that makes large imports (1M+ records) work in constant memory.

## Acceptance criteria
- [ ] `import-export/streaming.lisp` defines:
  - `with-import-stream (source format mapping graph opts &body body)` — macro that opens source (file or stdin), creates streaming parser per format, binds `*import-context*` with state
  - `*import-context*` (dynamic var) holding: format parser, graph, mapping, reconciliation table, chunk buffer, stats counters, resume token, current file position
  - `process-next-record (context)` — pulls one parsed record from format parser, applies mapping (Story 002), resolves ID via reconciliation (Story 003), pushes constructor args to chunk buffer
  - `flush-chunk (context)` — when chunk buffer reaches `:chunk-size` (default 1000) or end-of-stream:
    - `with-transaction` → for each buffered record: call upsert-vertex/upsert-edge (Story 003)
    - on conflict: apply `:upsert`/`:skip`/`:error` policy
    - commit → persist reconciliation table + write resume token
    - clear buffer, force GC if `(room)` shows heap > 500MB
  - `make-resume-token (context)` — returns `(file-position . (last-vertex-id last-edge-id))`
  - `write-resume-token (token source-path)` — writes JSON sidecar `<source-path>.vg-import-token.json`
  - `read-resume-token (source-path)` — reads token or returns nil
  - `import-stats (context)` — returns plist: `:vertices-created`, `:vertices-updated`, `:edges-created`, `:edges-updated`, `:errors`, `:chunks-committed`, `:resume-token`
- [ ] Resume protocol: if `:resume-token` passed to `import-graph`, seek to file-position, skip records until after last-vertex-id/last-edge-id (using reconciliation table to detect already-imported)
- [ ] Memory budget: after each chunk, check `(gc :full t)` if heap > threshold; log warning if still > 500MB
- [ ] Unit tests: import 10K JSONL records with chunk-size 100 → verify 100 chunks committed, resume token works (kill at chunk 50, restart → completes), heap stays bounded, stats accurate

## Affected files
- import-export/streaming.lisp (new)
- import-export/package.lisp (modified - export new symbols)

## Architecture context
> ### 3. `import-export/streaming`
> - **Chunked transaction manager** — groups N records per transaction, commits, checkpoints resume token (file position + last committed IDs)
> - **Resume protocol** — on failure, restart from token; skip already-imported via ID reconciliation table
> - **Memory budget** — enforces < 500MB heap via bounded buffers + forced GC between chunks
>
> ### Data Flow (import step 3)
> ```
> 3. WHEN chunk full OR end-of-file:
>      a. WITH-TRANSACTION:
>           - FOR each buffered record: MAKE-VERTEX / MAKE-EDGE (or UPDATE via COPY+SAVE)
>           - ON conflict: apply :upsert/:skip/:error policy
>      b. COMMIT → persist reconciliation table + write resume token (file pos + last IDs)
>      c. CLEAR buffer, force GC if heap > threshold
> 4. RETURN import stats: counts, errors, resume token (for resumability)
> ```
>
> ### Resume Token
> - **Structure**: `(file-position . (last-vertex-id last-edge-id))`
> - **Serialized** as JSON sidecar: `<source-file>.vg-import-token.json`
> - **Used** to skip already-processed records on restart

## Out of scope
- Format-specific parser (JSONL/CSV/Parquet) — Story 005 for JSONL, separate stories for others
- Mapping DSL application — Story 002
- Reconciliation table — Story 003
- Public API `import-graph` — Story 001 (delegates to streaming coordinator)
- Export streaming — export uses `map-vertices`/`map-edges` directly (simpler, no resume needed)