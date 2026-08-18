;;; Test script for HNSW spike
;;; This validates the core implementation works

(in-package :cl-user)

;; Ensure all core HNSW components load in correct order
(load "spikes/hnsw/params.lisp")
(load "spikes/hnsw/distance.lisp")
(load "spikes/hnsw/structures.lisp")
(load "spikes/hnsw/heap.lisp")
(load "spikes/hnsw/core.lisp")
(load "spikes/hnsw/utils.lisp")

;; Basic functionality tests
(print "All files loaded successfully")

;; Test create-hnsw-index
(let ((idx (create-hnsw-index 128 :cosine)))
  (print (format nil "Created index with ~D nodes" (hash-table-count (hnsw-index-nodes idx))))
  (assert idx "Index creation failed")
  (format t "~%Index created~%"))

;; Test distance functions
(let ((v1 (make-array 128 :element-type 'single-float :initial-element 0.5))
      (v2 (make-array 128 :element-type 'single-float :initial-element 0.3)))
  (let ((cd (cosine-distance v1 v2)))
    (format t "Cosine distance: ~F~%" cd)
    (assert (<= cd 2.0) "Cosine distance out of range"))
  (let ((ld (l2-distance v1 v2)))
    (format t "L2 distance: ~F~%" ld)
    (assert (> ld 0.0) "L2 distance should be positive"))
  (let ((dd (dot-distance v1 v2)))
    (format t "Dot distance: ~F~%" dd)))

;; Test heap operations
(let ((heap (make-array 0 :element-type 'fixnum)))
  (heap-push! heap 10 #'(lambda (x) x))
  (heap-push! heap 5 #'(lambda (x) x))
  (heap-push! heap 20 #'(lambda (x) x))
  (let ((popped (heap-pop! heap #'(lambda (x) x))))
    (format t "Popped: ~D~%" popped)
    (assert (= popped 5) "Heap pop should return smallest"))
  (let ((popped2 (heap-pop! heap #'(lambda (x) x))))
    (format t "Popped2: ~D~%" popped2)
    (assert (= popped2 10) "Heap pop should return next smallest")))

(print "~%All tests passed!~%~%")