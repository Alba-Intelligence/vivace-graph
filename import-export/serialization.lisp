;;;; graph-db/import-export/serialization.lisp
;;;; Vertex/edge to plist serialization helpers.

(in-package :graph-db/import-export)

;;; ---------------------------------------------------------------------------
;;; Vertex serialization
;;; ---------------------------------------------------------------------------

(defun vertex->plist (vertex &optional mapping)
  "Convert VERTEX to plist for export.
VERTEX: graph-db vertex instance
MAPPING: optional export mapping spec to control output
Returns plist with :id, :type, and all slot values."
  (let ((plist (list :id (vertex-id vertex)
                     :type (vertex-type-id vertex))))
    ;; Add all slot values
    (dolist (slot (vertex-slots vertex))
      (let ((value (slot-value vertex slot)))
        (push slot plist)
        (push value plist)))
    (nreverse plist)))

(defun vertex-slot-value (vertex slot-name)
  "Get slot value from vertex, handling geometry and other special types."
  (let ((value (slot-value vertex slot-name)))
    (cond
      ((typep value 'geometry) (geometry-to-plist value))
      (t value))))

;;; ---------------------------------------------------------------------------
;;; Edge serialization
;;; ---------------------------------------------------------------------------

(defun edge->plist (edge &optional mapping)
  "Convert EDGE to plist for export.
EDGE: graph-db edge instance
MAPPING: optional export mapping spec to control output
Returns plist with :id, :type, :from, :to, :weight, and all slot values."
  (let ((plist (list :id (edge-id edge)
                     :type (edge-type-id edge)
                     :from (edge-from edge)
                     :to (edge-to edge)
                     :weight (edge-weight edge))))
    (dolist (slot (edge-slots edge))
      (let ((value (slot-value edge slot)))
        (push slot plist)
        (push value plist)))
    (nreverse plist)))

;;; ---------------------------------------------------------------------------
;;; Geometry serialization
;;; ---------------------------------------------------------------------------

(defun geometry-to-plist (geometry)
  "Convert geometry to plist with :lat, :lon for points, or :wkt for complex."
  (ecase (geometry-kind geometry)
    (:point (list :lat (geometry-lat geometry)
                  :lon (geometry-lon geometry)))
    (:linestring (list :wkt (geometry->wkt geometry)))
    (:polygon (list :wkt (geometry->wkt geometry)))
    (:multipolygon (list :wkt (geometry->wkt geometry)))))

(defun geometry->wkt (geometry)
  "Convert geometry to WKT string."
  ;; This would use the geometry's serialization
  (error "geometry->wkt not yet implemented"))

;;; ---------------------------------------------------------------------------
;;; Plist to constructor args
;;; ---------------------------------------------------------------------------

(defun plist->vertex-args (plist mapping)
  "Convert plist to vertex constructor args.
PLIST: plist from source record
MAPPING: import mapping spec for type coercion
Returns (values type-id slot-plist source-id)."
  (let ((type-id (getf plist :type))
        (source-id (getf plist :source-id)))
    (values type-id (remove-from-plist plist '(:type :source-id)) source-id)))

(defun plist->edge-args (plist mapping)
  "Convert plist to edge constructor args.
PLIST: plist from source record
MAPPING: import mapping spec for type coercion
Returns (values type-id from-source-id to-source-id weight slot-plist source-id)."
  (let ((type-id (getf plist :type))
        (from-source-id (getf plist :from))
        (to-source-id (getf plist :to))
        (weight (getf plist :weight))
        (source-id (getf plist :source-id)))
    (values type-id from-source-id to-source-id weight
            (remove-from-plist plist '(:type :from :to :weight :source-id))
            source-id)))

(defun remove-from-plist (plist keys)
  "Remove KEYS from PLIST."
  (loop for (k v) on plist by #'cddr
        unless (member k keys)
        append (list k v)))