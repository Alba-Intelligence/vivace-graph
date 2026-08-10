;;;; graph-db/import-export/protocol.lisp
;;;; Format protocol and registry for pluggable import/export formats.

(in-package :graph-db.import-export)

;;; ---------------------------------------------------------------------------
;;; Format object
;;; ---------------------------------------------------------------------------

(defstruct format-spec
  (name nil :type keyword :read-only t)
  (import-parser nil :type (or null function))
  (export-serializer nil :type (or null function))
  (streaming-p nil :type boolean)
  (supports-export-p nil :type boolean))

;;; ---------------------------------------------------------------------------
;;; Format registry
;;; ---------------------------------------------------------------------------

(defvar *format-registry* (make-hash-table :test 'eq)
  "Hash table mapping format keywords (e.g., :jsonl, :csv) to FORMAT-SPEC objects.")

(defun register-format (name &key import-parser export-serializer streaming-p supports-export-p)
  "Register a new import/export format.
NAME: keyword identifying the format (e.g., :jsonl, :csv)
IMPORT-PARSER: function of one argument (source) returning a parser iterator function
EXPORT-SERIALIZER: function of one argument (target-stream) returning a serializer function
STREAMING-P: boolean, true if format supports constant-memory streaming
SUPPORTS-EXPORT-P: boolean, true if format has export implementation
Returns the created FORMAT-SPEC object."
  (let ((fmt (make-format-spec
                   :name name
                   :import-parser import-parser
                   :export-serializer export-serializer
                   :streaming-p (or streaming-p nil)
                   :supports-export-p (or supports-export-p nil))))
    (setf (gethash name *format-registry*) fmt)
    fmt))

(defun find-format (name)
  "Look up a format by keyword name. Signals error if not found."
  (or (gethash name *format-registry*)
      (error "Unknown import/export format: ~S. Registered formats: ~S"
             name (alexandria:hash-table-keys *format-registry*))))

(defun format-streaming-p (format)
  "True if FORMAT (keyword or FORMAT-SPEC object) supports constant-memory streaming."
  (format-spec-streaming-p (if (keywordp format) (find-format format) format)))

(defun format-supports-export (format)
  "True if FORMAT (keyword or FORMAT-SPEC object) has an export implementation."
  (format-spec-supports-export-p (if (keywordp format) (find-format format) format)))

;;; ---------------------------------------------------------------------------
;;; Generic protocol functions
;;; ---------------------------------------------------------------------------

(defgeneric import-format (format source graph mapping opts)
  (:documentation
   "Import from SOURCE into GRAPH per MAPPING.
FORMAT: keyword or FORMAT-SPEC object
SOURCE: pathname, stream, or :stdin
GRAPH: graph instance
MAPPING: parsed mapping spec (from PARSE-MAPPING-SPEC)
OPTS: plist of options (:conflict-policy, :chunk-size, :resume-token, ...)
Returns (values stats resume-token) where stats is a plist of counters."))

(defgeneric export-format (format target graph mapping opts)
  (:documentation
   "Export GRAPH to TARGET per MAPPING.
FORMAT: keyword or FORMAT-SPEC object
TARGET: pathname, stream, or :stdout
GRAPH: graph instance
MAPPING: parsed mapping spec (from PARSE-MAPPING-SPEC) or NIL for default
OPTS: plist of options (:vertex-types, :edge-types, :include-geometry, ...)
Returns stats plist."))

;;; ---------------------------------------------------------------------------
;;; Default methods (signal not-implemented)
;;; ---------------------------------------------------------------------------

(defmethod import-format (format source graph mapping opts)
  (declare (ignore source graph mapping opts))
  (error "Import not implemented for format ~A" (format-spec-name format)))

(defmethod export-format (format target graph mapping opts)
  (declare (ignore target graph mapping opts))
  (error "Export not implemented for format ~A" (format-spec-name format)))