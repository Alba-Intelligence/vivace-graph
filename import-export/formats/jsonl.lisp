;;;; graph-db/import-export/formats/jsonl.lisp
;;;; JSONL format implementation

(in-package :graph-db.import-export)

;;; ---------------------------------------------------------------------------
;;; JSONL Parser (import)
;;; ---------------------------------------------------------------------------

(defun make-jsonl-parser (source)
  "Create a JSONL parser iterator for SOURCE.
SOURCE: pathname, stream, or :stdin
Returns a function that returns next record (plist) or :eof."
  (let ((stream (ensure-jsonl-stream source)))
    (lambda ()
      (let ((line (read-line stream nil nil)))
        (if (null line)
            (progn
              (close stream)
              :eof)
            (cl-json:decode-json-from-string line))))))

(defun ensure-jsonl-stream (source)
  "Open SOURCE as a stream for JSONL reading."
  (cond
    ((eq source :stdin) *standard-input*)
    ((stringp source) (open source :direction :input))
    ((pathnamep source) (open source :direction :input))
    ((streamp source) source)
    (t (error "Cannot create JSONL stream from ~S" source))))

;;; ---------------------------------------------------------------------------
;;; JSONL Serializer (export)
;;; ---------------------------------------------------------------------------

(defun make-jsonl-serializer (target)
  "Create a JSONL serializer for TARGET.
TARGET: pathname, stream, or :stdout
Returns a function (plist) that writes one JSONL line."
  (let ((stream (ensure-jsonl-output-stream target)))
    (lambda (record-plist)
      (cl-json:encode-json-to-string record-plist)
      (terpri stream))))

(defun ensure-jsonl-output-stream (target)
  "Open TARGET as an output stream for JSONL writing."
  (cond
    ((eq target :stdout) *standard-output*)
    ((stringp target) (open target :direction :output :if-exists :supersede :if-exists :create))
    ((pathnamep target) (open target :direction :output :if-exists :supersede :if-exists :create))
    ((streamp target) target)
    (t (error "Cannot create JSONL output stream from ~S" target))))

;;; ---------------------------------------------------------------------------
;;; Import format method
;;; ---------------------------------------------------------------------------

(defmethod import-format ((fmt format) (source (eql :jsonl)) graph mapping opts)
  "Import from JSONL source into GRAPH per MAPPING."
  (let* ((conflict-policy (getf opts :conflict-policy :upsert))
         (chunk-size (or (getf opts :chunk-size) 1000))
         (resume-token (getf opts :resume-token))
         (streaming (if (consp source)
                        (first source)
                        source))
         (parser (make-jsonl-parser streaming))
         (table (make-reconciliation-table graph
                      :location (getf opts :location)
                      :in-memory (getf opts :in-memory-reconciliation)))
         (stats (list :vertices-created 0 :vertices-updated 0
                      :edges-created 0 :edges-updated 0
                      :errors 0 :chunks-committed 0))
         (chunk-buffer '()))
    ;; Apply resume token if present
    (when resume-token
      (let ((pos (car resume-token)))
        (when pos
          (file-position parser pos))))
    ;; Process records
    (loop
      (let ((record (funcall parser)))
        (if (eq record :eof)
            (return)
            (progn
              (push record chunk-buffer)
              (when (>= (length chunk-buffer) chunk-size)
                (flush-chunk-to-graph chunk-buffer table graph mapping conflict-policy stats)
                (setf chunk-buffer '()))))))
    ;; Flush remaining records
    (when chunk-buffer
      (flush-chunk-to-graph chunk-buffer table graph mapping conflict-policy stats))
    (values stats resume-token)))

;;; ---------------------------------------------------------------------------
;;; Export format method
;;; ---------------------------------------------------------------------------

(defmethod export-format ((fmt format) (target (eql :jsonl)) graph mapping opts)
  "Export GRAPH to JSONL TARGET per MAPPING."
  (let* ((serializer (make-jsonl-serializer target))
         (vertex-types (getf opts :vertex-types))
         (edge-types (getf opts :edge-types))
         (include-geometry (getf opts :include-geometry t))
         (vertex-count 0)
         (edge-count 0))
    ;; Export vertices
    (graph-db:map-vertices (graph)
      (lambda (vertex)
        (when (or (null vertex-types)
                  (member (vertex-type-id vertex) vertex-types))
          (let ((plist (vertex->plist vertex mapping)))
            (when (not include-geometry)
              (remf plist :location))
            (funcall serializer plist))
          (incf vertex-count))))
    ;; Export edges
    (graph-db:map-edges (graph)
      (lambda (edge)
        (when (or (null edge-types)
                  (member (edge-type-id edge) edge-types))
          (let ((plist (edge->plist edge mapping)))
            (when (not include-geometry)
              (remf plist :location))
            (funcall serializer plist))
          (incf edge-count))))
    (list :vertices-exported vertex-count :edges-exported edge-count)))

;;; ---------------------------------------------------------------------------
;;; Helpers
;;; ---------------------------------------------------------------------------

(defun flush-chunk-to-graph (records table graph mapping conflict-policy stats)
  "Apply RECORDS chunk to graph in a transaction."
  (graph-db:with-transaction ()
    (dolist (record records)
      (handler-case
          (let ((type (getf record :type)))
            (if (eq type :edge)
                (apply-edge-record record table graph mapping conflict-policy stats)
                (apply-vertex-record record table graph mapping conflict-policy stats)))
        (error (e)
          (incf (getf stats :errors) 1)
          (format *error-output* "Error importing record: ~A~%" e)))))
  (incf (getf stats :chunks-committed) 1))

(defun apply-vertex-record (record table graph mapping conflict-policy stats)
  (let* ((source-id (getf record :id))
         (type-id (getf record :type-id))
         (slot-data (remove-from-plist record '(:id :type :type-id))))
    (multiple-value-bind (vertex was-new)
        (upsert-vertex graph type-id slot-data source-id conflict-policy)
      (if was-new
          (incf (getf stats :vertices-created) 1)
          (incf (getf stats :vertices-updated) 1)))))

(defun apply-edge-record (record table graph mapping conflict-policy stats)
  (let* ((source-id (getf record :id))
         (type-id (getf record :type-id))
         (from-id (getf record :from))
         (to-id (getf record :to))
         (weight (getf record :weight 1.0))
         (slot-data (remove-from-plist record '(:id :type :type-id :from :to :weight))))
    (multiple-value-bind (edge was-new)
        (upsert-edge graph type-id from-id to-id weight slot-data source-id conflict-policy)
      (if was-new
          (incf (getf stats :edges-created) 1)
          (incf (getf stats :edges-updated) 1)))))

;; Register JSONL format
(register-format :jsonl
  :import-parser #'make-jsonl-parser
  :export-serializer #'make-jsonl-serializer  ; Note: export uses method-based export-format
  :streaming-p t
  :supports-export-p t)