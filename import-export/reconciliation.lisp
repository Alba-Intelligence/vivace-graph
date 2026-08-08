;;;; graph-db/import-export/reconciliation.lisp
;;;; Reconciliation table (source-id ↔ VG-UUID mapping)

(in-package :graph-db.import-export)

;;; ---------------------------------------------------------------------------
;;; Reconciliation table definition
;;; ---------------------------------------------------------------------------

(defstruct (reconciliation-table (:constructor make-reconciliation-table (location in-memory)))
  (table nil :type hash-table)       ; actual lhash or hash-table
  (location nil :type keyword)       ; :on-disk or :in-memory
  (in-memory nil :type boolean))     ; true if using in-memory hash-table

(defun make-reconciliation-table (graph &key location in-memory)
  "Create or open reconciliation table for GRAPH.
LOCATION: keyword (:on-disk, :on-disk-in-memory, :in-memory)
IN-MEMORY: boolean (only for :in-memory location)
Returns reconciliation table structure with underlying table and metadata."
  (let ((location (or location :on-disk))  ; default to on-disk if not specified)
        (in-memory (or in-memory (if (keywordp location)
                                   (case location
                                     (:on-disk-in-memory nil)
                                     (case location
                                       (:on-disk-in-memory t)
                                       (:on-disk nil)
                                       (t nil))
                                   nil)))))
    (let ((table (if in-memory
                     (make-hash-table :test 'equal)
                     (lhash:make-lhash :key-test 'string= 
                                         :value-size 16  ; 16-byte UUID
                                         :bucket-count 8  ; power of 2
                                         :max-buckets 1024)))  ; enough for 100K+ IDs
            (table-struct (make-reconciliation-table location in-memory)))
      (setf (reconciliation-table-table table) table)
      (setf (reconciliation-table-location table) location)
      (setf (reconciliation-table-in-memory table) in-memory)
      table)))

(defun reconcile-id (table source-id)
  "Resolve source-id to VG-UUID. Returns (values uuid created-p)."
  (let ((table (reconciliation-table-table table))
        (created nil))
    (if (gethash source-id table)
        (values (gethash source-id table) nil)
        (let ((new-id (graph-db:gen-vertex-id)))
          (setf (gethash source-id table) new-id)
          (setf created t)
          (values new-id t)))))

(defun lookup-reconciliation (table source-id)
  "Look up source-id in TABLE. Returns UUID or NIL."
  (gethash source-id (reconciliation-table-table table)))

;;; ---------------------------------------------------------------------------
;;; Persistence and lifecycle
;;; ---------------------------------------------------------------------------

(defun persist-reconciliation (table)
  "Persist reconciliation table to disk. No-op for in-memory tables."
  (let ((table (reconciliation-table-table table)))
    (when (not (reconciliation-table-in-memory table))
      (lhash:save (reconciliation-table-table table)
                  (format nil "~A/import-id-map" (reconciliation-table-location table))))))

(defun close-reconciliation (table)
  "Close reconciliation table. No-op for in-memory tables."
  (let ((table (reconciliation-table-table table)))
    (when (not (reconciliation-table-in-memory table))
      (lhash:close (reconciliation-table-table table)))))

(defun get-reconciliation-table (graph)
  "Get reconciliation table for GRAPH. Creates new table if none exists."
  (let ((graph-dir (graph-db:graph-directory graph)))
    (make-reconciliation-table graph :location :on-disk)))

(defun get-reconciliation-table-in-memory (graph)
  "Get in-memory reconciliation table for GRAPH (small imports only)."
  (let ((graph-dir (graph-db:graph-directory graph)))
    (make-reconciliation-table graph :location :on-disk-in-memory :in-memory t)))