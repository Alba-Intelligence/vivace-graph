;;;; graph-db/import-export/api.lisp
;;;; Public API: import-graph / export-graph

(in-package :graph-db.import-export)

;;; ---------------------------------------------------------------------------
;;; UUID string/array conversion helpers
;;; ---------------------------------------------------------------------------

(defun uuid-array->string (uuid-array)
  "Convert a 16-byte UUID array to standard UUID string."
  (graph-db:string-id uuid-array))

(defun string->uuid-array (uuid-string)
  "Convert a standard UUID string to 16-byte array."
  (let ((uuid (uuid:make-uuid-from-string uuid-string)))
    (uuid:uuid-to-byte-array uuid)))

;;; ---------------------------------------------------------------------------
;;; Import context
;;; ---------------------------------------------------------------------------

(defstruct import-context
  "Streaming import context holding parser, graph, mapping, and state."
  (format nil :type symbol)
  (parser nil :type function)
  (parser-stream nil :type (or null stream))
  (graph *graph* :type t)
  (mapping nil :type (or null list))
  (reconciliation-table nil :type (or null reconciliation-table))
  (chunk-buffer nil :type list)
  (conflict-policy :upsert :type symbol)
  (chunk-size 1000 :type fixnum)
  (resume-token nil :type (or null cons))
  (in-memory-reconciliation nil :type boolean)
  (stats (list :vertices-created 0 :vertices-updated 0
               :edges-created 0 :edges-updated 0
               :errors 0 :chunks-committed 0)
         :type list)
  (file-position 0 :type fixnum)
  (last-vertex-id nil :type (or null (simple-array (unsigned-byte 8) (*))))
  (last-edge-id nil :type (or null (simple-array (unsigned-byte 8) (*)))))

(defvar *import-context* nil
  "Dynamically bound during import; holds streaming state.")

;;; ---------------------------------------------------------------------------
;;; Streaming coordinator macros
;;; ---------------------------------------------------------------------------

(defmacro with-import-stream ((source format mapping-spec graph
                               &key conflict-policy chunk-size
                                    resume-token in-memory-reconciliation
                                    location)
                              &body body)
  "Open SOURCE with FORMAT parser, bind *IMPORT-CONTEXT*, execute BODY.

OPTIONS:
  :CONFLICT-POLICY — :upsert (default), :skip, or :error
  :CHUNK-SIZE — number of records per transaction (default 1000)
  :RESUME-TOKEN — token from previous partial import, or NIL
  :IN-MEMORY-RECONCILIATION — use hash-table instead of on-disk lhash
  :LOCATION — on-disk store path for reconciliation lhash"
  (let ((ctx (gensym "CTX"))
        (fmt (gensym "FMT"))
        (parser (gensym "PARSER"))
        (stream (gensym "STREAM")))
    `(let* ((,fmt (find-format ,format))
            (,stream (if (streamp ,source)
                         ,source
                         (open-turtle-stream ,source)))
                (,parser (funcall (format-spec-import-parser ,fmt) ,stream))
                (,ctx (make-import-context
                       :format ,format
                       :parser ,parser
                       :parser-stream (if (streamp ,source) nil ,stream)
                       :graph ,graph
                       :mapping (cond
                                  ((null ,mapping-spec) nil)
                                  ((pathnamep ,mapping-spec) (load-mapping-file ,mapping-spec))
                                  ((stringp ,mapping-spec) (load-mapping-file ,mapping-spec))
                                  (t (parse-mapping-spec ,mapping-spec)))
                       :reconciliation-table (make-reconciliation-table
                                              ,graph
                                              :location ,location
                                              :in-memory ,in-memory-reconciliation)
                       :conflict-policy (or ,conflict-policy :upsert)
                       :chunk-size (or ,chunk-size 1000)
                       :resume-token ,resume-token
                       :in-memory-reconciliation ,in-memory-reconciliation)))
       (declare (ignorable ,stream))
       (unwind-protect
            (progn ,@body)
         (when (import-context-reconciliation-table ,ctx)
           (persist-reconciliation (import-context-reconciliation-table ,ctx))
           (close-reconciliation (import-context-reconciliation-table ,ctx)))
         (when (import-context-parser-stream ,ctx)
           (close (import-context-parser-stream ,ctx))))))

;;; ---------------------------------------------------------------------------
;;; Import API
;;; ---------------------------------------------------------------------------

(defun import-graph (&key
                      (format (error "Required: :format"))
                      (source (error "Required: :source"))
                      (graph *graph*)
                      mapping
                      (conflict-policy :upsert)
                      (chunk-size 1000)
                      (resume-token nil)
                      (in-memory-reconciliation nil)
                      (location nil))
  "Import a graph from SOURCE in FORMAT.

FORMAT: keyword (e.g., :jsonl, :turtle, :csv, :parquet, :gml, :wikidata, :yago)
SOURCE: pathname, open stream, or :stdin
GRAPH: target graph (defaults to *graph*)
MAPPING: mapping spec (Lisp form, or pathname to .json/.yaml file)
CONFLICT-POLICY: :upsert (default), :skip, or :error
CHUNK-SIZE: number of records per transaction (default 1000)
RESUME-TOKEN: token from previous partial import, or NIL
IN-MEMORY-RECONCILIATION: use hash-table instead of on-disk lhash for small imports
LOCATION: on-disk store path for reconciliation lhash

Returns (values stats resume-token) where:
  stats = plist of :vertices-created, :vertices-updated, :edges-created, :edges-updated, :errors, :chunks-committed
  resume-token = token for resuming (or NIL if complete)"
  (unless (symbolp format)
    (warn "Format ~A should be a keyword (e.g., :jsonl, :turtle)" format))
  (let ((fmt (find-format (if (symbolp format) (make-keyword (symbol-name format)) format))))
    (unless (format-spec-import-parser fmt)
      (error "Format ~A does not support import" format))
    (with-import-stream (source (if (symbolp format)
                                    (make-keyword (symbol-name format))
                                    format)
                                mapping graph
                                :conflict-policy conflict-policy
                                :chunk-size chunk-size
                                :resume-token resume-token
                                :in-memory-reconciliation in-memory-reconciliation
                                :location location)
      (loop
        (let ((result (process-next-record *import-context*)))
          (when (eq result :eof) (return))
          (when (>= (length (import-context-chunk-buffer *import-context*)) chunk-size)
            (flush-chunk *import-context*)))
        (when (import-context-chunk-buffer *import-context*)
          (flush-chunk *import-context*))
        (values (import-context-stats *import-context*)
                (make-resume-token *import-context*))))))

;;; ---------------------------------------------------------------------------
;;; Resume token helpers
;;; ---------------------------------------------------------------------------

(defun make-resume-token (context)
  "Create a resume token from CONTEXT: (file-position . (last-vertex-id last-edge-id))."
  (when (and (import-context-last-vertex-id context)
             (import-context-last-edge-id context)
             (> (import-context-file-position context) 0))
    (cons (import-context-file-position context)
          (cons (import-context-last-vertex-id context)
                (import-context-last-edge-id context)))))

(defun write-resume-token (token source-path)
  "Write resume TOKEN to JSON sidecar file: <source-path>.vg-import-token.json"
  (when (and token source-path (pathnamep source-path))
    (let ((token-file (make-pathname
                       :name (format nil "~A.vg-import-token" (pathname-name source-path))
                       :type "json"
                       :defaults source-path)))
      (with-open-file (out token-file :direction :output :if-exists :supersede)
        (cl-json:encode-json
         (list :file-position (car token)
               :last-vertex-id (uuid-array->string (caadr token))
               :last-edge-id (uuid-array->string (cdadr token)))
         out))))

(defun read-resume-token (source-path)
  "Read resume token from JSON sidecar, or return NIL."
  (when (pathnamep source-path)
    (let ((token-file (make-pathname
                       :name (format nil "~A.vg-import-token" (pathname-name source-path))
                       :type "json"
                       :defaults source-path)))
      (when (probe-file token-file)
        (with-open-file (in token-file :direction :input)
          (let ((data (cl-json:decode-json in)))
            (when data
              (cons (getf data :file-position)
                    (cons (string->uuid-array (getf data :last-vertex-id))
                          (string->uuid-array (getf data :last-edge-id))))))))))

;;; ---------------------------------------------------------------------------
;; Export API
;;; ---------------------------------------------------------------------------

(defun export-graph (&key
                      (format (error "Required: :format"))
                      (target (error "Required: :target"))
                      (graph *graph*)
                      mapping
                      (vertex-types '(graph-db:vertex))
                      (edge-types '(graph-db:edge))
                      (include-geometry t)
                      (location nil))
  "Export GRAPH to TARGET in FORMAT.

FORMAT: keyword (e.g., :jsonl, :turtle, :csv)
TARGET: pathname, open stream, or :stdout
GRAPH: source graph (defaults to *graph*)
MAPPING: optional reverse mapping spec
VERTEX-TYPES: list of vertex type symbols to export (default: all)
EDGE-TYPES: list of edge type symbols to export (default: all)
INCLUDE-GEOMETRY: if true, include spatial/geometry slot values
LOCATION: unused for export

Returns stats plist."
  (declare (ignore mapping location))
  (let ((fmt (find-format (if (symbolp format)
                              (make-keyword (symbol-name format))
                              format))))
    (unless (format-spec-export-serializer fmt)
      (error "Format ~A does not support export" format))
    (funcall (format-spec-export-serializer fmt) target
             graph vertex-types edge-types include-geometry)))

;;; ---------------------------------------------------------------------------
;; Stats accessors
;;; ---------------------------------------------------------------------------

(defun import-stats (context)
  "Return stats plist from import CONTEXT."
  (import-context-stats context))

(defun incf-import-stat (context key &optional (delta 1))
  "Increment a stat counter in the import CONTEXT."
  (let ((stats (import-context-stats context)))
    (setf (getf stats key) (+ (getf stats key 0) delta))))

(defun set-import-stat (context key value)
  "Set a stat counter in the import CONTEXT."
  (let ((stats (import-context-stats context)))
    (setf (getf stats key) value)))