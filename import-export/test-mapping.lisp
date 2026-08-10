;;;; graph-db/import-export/test-mapping.lisp
;;;; Test for mapping DSL.

(in-package :graph-db/import-export)

;; Mock graph schema functions for testing
(defun mock-list-vertex-types () '(person customer))
(defun mock-list-edge-types () '(likes sells))
(defun mock-list-vertex-slots (type)
  (ecase type
    (person '((:name . string) (:age . integer) (:email . string) (:location . geometry)))
    (customer '((:id . uuid) (:name . string) (:tier . integer)))))
(defun mock-list-edge-slots (type)
  (ecase type
    (likes '((:person . uuid) (:customer . uuid) (:date . timestamp)))
    (sells '((:store . uuid) (:product . uuid) (:quantity . integer)))))

;; Override schema functions for testing
(defun list-vertex-types (graph) (declare (ignore graph)) (mock-list-vertex-types))
(defun list-edge-types (graph) (declare (ignore graph)) (mock-list-edge-types))
(defun list-vertex-slots (type graph) (declare (ignore graph)) (mock-list-vertex-slots type))
(defun list-edge-slots (type graph) (declare (ignore graph)) (mock-list-edge-slots type))

(defun test-parse-mapping-spec ()
  "Test parsing Lisp mapping spec."
  (let* ((spec '((:vertex-type :person
                  ((:source-field "name" :target-slot :name :coerce string)
                   (:source-field "age" :target-slot :age :coerce integer :transform #'(lambda (x) (* x 2)))
                   (:source-field "email" :target-slot :email :coerce email :required t))
                 (:vertex-type :customer
                  ((:source-field "cid" :target-slot :id :coerce uuid)))
                 (:edge-type :likes
                  ((:source-field "from" :target-slot :person :coerce uuid)
                   (:source-field "to" :target-slot :customer :coerce uuid)
                   (:source-field "date" :target-slot :date :coerce timestamp)))))
         (parsed (parse-mapping-spec spec)))
    (assert (eq (mapping-spec-vertex-mappings parsed) (length 2)))
    (assert (eq (mapping-spec-edge-mappings parsed) (length 1)))
    (let ((person-map (first (mapping-spec-vertex-mappings parsed))))
      (assert (eq (vertex-mapping-type person-map) :person))
      (assert (eq (length (vertex-mapping-slots person-map)) 3))
      (let ((age-slot (third (vertex-mapping-slots person-map))))
        (assert (eq (slot-mapping-coerce age-slot) :integer))
        (assert (functionp (slot-mapping-transform age-slot)))))
    (format t "parse-mapping-spec test PASSED~%")))

(defun test-load-mapping-file-json ()
  "Test loading JSON mapping file."
  (let* ((json-spec '((:vertex-type :person
                       ((:source-field "name" :target-slot :name :coerce string)
                        (:source-field "age" :target-slot :age :coerce integer))))
          (json-str (cl-json:encode-json-to-string json-spec)))
    ;; Write to temp file
    (with-open-file (out "/tmp/test-mapping.json" :direction :output :if-exists :supersede)
      (write-line json-str out))
    (let ((parsed (load-mapping-file "/tmp/test-mapping.json")))
      (assert (eq (length (mapping-spec-vertex-mappings parsed)) 1))
      (let ((person-map (first (mapping-spec-vertex-mappings parsed))))
        (assert (eq (vertex-mapping-type person-map) :person))
        (assert (eq (length (vertex-mapping-slots person-map)) 2))))
    (format t "load-mapping-file JSON test PASSED~%")
    (ignore-errors (uiop:delete-file-if-exists "/tmp/test-mapping.json"))))

(defun test-coerce-value ()
  "Test type coercion."
  ;; String
  (assert (string= (coerce-value :string 123) "123"))
  (assert (string= (coerce-value :string "hello") "hello"))
  ;; Integer
  (assert (= (coerce-value :integer "42") 42))
  (assert (= (coerce-value :integer 3.7) 3))
  ;; Float
  (assert (= (coerce-value :float "3.14") 3.14))
  (assert (= (coerce-value :float 42) 42.0))
  ;; Boolean
  (assert (eq (coerce-value :boolean "true") t))
  (assert (eq (coerce-value :boolean "false") nil))
  (assert (eq (coerce-value :boolean 0) nil))
  (assert (eq (coerce-value :boolean 1) t))
  ;; UUID
  (let ((uuid-str "123e4567-e89b-12d3-a456-426614174000"))
    (let ((uuid-arr (coerce-value :uuid uuid-str)))
      (assert (= (length uuid-arr) 16))
      (assert (every #'unsigned-byte-p uuid-arr))))
  ;; Email
  (assert (string= (coerce-value :email "test@example.com") "test@example.com"))
  (assert (null (coerce-value :email "invalid-email")))
  (format t "coerce-value test PASSED~%"))

(defun test-validate-mapping-spec ()
  "Test validation against mock schema."
  (let* ((spec '((:vertex-type :person
                  ((:source-field "name" :target-slot :name :coerce string))
                 (:vertex-type :customer
                  ((:source-field "id" :target-slot :id :coerce uuid))))
         (graph nil))  ; graph ignored due to mocking
         (parsed (parse-mapping-spec spec)))
    ;; This should pass
    (validate-mapping-spec parsed graph)
    (format t "validate-mapping-spec valid test PASSED~%")
    ;; This should fail - unknown type
    (handler-case
        (validate-mapping-spec (parse-mapping-spec '((:vertex-type :unknown
                                                      ((:source-field "x" :target-slot :y :coerce string)))))
                               graph)
      (error () (format t "validate-mapping-spec invalid type test PASSED~%")))
    ;; This should fail - unknown slot
    (handler-case
        (validate-mapping-spec (parse-mapping-spec '((:vertex-type :person
                                                      ((:source-field "x" :target-slot :nonexistent :coerce string)))))
                               graph)
      (error () (format t "validate-mapping-spec invalid slot test PASSED~%")))))

(defun run-mapping-tests ()
  (format t "Running mapping DSL tests...~%")
  (test-parse-mapping-spec)
  (test-load-mapping-file-json)
  (test-coerce-value)
  (test-validate-mapping-spec)
  (format t "All mapping DSL tests PASSED~%"))

;; Run tests when loaded
(run-mapping-tests)