;;;; graph-db/import-export/mapping.lisp
;;;; Mapping DSL parser, file loader, and validator.

(in-package :graph-db/import-export)

;;; ---------------------------------------------------------------------------
;;; Mapping spec representation
;;; ---------------------------------------------------------------------------

(defstruct (mapping-spec (:constructor make-mapping-spec (vertex-mappings edge-mappings)))
  (vertex-mappings nil :type list)   ; list of vertex-mapping structs
  (edge-mappings nil :type list))    ; list of edge-mapping structs

(defstruct (vertex-mapping (:constructor make-vertex-mapping (type slots)))
  (type nil :type t)                 ; vertex type symbol or name
  (slots nil :type list))            ; list of slot-mapping structs

(defstruct (edge-mapping (:constructor make-edge-mapping (type slots)))
  (type nil :type t)                 ; edge type symbol or name
  (slots nil :type list))            ; list of slot-mapping structs

(defstruct (slot-mapping (:constructor make-slot-mapping
                                           source-field target-slot
                                           &key coerce transform default required))
  (source-field nil :type (or string keyword))  ; column/field name in source
  (target-slot nil :type keyword)              ; slot name in vertex/edge
  (coerce nil :type keyword)                   ; coercion keyword (from registry)
  (transform nil :type function)               ; optional transform function
  (default nil :type t)                        ; default value if source missing
  (required nil :type boolean))                ; if T, error when source missing

;;; ---------------------------------------------------------------------------
;;; Parse mapping spec from Lisp form
;;; ---------------------------------------------------------------------------

(defun parse-mapping-spec (spec)
  "Parse mapping spec from Lisp form (plist/alist) per architecture DSL.
Returns normalized mapping-spec structure.

DSL:
  ((:vertex-type TYPE
    ((source-field :target-slot :coerce TYPE :transform FN :default VAL :required BOOL)
     ...))
   (:edge-type TYPE
    ((source-field :target-slot :coerce TYPE ...))
   ...))

Returns mapping-spec structure.
Signals error on invalid spec."
  (check-type spec list)
  (let ((vertex-mappings '())
        (edge-mappings '()))
    (dolist (clause spec)
      (ecase (car clause)
        (:vertex-type
         (destructuring-bind (&key type fields) (cdr clause)
           (push (make-vertex-mapping
                  :type type
                  :slots (parse-slot-mappings fields))
                 vertex-mappings)))
        (:edge-type
         (destructuring-bind (&key type fields) (cdr clause)
           (push (make-edge-mapping
                  :type type
                  :slots (parse-slot-mappings fields))
                 edge-mappings))))
    (make-mapping-spec
     :vertex-mappings (nreverse vertex-mappings)
     :edge-mappings (nreverse edge-mappings)))))

(defun parse-slot-mappings (slot-clauses)
  "Parse slot mapping clauses into slot-mapping structs."
  (mapcar (lambda (clause)
            (destructuring-bind (&key source-field target-slot coerce transform default required) clause
              (make-slot-mapping
               :source-field (cond ((stringp source-field) source-field)
                                   ((keywordp source-field) (symbol-name source-field))
                                   (t (error "source-field must be string or keyword: ~S" source-field)))
               :target-slot (ensure-keyword target-slot)
               :coerce (ensure-keyword coerce)
               :transform (or transform (lambda (x) x))  ; identity transform by default
               :default default
               :required (or required nil))))
          slot-clauses)))

;;; ---------------------------------------------------------------------------
;;; Load mapping from JSON/YAML file
;;; ---------------------------------------------------------------------------

(defun load-mapping-file (path)
  "Load mapping spec from JSON or YAML file.
PATH: pathname or string
Detects .json/.yaml/.yml extension, parses to same internal representation as parse-mapping-spec.
Returns mapping-spec structure."
  (let ((p (ensure-pathname path)))
    (cond
      ((member (pathname-type p) '("json" "JSON"))
       (parse-mapping-spec (load-json-mapping p)))
      ((member (pathname-type p) '("yaml" "yml" "YAML" "YML"))
       (parse-mapping-spec (load-yaml-mapping p)))
      (t (error "Unsupported mapping file extension: ~S. Use .json, .yaml, or .yml"
                (pathname-type p))))))

(defun ensure-pathname (path)
  "Ensure PATH is a pathname."
  (if (pathnamep path) path (pathname path)))

(defun load-json-mapping (path)
  "Load JSON mapping file and convert to DSL form."
  (with-open-file (in path :direction :input)
    (let ((data (cl-json:decode-json in)))
      (convert-json-to-dsl data))))

(defun load-yaml-mapping (path)
  "Load YAML mapping file and convert to DSL form."
  ;; Try to use yason or cl-yaml if available, otherwise signal not-implemented
  (error "YAML mapping not yet implemented - requires cl-yaml or yason dependency"))

(defun convert-json-to-dsl (json-data)
  "Convert parsed JSON mapping to Lisp DSL form."
  (check-type json-data list)
  (mapcar (lambda (clause)
            (destructuring-bind (&key type fields) clause
              `(,(ecase type
                   (:vertex :vertex-type)
                   (:edge :edge-type))
                :type ,(ensure-keyword type)
                :fields ,(convert-slot-fields fields))))
          json-data))

(defun convert-slot-fields (fields-data)
  "Convert JSON slot fields to Lisp form."
  (check-type fields-data list)
  (mapcar (lambda (field)
            (destructuring-bind (&key source-field target-slot coerce transform default required) field
              `(:source-field ,source-field
                :target-slot ,(ensure-keyword target-slot)
                :coerce ,(ensure-keyword coerce)
                :transform ,(when transform (read-from-string transform))
                :default ,default
                :required ,required)))
          fields-data)))

;;; ---------------------------------------------------------------------------
;;; Validate mapping spec against graph schema
;;; ---------------------------------------------------------------------------

(defun validate-mapping-spec (spec graph)
  "Validate SPEC against GRAPH schema.
Checks:
  - All vertex/edge types in spec exist in graph schema
  - All target slots exist on those types
  - Coercions are registered
Returns SPEC if valid, signals error otherwise."
  (check-type spec mapping-spec)
  (let ((vertex-types (get-vertex-types graph))
        (edge-types (get-edge-types graph)))
    (validate-type-mappings :vertex (mapping-spec-vertex-mappings spec) vertex-types graph)
    (validate-type-mappings :edge (mapping-spec-edge-mappings spec) edge-types graph))
  spec)

(defun validate-type-mappings (kind mappings valid-types graph)
  "Validate mappings of KIND (:vertex or :edge)."
  (dolist (mapping mappings)
    (let ((type (if (eq kind :vertex)
                    (vertex-mapping-type mapping)
                    (edge-mapping-type mapping))))
      (unless (member type valid-types :test #'eq)
        (error "~A type ~S not found in graph schema. Valid types: ~S"
               kind type valid-types))
      (validate-slot-mappings kind type (if (eq kind :vertex)
                                            (vertex-mapping-slots mapping)
                                            (edge-mapping-slots mapping))
                              graph))))

(defun validate-slot-mappings (kind type slots graph)
  "Validate slot mappings for TYPE."
  (let ((slots-info (get-type-slots kind type graph)))
    (dolist (slot slots)
      (let ((slot-name (slot-mapping-target-slot slot)))
        (unless (assoc slot-name slots-info :test #'eq)
          (error "Slot ~S not found on ~A type ~S. Valid slots: ~S"
                 slot-name kind type (mapcar #'car slots-info)))
        (unless (find-coercion (slot-mapping-coerce slot))
          (error "Unregistered coercion: ~S for slot ~S"
                 (slot-mapping-coerce slot) slot-name))))))

;;; ---------------------------------------------------------------------------
;;; Helper functions to access graph schema (using graph-db/introspect if available)
;;; ---------------------------------------------------------------------------

(defun get-vertex-types (graph)
  "Return list of vertex type symbols in GRAPH schema."
  (if (fboundp 'graph-db:list-vertex-types)
      (graph-db:list-vertex-types graph)
      (error "Graph introspection not available - need graph-db >= ?")))

(defun get-edge-types (graph)
  "Return list of edge type symbols in GRAPH schema."
  (if (fboundp 'graph-db:list-edge-types)
      (graph-db:list-edge-types graph)
      (error "Graph introspection not available - need graph-db >= ?")))

(defun get-type-slots (kind type graph)
  "Return list of (slot-name . slot-type) for KIND type in GRAPH."
  (ecase kind
    (:vertex
     (if (fboundp 'graph-db:list-vertex-slots)
         (graph-db:list-vertex-slots graph type)
         (error "Vertex slot introspection not available")))
    (:edge
     (if (fboundp 'graph-db:list-edge-slots)
         (graph-db:list-edge-slots graph type)
         (error "Edge slot introspection not available")))))

;;; ---------------------------------------------------------------------------
;;; Utility functions
;;; ---------------------------------------------------------------------------

(defun ensure-keyword (x)
  "Ensure X is a keyword. Converts string/symbol as needed."
  (cond ((keywordp x) x)
        ((symbolp x) (make-keyword (symbol-name x)))
        ((stringp x) (make-keyword (string-upcase x)))
        (t (error "Cannot make keyword from ~S" x))))

(defun plistp (x)
  "True if X is a proper plist (even-length list with keywords at even indices)."
  (and (listp x)
       (evenp (length x))
       (loop for i from 0 below (length x) by 2
             always (keywordp (nth i x)))))
