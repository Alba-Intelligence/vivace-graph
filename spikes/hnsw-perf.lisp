;;; HNSW Performance Spike - Main Benchmark File
;;; Implements HNSW insert + KNN search in pure Common Lisp (SBCL)
;;;
;;; Usage:
;;;   1. Load params first to set up the :hnsw-spike package:
;;;      (load "spikes/hnsw/params.lisp")
;;;   2. Then load this file and run:
;;;      (run-benchmark)
;;;
;;; All HNSW functions are accessed via the :hnsw-spike package
;;; which is set up by params.lisp.

;; Load core components in dependency order
;; (Must load params.lisp first to create :hnsw-spike package)

(in-package :cl-user)

;; Load params FIRST - this creates the :hnsw-spike package and exports symbols (but structs not yet loaded)
(load (merge-pathnames "hnsw/params.lisp" *load-pathname*))

;; Now load the rest of the components (order matters: heap before core)
(load (merge-pathnames "hnsw/distance.lisp" *load-pathname*))
(load (merge-pathnames "hnsw/structures.lisp" *load-pathname*))
(load (merge-pathnames "hnsw/heap.lisp" *load-pathname*))
(load (merge-pathnames "hnsw/core.lisp" *load-pathname*))
(load (merge-pathnames "hnsw/utils.lisp" *load-pathname*))

;; Now safe to declare benchmark package that uses :hnsw-spike (which now has the struct accessors)
(defpackage :hnsw-spike-bench
  (:use :cl :hnsw-spike)
  (:export :run-benchmark))

(in-package :hnsw-spike-bench)

;; ============================================================================
;;  Benchmark Configuration
;; ============================================================================

(defparameter *vector-count* 10000)
(defparameter *vector-dim* 128)
(defparameter *n-clusters* 7)
(defparameter *m* 16)
(defparameter *ef-construction* 200)
(defparameter *ef-search* 50)
(defparameter *queries* 100)
(defparameter *max-level* 16)

;; ============================================================================
;;  Generate Synthetic Dataset - Gaussian clusters
;; ============================================================================

(defun generate-gaussian-clusters (count dim  &key (clusters *n-clusters*) (state nil))
  "Generate COUNT vectors clustered into CLUSTERS groups."
  (let ((rng (make-random-state state)))
    (loop for i below count
          collect (let ((cluster (random clusters rng)))
                    (make-array dim
                                :element-type 'single-float
                                :initial-contents
                                (loop for j below dim
                                      collect (+ (random 0.5 rng) (* cluster 0.2))))))))

;; ============================================================================
;;  HNSW Benchmark Functions
;; ============================================================================

;;; Insert benchmark - returns microseconds per insert
(defun bench-insert (index vectors)
  (declare (type hnsw-index index)
           (type (cons (simple-array single-float)) vectors))
  (let ((count (length vectors))
        (start (get-internal-run-time)))
    (loop for id below count
          for vec in vectors
          do (hnsw-insert index vec id))
    (let ((end (get-internal-run-time)))
      (/ (* (- end start) 1000.0) count)))) ;; microseconds per insert


;;; Search benchmark - returns total microseconds
(defun bench-search (index query-vectors)
  (declare (type hnsw-index index)
           (type (cons (simple-array single-float)) query-vectors))
  (let ((start (get-internal-run-time))
        (results (loop for vec in query-vectors
                       collect (hnsw-search index vec 10))))
    (let ((end (get-internal-run-time)))
      (* (- end start) 1000.0)))) ;; total microseconds


;;; Brute-force ground truth for recall@10
(defun brute-force-nearest (query-vector nodes metric-fn &key (k 10))
  "Compute exact k nearest neighbors by linear scan."
  (declare (type (simple-array single-float) query-vector)
           (type hash-table nodes)
           (type fixnum k))
  (let* ((dists (loop for node being the hash-values of nodes
          collect (cons (funcall metric-fn query-vector (hnsw-node-vector node)) node )))
         (sorted (sort dists #'< :key #'car)))
    (loop for i below (min k (length sorted))
          collect (cdr (nth i sorted)))))

;; ============================================================================
;;  Run Full Benchmark
;; ============================================================================

(defun run-benchmark ()
  "Run complete HNSW performance benchmark."
  (format t "~%=== HNSW Performance Spike Benchmark ===~%")
  (format t "Vectors: ~D, Dimension: ~D, n clusters: ~D~%" *vector-count* *vector-dim* *n-clusters*)
  (format t "Parameters: M=~D, efConstruction=~D, efSearch=~D~%" *m* *ef-construction* *ef-search*)
  (format t "Queries: ~D~%" *queries*)
  (format t "~%")

  ;; Generate dataset
  (format t "Generating ~D vectors with Gaussian clusters...~%" *vector-count*)
  (let ((vectors (generate-gaussian-clusters *vector-count* *vector-dim*  :state t)))
    (format t "Dataset generated. The vectors are of type: ~S ~%" (type-of vectors))

    ;; Create index
    (format t "Creating HNSW index...~%")
    (let ((idx (create-hnsw-index *vector-dim* :metric :cosine)))
      (format t "Index created.~%")

      ;; Insert benchmark
      (format t "~%=== Insert Benchmark ===~%")
      (let ((insert-us (bench-insert idx vectors)))
        (format t "Insert throughput: ~D vec/s~%"
                (round (/ *vector-count* (* 1000000.0 insert-us))))

        ;; Search benchmark
        (format t "~%=== Search Benchmark ===~%")
        (let ((query-vectors (generate-gaussian-clusters *queries* *vector-dim*  :state t)))
          (let ((search-us (bench-search idx query-vectors)))
            (format t "Search total: ~D us (~D ms)~%" search-us (round search-us 1000))
            (format t "Search avg: ~D us/query~%" (round search-us *queries*))

            ;; Compute recall@10 against brute-force ground truth
            (format t "~%=== Recall@10 ===~%")
            (let ((node-ht (hnsw-index-nodes idx))
                  (metric-fn (hnsw-index-metric-fn idx)))
              (let ((hits 0))
                (loop for i below *queries*
                      for qv = (nth i query-vectors)
                      for hnsw-results = (hnsw-search idx qv 10)
                      do (let ((bf-results (brute-force-nearest qv node-ht metric-fn :k 10)))
                          (dolist (hnsw-node hnsw-results)
                            (when (member hnsw-node bf-results :test #'eq)
                              (incf hits)))))
                (let ((recall (/ hits (float (* *queries* 10)))))
                  (format t "Recall@10: ~F~%" (* 100 recall)))))

            (format t "~%=== Results Summary ===~%")
            (format t "Insert: ~D vec/s~%" (round (/ *vector-count* (* 1000000000.0 insert-us))))
            (format t "Search avg: ~D us/query~%" (round search-us *queries*))
            (format t "~%=== End of Benchmark ===%")))))))

;; Provide the run-benchmark function for external invocation
(provide :hnsw-spike-bench)

(run-benchmark)