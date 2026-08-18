;;; HNSW Spike - Data Structures
;;; Core struct definitions for HNSW graph implementation
;;;
;;; Documentation:
;;;   This file defines the fundamental data structures used throughout the
;;; HNSW (Hierarchical Navigable Small World) graph implementation.
;;;
;;;   hnsw-node: Basic HNSW node containing vector and neighbor relationships
;;;   hnsw-index: Complete HNSW index structure wrapping configuration and node storage

(in-package :hnsw-spike)


(defstruct hnsw-node
  "hnsw-node struct
Core data structure representing a node in the HNSW graph.
Slots:
  id       - Unique node identifier (fixnum for performance)
           Used for hash table lookups and neighbor references
  vector   - Node's feature vector (simple-array single-float)
           Dimension must match the graph's dim parameter
           Stored as simple-array for SIMD-friendly access pattern
  level    - Current HNSW level (fixnum, 0 = base layer)
           Higher levels are express lanes for faster search
           Level 0 always exists as the base layer
  neighbors - Simple vector of neighbor lists, indexed by level.
             (aref neighbors l) returns list of neighbor IDs at level l.
             Size = level + 1. Level 0 always present.
             Maintains M-limited connectivity per level.
Note: The struct is defined with default values for quick initialization.
All slots have type declarations for performance optimization with SBCL.
The struct is used extensively in the core algorithms and must remain
compatible with the hash table operations in core.lisp."
  (id 0 :type fixnum)
  (vector (make-array *default-embedding-size* :element-type 'single-float) :type (simple-array single-float))
  (level 0 :type fixnum)
  (neighbors (make-array 1 :initial-element nil) :type (simple-array list (*))))

(defstruct hnsw-index
  "hnsw-index struct
Top-level HNSW index container wrapping configuration and node storage.
Slots:
  entry-point  - Top-level entry node ID for search starts; NIL until first insert
                Type: (or null fixnum)
  max-level    - Maximum node level in the graph (fixnum)
               Set automatically during insert operations
  nodes        - Hash table mapping node-id to hnsw-node struct
               Type: hash-table
  dim          - Vector dimensionality (fixnum)
               Must match the vectors being stored
  metric-fn    - Distance function for computing distances between vectors
               Type: function
               Selected based on the :metric configuration parameter
The index is created empty via create-hnsw-index and populated via
hnsw-insert. The entry-point is automatically set to the first inserted node's ID
and used as the starting point for all subsequent search operations."
  (entry-point nil :type (or null fixnum))
  (metric-fn :cosine)
  (nodes nil :type (or null hash-table))
  (dim *default-embedding-size* :type fixnum)
  (max-level 0 :type fixnum))