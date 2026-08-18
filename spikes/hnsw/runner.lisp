(in-package :cl-user)

(defpackage :hnsw-spike.runner
  (:use :cl :hnsw-spike.core :hnsw-spike)
  (:export :generate-random-vectors :run-hnsw-spike))

(in-package :hnsw-spike.runner)

(defun generate-random-vectors (count dim)
  "Generate COUNT random vectors of dimension DIM."
  (loop for i below count
        collect (make-array dim
                            :element-type 'single-float
                            :initial-contents
                            (loop for j below dim
                                  collect (random 1.0)))))

(defun run-hnsw-spike (&optional (vector-count 10000) (dim 1536))
  "Run HNSW performance spike with given parameters."
  (format t "Running HNSW performance spike~%")
  (format t "Vectors: ~D, Dimension: ~D~%" vector-count dim)
  
  (let* ((index (create-hnsw-index dim :cosine))
         (vectors (generate-random-vectors vector-count dim))
         (query-vectors (generate-random-vectors 100 dim)))
    
    ;; Insert benchmark
    (format t "Inserting ~D vectors...~%" vector-count)
    (time
      (loop for i below vector-count
            for vec in vectors
            do (hnsw-insert index vec i)))
    
    ;; Search benchmark
    (format t "Searching ~D queries...~%" (length query-vectors))
    (time
      (loop for vec in query-vectors
            collect (hnsw-search index vec 10)))
    
    ;; Basic validation
    (format t "Index stats: ~D nodes, max-level ~D~%"
            (hash-table-count (hnsw-index-nodes index))
            (hnsw-index-max-level index))
    
    (values index vectors query-vectors)))
