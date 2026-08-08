;;;; graph-db/import-export/geometry-map.lisp
;;;; Geometry coercion and mapping.

(in-package :graph-db.import-export)

;;; ---------------------------------------------------------------------------
;;; Geometry coercion (handles :geometry coercion with format spec)
;;; ---------------------------------------------------------------------------

(register-coercion :geometry
  (lambda (raw-value)
    "Coerce RAW-VALUE to geometry object.
RAW-VALUE can be:
  - plist with :lat/:lon (Point) or :wkt/:geojson
  - string (WKT or GeoJSON)
  - Already a geometry object
Delegates to MAP-GEOMETRY with auto-detected format."
    (map-geometry raw-value :auto)))

(defun map-geometry (raw-value &optional (format-spec :auto))
  "Map RAW-VALUE to a geometry object.
FORMAT-SPEC: :auto | :latlon | :wkt | :geojson | plist with :format key
Returns geometry object (Point, Polygon, etc.) via make-point/make-polygon.

Supported input formats:
  :latlon / :lat-lon — plist with :lat and :lon (or :latitude/:longitude) as numbers/strings
  :wkt — string in Well-Known Text format (POINT only without GEOS)
  :geojson — plist/alist with :type and :coordinates (GeoJSON)
  :auto — auto-detect from RAW-VALUE structure"
  (let ((fmt (if (and (keywordp format-spec) (not (eq format-spec :auto)))
                 format-spec
                 (detect-geometry-format raw-value format-spec))))
    (case fmt
      (:latlon (map-geometry-latlon raw-value))
      (:wkt (map-geometry-wkt raw-value))
      (:geojson (map-geometry-geojson raw-value))
      (t (error "Unknown geometry format: ~S" fmt)))))

(defun detect-geometry-format (raw-value &optional format-spec)
  "Auto-detect geometry format from RAW-VALUE."
  (cond
    ((and (keywordp format-spec) (member format-spec '(:latlon :wkt :geojson))) format-spec)
    ((and (plistp raw-value) (or (getf raw-value :lat) (getf raw-value :latitude))) :latlon)
    ((and (plistp raw-value) (getf raw-value :wkt)) :wkt)
    ((and (plistp raw-value) (getf raw-value :geojson)) :geojson)
    ((and (consp raw-value) (eq (car raw-value) :type) (getf (cdr raw-value) :coordinates)) :geojson)
    ((stringp raw-value)
     (if (cl-ppcre:scan "^POINT\\s*\\(?\\s*([-+]?\\d*\\.?\\d+)\\s+([-+]?\\d*\\.?\\d+)\\s*\\)?$" raw-value)
         :wkt
         :geojson))  ; assume GeoJSON if not WKT POINT
    (t :latlon)))  ; default fallback

(defun map-geometry-latlon (raw-value)
  "Map :latlon format (plist with :lat/:lon) to Point geometry."
  (let* ((lat (or (getf raw-value :lat) (getf raw-value :latitude)))
         (lon (or (getf raw-value :lon) (getf raw-value :longitude))))
    (when (or (null lat) (null lon))
      (error "Lat/lon format requires :lat and :lon keys, got ~S" raw-value))
    (graph-db:make-point (coerce-value :float lon) (coerce-value :float lat))))

(defun map-geometry-wkt (raw-value)
  "Map WKT string to geometry. Supports POINT (no GEOS required). Other types require GEOS."
  (cond ((typep raw-value 'geometry) raw-value)
        ((stringp raw-value)
         (let* ((wkt (string-trim '(#\Space #\Tab #\Newline #\Return) raw-value))
                (coords (cl-ppcre:scan "([-+]?\\d*\\.?\\d+)\\s+([-+]?\\d*\\.?\\d+)" wkt)))
           (when coords
             (graph-db:make-point (parse-number:parse-number (first coords))
                                  (parse-number:parse-number (second coords)))
             ;; For other WKT types, return a marker
             (unless (cl-ppcre:scan "^POINT\\s*\\(?\\s*([-+]?\\d*\\.?\\d+)\\s+([-+]?\\d*\\.?\\d+)\\s*\\)?$" wkt)
               (error "WKT type not supported (need GEOS): ~S" wkt)))))
        (t (error "WKT format requires string, got ~S" raw-value))))

(defun map-geometry-geojson (raw-value)
  "Map GeoJSON (plist/alist with :type :coordinates) to geometry."
  (cond ((typep raw-value 'geometry) raw-value)
        ((and (consp raw-value) (eq (car raw-value) :type))
         ;; GeoJSON as plist: (:type "Point" :coordinates (lon lat))
         (let ((type (getf (cdr raw-value) :type))
               (coords (getf (cdr raw-value) :coordinates)))
           (ecase (string-upcase (format nil "~A" type))
             ("POINT" (graph-db:make-point (coerce-value :float (second coords))
                                           (coerce-value :float (first coords))))
             ("POLYGON" (if (listp coords)
                            (apply #'graph-db:make-polygon coords)
                            (error "Invalid POLYGON coordinates: ~S" coords)))
             ("LINESTRING" (graph-db:make-linestring coords))
             (t (error "Unsupported GeoJSON type: ~S" type)))))
        ((and (plistp raw-value) (getf raw-value :geojson))
         (map-geometry-geojson (getf raw-value :geojson)))
        (t (error "GeoJSON format requires :type and :coordinates, got ~S" raw-value))))