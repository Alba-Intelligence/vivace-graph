;;;; graph-db/import-export/test-jsonl-integration.lisp
;;;; Integration tests for JSONL import/export using real testdata files.

(in-package :graph-db.import-export)

;; Define test mapping specs
(defparameter test-people-mapping-spec
  '((:vertex-type :person
     ((:source-field "name" :target-slot :name :coerce string)
      (:source-field "age" :target-slot :age :coerce integer)
      (:source-field "email" :target-slot :email :coerce email)))
    (:vertex-type :customer
     ((:source-field "cid" :target-slot :id :coerce uuid)))
    (:edge-type :likes
     ((:source-field "from" :target-slot :person :coerce uuid)
      (:source-field "to" :target-slot :customer :coerce uuid)))))

(defparameter test-k8s-mapping-spec
  '((:vertex-type :pod
     ((:source-field "to" :target-slot :pod-id :coerce string)
      (:source-field "from" :target-slot :rs-id :coerce string)))
    (:edge-type :owns
     ((:source-field "to" :target-slot :pod :coerce uuid)
      (:source-field "from" :target-slot :rs :coerce uuid)))))

(defun define-graph-from-mapping (graph-name mapping-spec)
  "Create a graph with schema matching the mapping spec."
  (declare (ignore mapping-spec))  ; Schema creation requires vertex/edge defs
  (graph-db:make-graph graph-name "/tmp/test-graph/"))

(defun define-export-mapping-from-schema (graph)
  "Create export mapping spec from graph schema."
  `((:vertex-type :vertex)
    (:edge-type :edge)))

(defun define-vertex-from-plist (graph type-id plist)
  "Create a vertex from plist using the graph's API."
  (let ((slot-plist (remove-from-plist plist '(:type :source-id))))
    (graph-db:make-vertex graph type-id slot-plist)))

(defun define-edge-from-plist (graph type-id from-id to-id plist)
  "Create an edge from plist using the graph's API."
  (let ((slot-plist (remove-from-plist plist '(:type :from :to :source-id))))
    (graph-db:make-edge graph type-id from-id to-id slot-plist)))

(defun define-load-jsonl-test (graph-name mapping-spec filename)
  "Load JSONL file using our API."
  (let ((graph (define-graph-from-mapping graph-name mapping-spec)))
    (unwind-protect
         (multiple-value-bind (stats token)
             (import-graph :format :jsonl
                           :source filename
                           :graph graph
                           :mapping mapping-spec
                           :conflict-policy :upsert
                           :chunk-size 5)
           (format t "Import ~A: ~D vertices, ~D edges, ~D errors~%"
                   filename (getf stats :vertices-created)
                          (getf stats :edges-created)
                          (getf stats :errors))
           (values stats token))
      (graph-db:close-graph graph)
      (ignore-errors (uiop:delete-directory-tree "/tmp/test-graph/" :validate t)))))

(defun define-export-jsonl-test (graph-name filename)
  "Export graph to JSONL file."
  (let ((graph (graph-db:make-graph graph-name "/tmp/test-graph/")))
    (unwind-protect
         (let ((stats (export-graph :format :jsonl
                                    :target filename
                                    :graph graph)))
           (format t "Export ~A: ~D vertices, ~D edges~%"
                   filename (getf stats :vertices-exported)
                          (getf stats :edges-exported))
           stats)
      (graph-db:close-graph graph)
      (ignore-errors (uiop:delete-directory-tree "/tmp/test-graph/" :validate t)))))

(defun define-round-trip-test (mapping-spec filename)
  "Complete round-trip test: export then import."
  (let ((graph-name (format nil "test-~A" filename)))
    ;; Export first
    (format t "=== Round-trip test for ~A ===~%" filename)
    (define-export-jsonl-test graph-name filename)
    ;; Clear and re-import
    (define-load-jsonl-test graph-name mapping-spec filename)))

(defun define-integration-tests ()
  "Run all integration tests."
  (format t "=== JSONL Integration Tests ===~%")
  
  ;; Test 1: Small graph
  (define-round-trip-test test-people-mapping-spec "small")
  
  ;; Test 2: K8s pod owners
  (define-round-trip-test test-k8s-mapping-spec "k8s_pod_owners")
  
  (format t "=== All integration tests completed ===~%"))

;; Run tests when loaded
(when *load-verbose*
  (define-integration-tests))