;;; HNSW Spike - Data Structures
;;; Core struct definitions for HNSW graph implementation
;;;
;;; Documentation:
;;;   This file defines the fundamental data structures used throughout the
;;; HNSW (Hierarchical Navigable Small World) graph implementation.
;;;
;;;   hnw-node: Basic HNSW node containing vector and neighbor relationships
;;;   hnw-index: Complete HNSW index structure wrapping configuration and node storage

;;; ============================================================================
;;; hnw-node struct
;;; ============================================================================
;;;
;;; Core data structure representing a node in the HNSW graph.
;;;
;;; Slots:
;;;   id       - Unique node identifier (fixnum for performance)
;;;           Used for hash table lookups and neighbor references
;;;
;;;   vector   - Node's feature vector (simple-array single-float)
;;;           Dimension must match the graph's dim parameter
;;;           Stored as simple-array for SIMD-friendly access pattern
;;;
;;;   level    - Current HNSW level (fixnum, 0 = base layer)
;;;           Higher levels are "express lanes" for faster search
;;;           Level 0 always exists as the base layer
;;;
;;;   neighbors - Association list or vector of neighbor node references
;;;              One entry per HNSW level, containing nodes adjacent at that level
;;;              Maintains the M-limited connectivity per level
;;;
;;; Note: The struct is defined with default values for quick initialization.
;;; All slots have type declarations for performance optimization with SBCL.
;;; The struct is used extensively in the core algorithms and must remain
;;; compatible with the hash table operations in core.lisp.

(defstruct hnw-node
  id                ; unique node identifier
  vector           ; node vector (simple-array single-float)
  level            ; current HNSW level
  neighbors)       ; neighbor lists per level)

;;; ============================================================================
;;; hnw-index struct
;;; ============================================================================
;;;
;;; Top-level HNSW index container wrapping configuration and node storage.
;;;
;;; Slots:
;;;   entry-point  - Top-level entry node for search starts; NIL until first insert
;;;                 Type: (or null hnsw-node)
;;;
;;;   max-level    - Maximum node level in the graph (fixnum)
;;;                Set automatically during insert operations
;;;
;;;   nodes        - Hash table mapping node-id to hnw-node struct
;;;                Type: hash-table
;;;
;;;   dim          - Vector dimensionality (fixnum)
;;;                Must match the vectors being stored
;;;
;;;   metric-fn    - Distance function for computing distances between vectors
;;;                Type: function
;;;                Selected based on the :metric configuration parameter
;;;
;;; The index is created empty via create-hnsw-index and populated via
;;; hnsw-insert. The entry-point is automatically set to the first inserted node
;;; and used as the starting point for all subsequent search operations.

(defstruct hnw-index
  entry-point      ; top-level entry node
  max-level        ; maximum level in graph
  nodes            ; hash table of nodes indexed by id
  dim              ; vector dimensionality
  metric-fn)       ; distance function for metric computation)