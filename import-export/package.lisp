;;;; graph-db/import-export/package.lisp
;;;; Package definition for the import/export system.

(defpackage :graph-db.import-export
  (:use :cl :alexandria :cl-ppcre)
  (:nicknames :graph-db-ie)
  (:export
   ;; Public API
   #:import-graph
   #:export-graph
   ;; Format protocol
   #:*format-registry*
   #:register-format
   #:format-streaming-p
   #:format-supports-export
   #:import-format
   #:export-format
   #:make-format-spec
   #:format-spec-import-parser
   #:format-spec-export-serializer
   #:format-spec-name
   ;; Mapping
   #:parse-mapping-spec
   #:load-mapping-file
   #:validate-mapping-spec
   #:*coercion-registry*
   #:coerce-value
   #:register-coercion
   #:map-geometry
   ;; Reconciliation
   #:make-reconciliation-table
   #:reconcile-id
   #:lookup-reconciliation
   #:persist-reconciliation
   #:close-reconciliation
   #:upsert-vertex
   #:upsert-edge
   ;; Streaming
   #:with-import-stream
   #:process-next-record
   #:flush-chunk
   #:make-resume-token
   #:write-resume-token
   #:read-resume-token
   #:import-stats
   #:*import-context*
   ;; Serialization
   #:vertex->plist
   #:edge->plist
   #:plist->vertex-args
   #:plist->edge-args
   ;; Format registration (for format implementors)
   #:register-jsonl-format))