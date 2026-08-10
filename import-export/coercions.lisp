;;;; graph-db/import-export/coercions.lisp
;;;; Type coercion registry and built-in coercions.

(in-package :graph-db/import-export)

;;; ---------------------------------------------------------------------------
;;; Coercion registry
;;; ---------------------------------------------------------------------------

(defvar *coercion-registry* (make-hash-table :test 'eq)
  "Maps coercion names (keywords) to functions: (raw-value) -> coerced-value.
Functions should signal an error of type COERCION-ERROR on failure.")

(define-condition coercion-error (error)
  ((coercion-name :initarg :coercion-name :reader coercion-error-coercion-name)
   (raw-value :initarg :raw-value :reader coercion-error-raw-value)
   (message :initarg :message :reader coercion-error-message))
  (:report (lambda (c s)
             (format s "Coercion ~S failed for value ~S: ~A"
                     (coercion-error-coercion-name c)
                     (coercion-error-raw-value c)
                     (coercion-error-message c)))))

(defun register-coercion (name fn)
  "Register a coercion function NAME -> FN.
FN: function of one argument (raw-value) returning coerced value.
Returns FN."
  (check-type name keyword)
  (setf (gethash name *coercion-registry*) fn)
  fn)

(defun find-coercion (name)
  "Look up coercion function by NAME (keyword). Signals error if not found."
  (or (gethash name *coercion-registry*)
      (error "Unknown coercion: ~S. Registered: ~S"
             name (alexandria:hash-table-keys *coercion-registry*))))

(defun coerce-value (coercion-name raw-value)
  "Apply COERCION-NAME to RAW-VALUE. Returns coerced value.
Signals COERCION-ERROR on failure."
  (let ((fn (find-coercion coercion-name)))
    (handler-case
        (funcall fn raw-value)
      (error (e)
        (error 'coercion-error
               :coercion-name coercion-name
               :raw-value raw-value
               :message (format nil "~A" e))))))

;;; ---------------------------------------------------------------------------
;;; Built-in coercions
;;; ---------------------------------------------------------------------------

;; String passthrough
(register-coercion :string
  (lambda (x)
    (cond ((stringp x) x)
          ((null x) "")
          (t (format nil "~A" x)))))

;; Integer: parses strings, passes through integers
(register-coercion :integer
  (lambda (x)
    (cond ((integerp x) x)
          ((stringp x) (parse-integer x :junk-allowed t))
          ((floatp x) (floor x))
          (t (error "Cannot coerce ~S to integer" x)))))

;; Float: parses strings, passes through numbers
(register-coercion :float
  (lambda (x)
    (cond ((floatp x) (coerce x 'double-float))
          ((integerp x) (coerce x 'double-float))
          ((stringp x) (read-from-string x))
          (t (error "Cannot coerce ~S to float" x)))))

;; Boolean: common truthy/falsy values
(register-coercion :boolean
  (lambda (x)
    (cond ((booleanp x) x)
          ((stringp x) (member (string-downcase x) '("t" "true" "1" "yes" "y" "on") :test 'string=))
          ((integerp x) (not (zerop x)))
          ((null x) nil)
          (t t))))

;; UUID: string -> 16-byte array
(register-coercion :uuid
  (lambda (x)
    (cond ((and (arrayp x) (= (length x) 16) (every #'unsigned-byte-p x)) x)
          ((stringp x)
           (let ((uuid (uuid:make-uuid-from-string x)))
             (uuid:uuid-to-byte-array uuid)))
          (t (error "Cannot coerce ~S to UUID" x)))))

;; Email: string with @ validation
(register-coercion :email
  (lambda (x)
    (let ((s (cond ((stringp x) x)
                   ((null x) "")
                   (t (format nil "~A" x)))))
      (when (and (stringp s) (find #\@ s))
        s))))

;; Timestamp: ISO8601 string -> local-time:timestamp
(register-coercion :timestamp
  (lambda (x)
    (cond ((typep x 'local-time:timestamp) x)
          ((stringp x) (local-time:parse-timestring x))
          ((integerp x) (local-time:universal-to-timestamp x))
          (t (error "Cannot coerce ~S to timestamp" x)))))

;; Date: YYYY-MM-DD string -> local-time:timestamp (at midnight)
(register-coercion :date
  (lambda (x)
    (cond ((typep x 'local-time:timestamp) x)
          ((stringp x) (local-time:parse-timestring x))
          (t (error "Cannot coerce ~S to date" x)))))