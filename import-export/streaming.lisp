;;;; graph-db/import-export/streaming.lisp
;;;; Streaming import coordinator with chunked transactions.

(in-package :graph-db.import.export)

;;; ---------------------------------------------------------------------------
;;; Streaming context structure
;;; ---------------------------------------------------------------------------

(defstruct (import-streaming-context
            (:constructor make-import-streaming-context (source parser graph mapping opts)))
  (source nil :type (or pathname stream null))
  (parser nil :type function)           ; iterator function
  (graph nil :type t)
  (mapping nil :type (or null list))
  (opts nil :type list)
  (reconciliation-table nil :type (or null t))
  (chunk-buffer nil :type list)         ; buffer for current chunk
  (chunk-size 1000 :type fixnum)
  (conflict-policy :upsert :type keyword)
  (resume-token nil :type (or null cons))
  (stats (list :vertices-created 0 :vertices-updated 0
               :edges-created 0 :edges-updated 0
               :errors 0 :chunks-committed 0) :type list)
  (file-position 0 :type (or null integer))
  (last-vertex-id nil :type (or null simple-array))
  (last-edge-id nil :type (or null simple-array))
  (in-memory-reconciliation nil :type boolean))

;;; ---------------------------------------------------------------------------
;;; Streaming process helpers
;;; ---------------------------------------------------------------------------

(defun process-next-record (context)
  "Process next record from parser. Returns :eof or record plist.
Updates CONTEXT's chunk buffer and returns the record."
  (let ((parser (import-streaming-context-parser context)))
    (let ((record (funcall parser)))
      (if (eq record :eof)
          record
          (progn
            (push record (import-streaming-context-chunk-buffer context))
            record)))))

(defun flush-chunk (context)
  "Flush chunk buffer in a transaction.
Commits all buffered records atomically, updates stats, resets buffer."
  (let ((buffer (import-streaming-context-chunk-buffer context)))
    (when buffer
      (with-transaction ()
        (dolist (record (nreverse buffer))  ; buffer is LIFO
          (handler-case
              (apply-record-to-graph context record)
            (error (e)
              (incf (getf (import-streaming-context-stats context) :errors) 1)
              (format *error-output* "Error processing record: ~A~%" e)))))
      ;; Update chunk stats
      (incf (getf (import-streaming-context-stats context) :chunks-committed 1))
      (setf (import-streaming-context-chunk-buffer context) nil))))

(defun apply-record-to-graph (context record)
  "Apply a single record to the graph using upsert logic."
  (declare (ignore context))
  ;; Stub implementation - actual logic in import-graph
  (values))

;;; ---------------------------------------------------------------------------
;;; Memory budget enforcement
;;; ---------------------------------------------------------------------------

(defun check-memory-budget (context)
  "Check if we're within the 500MB memory budget.
Returns T if within budget, signals warning if exceeded."
  (let ((current-bytes (room-bytes))
        (limit-bytes (* 500 1024 1024)))  ; 500MB
    (when (> current-bytes limit-bytes)
      (warn "Memory budget exceeded: ~A MB (limit: 500 MB)"
            (/ current-bytes 1024 1024)))))

(defun room-bytes ()
  "Return current heap usage in bytes.
Implementation depends on Lisp."
  #+sbcl (sb-ext:get-bytes-consed)
  #+ecl (ext:room-bytes)
  #- (error "Memory monitoring not implemented for this Lisp implementation"))

;;; ---------------------------------------------------------------------------
;;; Resume token management
;;; ---------------------------------------------------------------------------

(defun make-resume-token (context)
  "Create a resume token from CONTEXT: (file-position . (last-vertex-id last-edge-id))."
  (when (and (import-streaming-context-last-vertex-id context)
             (import-streaming-context-last-edge-id context)
             (import-streaming-context-file-position context))
    (cons (import-streaming-context-file-position context)
          (cons (import-streaming-context-last-vertex-id context)
                (import-streaming-context-last-edge-id context)))))

(defun write-resume-token (token path)
  "Write resume TOKEN to JSON sidecar file."
  (when (and token path (pathnamep path))
    (let ((token-file (make-pathname
                       :name (format nil "~A.vg-import-token" (pathname-name path))
                       :type "json"
                       :defaults path)))
      (ensure-directories-exist token-file)
      (with-open-file (out token-file :direction :output :if-exists :supersede)
        (cl-json:encode-json
         (list :file-position (car token)
               :last-vertex-id (uuid-array->string (caadr token))
               :last-edge-id (uuid-array->string (cdadr token)))
         out)))))

(defun read-resume-token (path)
  "Read resume token from JSON sidecar, or return NIL."
  (when (and path (pathnamep path))
    (let ((token-file (make-pathname
                       :name (format nil "~A.vg-import-token" (pathname-name path))
                       :type "json"
                       :defaults path)))
      (when (probe-file token-file)
        (with-open-file (in token-file :direction :input)
          (let ((data (cl-json:decode-json in)))
            (when data
              (cons (getf data :file-position)
                    (cons (string->uuid-array (getf data :last-vertex-id))
                          (string->uuid-array (getf data :last-edge-id)))))))))))

;;; ---------------------------------------------------------------------------
;;; UUID helpers (moved from api.lisp for use here)
;;; ---------------------------------------------------------------------------

(defun uuid-array->string (uuid-array)
  (graph-db:string-id uuid-array))

(defun string->uuid-array (uuid-string)
  (let ((uuid (uuid:make-uuid-from-string uuid-string)))
    (uuid:uuid-to-byte-array uuid)))