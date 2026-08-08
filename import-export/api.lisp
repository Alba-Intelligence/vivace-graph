;;;; graph-db/import-export/api.lisp
;;;; Public API: import-graph / export-graph

(in-package :graph-db.import-export)

;;; ---------------------------------------------------------------------------
;;; UUID string/array conversion helpers (using graph-db's string-id + uuid package)
;;; ---------------------------------------------------------------------------

(defun uuid-array->string (uuid-array)
  "Convert a 16-byte UUID array to standard UUID string."
  (graph-db:string-id uuid-array))

(defun string->uuid-array (uuid-string)
  "Convert a standard UUID string to 16-byte array."
  (let ((uuid (uuid:make-uuid-from-string uuid-string)))
    (uuid:uuid-to-byte-array uuid)))

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
                        (in-memory-reconciliation nil))
  "Import a graph from SOURCE in FORMAT.

FORMAT: keyword (e.g., :jsonl, :csv, :parquet, :gml, :wikidata, :yago)
SOURCE: pathname, open stream, or :stdin
GRAPH: target graph (defaults to *graph*)
MAPPING: mapping spec (Lisp form, or pathname to .json/.yaml file)
CONFLICT-POLICY: :upset (default), :skip, or :error
CHUNK-SIZE: number of records per transaction (default 1000)
RESUME-TOKEN: token from previous partial import, or NIL
IN-MEMORY-RECONCILIATION: use hash-table instead of on-disk lhash for small imports

Returns (values stats resume-token) where:
  stats = plist of :vertices-created, :vertices-updated, :edges-created, :edges-updated, :errors, :chunks-committed
  resume-token = token for resuming (or NIL if complete)"
  (let ((fmt (find-format format)))
    (unless (format-import-parser fmt)
      (error "Format ~A does not support import" format))
    (let ((mapping-spec (cond
                          ((null mapping) nil)
                          ((pathnamep mapping) (load-mapping-file mapping))
                          (t (parse-mapping-spec mapping)))))
      (with-import-stream (source fmt mapping-spec graph
                              :conflict-policy conflict-policy
                              :chunk-size chunk-size
                              :resume-token resume-token
                              :in-memory-reconciliation in-memory-reconciliation)
        (loop
          (let ((result (process-next-record *import-context*)))
            (when (eq result :eof) (return))
          (when (>= (length (import-context-chunk-buffer *import-context*)) chunk-size)
            (flush-chunk *import-context*)))
        (when (import-context-chunk-buffer *import-context*)
          (flush-chunk *import-context*))
        (values (import-stats *import-context*)
                (make-resume-token *import-context*))))))

;;; ---------------------------------------------------------------------------
;;; Import context (for streaming coordinator)
;;; ---------------------------------------------------------------------------

(defstruct import-context
  (format nil :type format)
  (parser nil :type function)
  (graph nil :type t)
  (mapping nil :type (or null list))
  (reconciliation-table nil :type (or null t))
  (chunk-buffer nil :type list)           ; list of constructor arg plists
  (conflict-policy :upset :type keyword)
  (chunk-size 1000 :type integer)
  (resume-token nil :type (or null cons))
  (in-memory-reconciliation nil :type boolean)
  (stats (list :vertices-created 0 :vertices-updated 0
               :edges-created 0 :edges-updated 0
               :errors 0 :chunks-committed 0) :type list)
  (file-position 0 :type integer)
  (last-vertex-id nil :type (or null simple-array))
  (last-edge-id nil :type (or null simple-array)))

(defvar *import-context* nil
  "Dynamically bound during import; holds streaming state.")

(defmacro with-import-stream ((source format mapping-spec graph &rest opts) &body body)
  "Open SOURCE with FORMAT parser, bind *import-context*, execute BODY.
OPTS: :conflict-policy, :chunk-size, :resume-token, :in-memory-reconciliation"
  (with-gensyms (ctx parser stream)
    `(let* ((,fmt (find-format ,format))
            (,parser (funcall (format-import-parser ,fmt) ,source))
            (,ctx (make-import-streaming-context
                   :source ,source
                   :parser ,parser
                   :graph ,graph
                   :mapping ,mapping-spec
                   :reconciliation-table (make-reconciliation-table ,graph
                                                      :location (getf opts :location)
                                                      :in-memory ,(getf opts :in-memory-reconciliation))
                   :conflict-policy (or ,(getf opts :conflict-policy) :upset)
                   :chunk-size (or ,(getf opts :chunk-size) 1000)
                   :resume-token ,(getf opts :resume-token)
                   :in-memory-reconciliation ,(getf opts :in-memory-reconciliation)))
       (unwind-protect
            (progn ,@body)
         (when (import-streaming-context-reconciliation-table ,ctx)
           (persist-reconciliation (import-streaming-context-reconciliation-table ,ctx))
           (close-reconciliation (import-streaming-context-reconciliation-table ,ctx)))
         (when (and (import-streaming-context-parser ,ctx)
                    (typep (import-streaming-context-parser ,ctx) 'function))
           (close (import-streaming-context-parser ,ctx)))))))

;;; ---------------------------------------------------------------------------
;;; Resume token helpers
;;; ---------------------------------------------------------------------------

(defun make-resume-token (context)
  "Create a resume token from CONTEXT: (file-position . (last-vertex-id last-edge-id))."
  (when (and (import-streaming-context-last-vertex-id context)
             (import-streaming-context-last-edge-id context)
             (import-streaming-context-file-position context))
    (cons (import-streaming-context-file-position context)
          (cons (import-streaming-context-last-vertex-id context)
                (import-streaming-context-last-edge-id context)))))

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
;;; Stats accessor
;;; ---------------------------------------------------------------------------

(defun import-stats (context)
  "Return stats plist from CONTEXT."
  (import-context-stats context))

(defun incf-import-stat (context key &optional (delta 1))
  (let ((stats (import-context-stats context)))
    (setf (getf stats key) (+ (getf stats key 0) delta))))

(defun set-import-stat (context key value)
  (let ((stats (import-context-stats context)))
    (setf (getf stats key) value)))