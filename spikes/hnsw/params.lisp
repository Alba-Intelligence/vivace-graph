;;; HNSW Spike - Package & Parameters
(in-package :cl-user)

(defpackage :hnsw-spike
  (:use :cl)
  (:export
   :run-hnsw-spike
   :*M* :*ef-construction* :*ef-search* :*max-level*
   :hnsw-node :hnsw-index
   :create-hnsw-index :random-level
   :search-layer :find-entry-point :connect-neighbors
   :hnsw-insert :hnsw-search
   :generate-random-vectors))

(in-package :hnsw-spike)

(defparameter *M* 16)
(defparameter *ef-construction* 200)
(defparameter *ef-search* 50)
(defparameter *max-level* 16)
(defparameter *default-embedding-size* 1536)
