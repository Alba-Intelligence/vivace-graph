;;;; graph-db/import-export/test-turtle.lisp
;;;; Test for Turtle format support.

(ql:quickload :graph-db)

(in-package :graph-db/import-export)

(defparameter *sample-triples*
  '(("http://yago-knowledge.org/resource/Barack_Obama"
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
     "http://dbpedia.org/ontology/Person")
    ("http://yago-knowledge.org/resource/Barack_Obama"
     "http://dbpedia.org/ontology/birthDate"
     "\"1961-08-04\"^^xsd:date")
    ("http://yago-knowledge.org/resource/Barack_Obama"
     "http://dbpedia.org/ontology/name"
     "\"Barack Obama\"")
    ("http://yago-knowledge.org/resource/Michelle_Obama"
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
     "http://dbpedia.org/ontology/Person")
    ("http://yago-knowledge.org/resource/Michelle_Obama"
     "http://dbpedia.org/ontology/birthDate"
     "\"1964-01-17\"^^xsd:date")
    ("http://yago-knowledge.org/resource/Michelle_Obama"
     "http://dbpedia.org/ontology/name"
     "\"Michelle Obama\"")
    ("http://yago-knowledge.org/resource/Hope_College"
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
     "http://dbpedia.org/ontology/EducationalInstitution")
    ("http://yago-knowledge.org/resource/Hope_College"
     "http://dbpedia.org/ontology/name"
     "\"Hope College\"")
    ("http://yago-knowledge.org/resource/Hopkins_Minnesota"
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
     "http://dbpedia.org/ontology/Place")))

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
