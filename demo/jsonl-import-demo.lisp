(in-package #:graph-db/jsonl-demo)

;; Make sure that the Turtle import is available
;; TODO


;; Location of Yago schema and taxonomy
(defvar +jsonl-db+ nil)

;; Key namespaces
(defvar *vertex-namespace* (uuidv7:generate))
(defvar *edge-namespace* (uuidv7:generate))

(defparameter *small-example* (make-pathname :directory '(:relative "jsonl") 
                                             :name "small" :type "jsonl"))

(defparameter *brandeskopf-example* (make-pathname :directory '(:relative "jsonl") 
                                                   :name "brandeskopf" :type "jsonl"))

(defparameter *gin-example* (make-pathname :directory '(:relative "jsonl") 
                                           :name "gin" :type "jsonl"))


(graph-db/import-export:find)

(defparameter *example-resources* 
  '("https://yago-knowledge.org/resource/Elvis_Presley"    
    "https://yago-knowledge.org/resource/Portugal"
    "https://yago-knowledge.org/resource/Bologna_University_Press"
    "https://yago-knowledge.org/resource/Ericsson" 
    "https://yago-knowledge.org/resource/Gilgamesh"))





(defun test-turtle-parser ()
  "Test the Turtle parser with sample data."
  (let* ((parser-fn (import-export.turtle::parse-turtle-file 
                     "import-export/testdata/turtle-sample.ttl"))
         (triples (funcall parser-fn))
         (triple-count (length triples)))
    (format t "Parsed ~A triples from Turtle file~%" triple-count)
    (when (> triple-count 0)
      (format t "First triple: ~A~%" (first triples))
      t)))



(defun run-turtle-tests ()
  "Run Turtle format tests."
  (format t "=== Testing Turtle format support ==~%")
  (test-turtle-parser)
  (format t "=== Turtle format tests completed ==~%"))

;; Run tests when loaded
(run-turtle-tests)

