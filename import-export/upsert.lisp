;;;; graph-db/import-export/upsert.lisp
;;;; Upsert logic with reconciliation support

(in-package :graph-db.import-export)

;;; ---------------------------------------------------------------------------
;;; Upsert vertex
;;; ---------------------------------------------------------------------------

(defun upsert-vertex (graph type-id slot-data source-id conflict-policy)
  "Upsert a vertex into GRAPH.
GRAPH: graph instance
TYPE-ID: vertex type (e.g., :person)
SLOT-DATA: plist of slot values to set
SOURCE-ID: string identifier for the source
CONFLICT-POLICY: :upsert (default, update existing), :skip (keep existing), :error (signal on conflict)

Returns the created/updated vertex and a boolean indicating if it was new.
Uses reconciliation table to map source-id to VG-UUID."
  (let ((table (get-reconciliation-table graph))
        (slot-data (coerce-slot-data slot-data))
        (source-id (or source-id (error "source-id is required")))
        (conflict-policy (or conflict-policy :upsert)))
    ;; Look up or generate VG-UUID
    (multiple-value-bind (vg-uuid was-new)
        (reconcile-id table source-id)
      (when was-new
        ;; Create new vertex with given source-id
        (make-vertex type-id slot-data :id vg-uuid :graph graph)
        (return-from upsert-vertex (list (make-vertex type-id slot-data :id vg-uuid :graph graph) t)))))

;;; ---------------------------------------------------------------------------
;;; Upsert edge
;;; ---------------------------------------------------------------------------

(defun upsert-edge (graph type-id from-source-id to-source-id weight slot-data source-id conflict-policy)
  "Upsert an edge into GRAPH.
GRAPH: graph instance
TYPE-ID: edge type (e.g., :likes)
FROM-SOURCE-ID: source identifier for start vertex
TO-SOURCE-ID: source identifier for end vertex
WEIGHT: numeric edge weight
SLOT-DATA: plist of slot values to set
SOURCE-ID: source identifier
CONFLICT-POLICY: :upsert (default), :skip (keep existing), :error (signal on conflict)

Returns the created/updated edge and a boolean indicating if it was new."
  (let ((table (get-reconciliation-table graph)))
    ;; Resolve both endpoints
    (multiple-value-bind (from-uuid was-new-from)
        (reconcile-id table from-source-id)
      (multiple-value-bind (to-uuid was-new-to)
          (reconcile-id table to-source-id)
        ;; Create the edge
        (make-edge type-id from-uuid to-uuid weight slot-data :graph graph)
        (list (make-edge type-id from-uuid to-uuid weight slot-data :graph graph) t)))))

;;; ---------------------------------------------------------------------------
;;; Helper: coerce slot data
;;; ---------------------------------------------------------------------------

(defun coerce-slot-data (data)
  "Coerce slot-data values using built-in coercions.
Coerces each slot value via the coercion registry.
Returns the coerced plist."
  (unless (listp data) (return-from coerce-slot-data nil))
  (mapcar (lambda (slot)
            (let ((coercion-type (getf slot :coerce)))
              (if coercion-type
                  (coerce-value coercion-type (getf slot :value))
                  (getf slot :value))))
          data))