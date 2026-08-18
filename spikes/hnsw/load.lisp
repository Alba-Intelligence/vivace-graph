;;; HNSW Spike - Load all components
;;; Load order matters due to dependencies
;;;   params -> distance -> structures -> heap -> core -> utils

(load "spikes/hnsw/params.lisp")
(load "spikes/hnsw/distance.lisp")
(load "spikes/hnsw/structures.lisp")
(load "spikes/hnsw/heap.lisp")
(load "spikes/hnsw/core.lisp")
(load "spikes/hnsw/utils.lisp")