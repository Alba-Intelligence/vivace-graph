;;; HNSW Spike - Core Algorithms
;;; HNSW (Hierarchical Navigable Small World) graph algorithms
;;;
;;; Documentation:
;;;   This file implements the core HNSW algorithms for approximate nearest
;;; neighbor search. HNSW builds a multi-layer graph with random element
;;; for ef/accuracy tradeoff, providing O(log N) search complexity.
;;;
;;; Algorithm Reference:
;;;   Malkov and Yashunsky (2016) "Efficient and robust approximate nearest
;;;   neighbor search using Hierarchical Navigable Small World graphs"
;;;
;;; Key Parameters:
;;;   *M*       - Max neighbors per level (default: 16)
;;;             Controls graph connectivity and memory usage
;;; *ef-construction* - ef for building phase (default: 200)
;;;                   Larger values produce higher quality graphs
;;; *ef-search* - ef for search phase (default: 50)
;;;               Larger values improve search accuracy but reduce speed

;;; ============================================================================
;;; create-hnsw-index
;;; ============================================================================
;;;
;;; Create and return a new empty HNSW index.
;;;
;;; Algorithm:
;;;   1. Initialize hnw-index struct with default configuration
;;;   2. Set dimension from the dim argument
;;;   3. Set metric function based on the metric symbol
;;;   4. Create empty hash table for node storage
;;;
;;; Arguments:
;;;   dim   - Vector dimensionality (e.g., 128, 768, 1536); required
;;;   metric - Distance metric symbol (default: :cosine)
;;;            :cosine - Cosine distance
;;;            :l2   - L2/Euclidean distance
;;;            :dot   - Dot product
;;
;;; Key Arguments (with defaults):
;;;   *M*           - Max neighbors per level (default 16);
;;;                 Controls graph connectivity; higher = more connections
;;;   *ef-construction* - ef for graph build phase (default 200);
;;;                     Larger = higher quality graph, slower build
;;;   *ef-search*   - ef for search phase (default 50);
;;;                   Larger = more accurate search, slower query
;;
;;; Returns: hnw-index struct with empty node hash table and configured metric
;;
;;; Example:
;;;   (let ((idx (create-hnsw-index 768 :cosine :m 16 :ef-construction 200 :ef-search 50)))
;;;     (hnsw-insert idx (make-array 768 :initial-element 0.5) 0))
;;;
;;; Note: Parameters m and ef should be chosen based on dataset size and
;;; desired accuracy/speed tradeoff. Typical values: M∈[16,64], ef∈[40,2000].

;;; ============================================================================
;;; random-level
;;; ============================================================================
;;;
;;; Generate random HNSW layer assignment for a new node.
;;;
;;; Algorithm:
;;;   Uses exponential distribution with p=0.5 probability per level.
;;;   Each level has 50% chance of being selected, creating a geometrically
;;;   distributed level assignment. This gives O(log N) graph depth expected.
;;;
;;; Arguments:
;;;   max-level  - Maximum layer level to assign (fixnum)
;;;              Typically computed as floor(log2(N)) for N nodes
;;
;;; Returns: Integer layer level in range [0, max-level]
;;;
;;; Algorithm Details:
;;;   The loop condition `(while (< (random 1.0) 0.5))` gives each level
;;;   a 50% probability of being selected. This creates the random level
;;;   distribution that is key to HNSW's search efficiency and balanced
;;;   graph growth. Nodes with higher levels appear in fewer search paths
;;;   but provide long-range connectivity.
;;;
;;; Note: This function uses the global parameter *max-level* which should
;;; be set appropriately for the expected dataset size.

;;; ============================================================================
;;; search-layer
;;; ============================================================================
;;;
;;; Search a single HNSW layer using greedy descent.
;;;
;;; Algorithm (High-level):
;;;   1. Start with entry-point node as initial candidate
;;;   2. For each candidate node: compute distance to query vector
;;;   3. Select the best (closest) candidate as next step
;;;   4. Move to that candidate and repeat at current layer
;;;   5. If no improving candidate found, prepare to descend to next layer
;;;
;;; Arguments:
;;;   index    - hnw-index struct (must be initialized)
;;;   vec      - Query vector (simple-array single-float, dimension dim)
;;;   ef       - Max candidates to maintain (controls accuracy/speed tradeoff)
;;;            Typical: *ef-search* or 50-100
;;;   metric-fn - Distance function (obtained from index metric-fn slot)
;;
;;; Returns: List of candidate nodes within this layer, sorted by distance
;;
;;; Algorithm Details:
;;;   The greedy descent algorithm:
;;;   1. Initialize candidates with entry-point node
;;;   2. While can improve: find nearest neighbor in current layer
;;;   3. If improved: move to that neighbor, continue search at same layer
;;;   4. If not improved: mark layer as exhausted, descend to next level
;;;   5. Collect all candidates visited across layers
;;;
;;;   This function implements one level of the multi-layer HNSW search.
;;;   Full search descends from top max-level down to layer 0, collecting
;;;   candidates at each level and using them as starting points for the
;;;   next lower level.
;;;
;;; Performance: O(K * average_degree) per layer examination, where K is
;;; the number of nodes examined before finding no improvement. The overall
;;; search complexity is O(log N) expected with proper ef parameter tuning.
;;;
;;; Note: This is a single-layer component; full HNSW search requires
;;; descending through all layers from max-level to 0.

;;; ============================================================================
;;; hnsw-insert
;;; ============================================================================
;;;
;;; Insert a node into the HNSW graph.
;;;
;;; Algorithm (High-level steps):
;;;   1. Generate random layer level for the new node via random-level
;;;   2. Create node struct with vector, id, level, and empty neighbor lists
;;;   3. Insert node into hash table by ID
;;;   4. Set entry-point if this is the first node
;;;   5. For each level from top node's level down to 0:
;;;      a. Search current layer to find insertion point
;;;      b. Connect new node to M nearest neighbors at this level
;;;      c. Update existing neighbors' connections to include new node
;;;
;;; Arguments:
;;;   index    - hnw-index struct (must be from create-hnsw-index)
;;;   vector   - Feature vector (simple-array single-float, dimension dim)
;;;   id       - Unique node identifier (fixnum or hashable type)
;;
;;; Returns: NIL (modifies index in-place)
;;
;;; Algorithm Details:
;;;   Full HNSW insertion involves navigational steps:
;;;   1. Start at entry-point, perform greedy descent to layer 0
;;;   2. At each level l from top to 0:
;;;      - Examine node's neighbors at level l
;;;      - Find the closest neighbor to the new vector
;;;      - Add new node as neighbor, prune to maintain *M* connections
;;;      - Update existing neighbors' neighbor lists to include new node
;;;   3. The new node's neighbor list at each level replaces the worst
;;;      existing connections, maintaining *M*-limited connectivity
;;;
;;;   The connect-neighbors function handles the detailed neighbor list
;;;   updates, ensuring that both the new node and existing nodes have
;;;   consistent neighbor references at each level.
;;;
;;; Performance: O(log N) expected for insertion with proper pruning.
;;; The dominant cost is the layer-by-layer navigation and neighbor list
;;; updates. Insertion time grows slowly with dataset size due to the
;;; logarithmic graph depth.
;;;
;;; Note: The function uses global parameters *M*, *ef-construction*, and
;;; *max-level*. All must be set appropriately before insertion operations.

;;; ============================================================================
;;; hnsw-search
;;; ============================================================================
;;;
;;; Find k nearest neighbors using HNSW greedy descent search.
;;;
;;; Algorithm:
;;;   1. Set ef to *ef-search* for candidate collection
;;;   2. Search the HNSW layer structure starting from entry-point
;;;   3. Collect all candidates within the ef search boundary
;;;   4. Sort candidates by distance to query vector
;;;   5. Return top-k results (or fewer if fewer than k nodes exist)
;;
;;; Arguments:
;;;   index    - hnw-index struct (must be initialized with nodes)
;;;   vector   - Query vector (simple-array single-float, dimension dim)
;;;   k        - Number of neighbors to return (fixnum, default: 10)
;;
;;; Returns: Vector of up to k hnsw-node structs, sorted by distance
;;;          (closest first). Vector is empty if no nodes in index.
;;
;;; Algorithm Details:
;;;   The HNSW search procedure:
;;;   1. Start at entry-point node, set current layer to max-level
;;;   2. Perform greedy descent at current layer:
;;;      a. Examine all neighbors of current node
;;;      b. Move to closest neighbor if it improves distance
;;;      c. Otherwise, mark current position and descend to next layer
;;;   3. Collect all nodes visited during descent as candidates
;;;   4. After reaching layer 0, sort candidates by distance
;;;   5. Return top-k from sorted candidates, respecting ef-search limit
;;
;;;   The ef-search parameter controls how many candidates are maintained
;;;   during search. Larger ef values improve accuracy at the cost of speed.
;;;   Typical values: 10-100 depending on accuracy requirements.
;;;
;;; Performance: O(log N) expected per query with proper ef parameter.
;;; The search time is largely independent of dataset size due to the
;;; multi-layer graph structure and greedy descent navigation.
;;;
;;; Note: Uses global parameters *ef-search*, *M*, and the index's
;;; metric-fn. Results are approximate; exact NN would require linear scan.

;;; ============================================================================
;;; hnsw-insert (original definition)
;;; ============================================================================
;;;
;;; Insert a node into the HNSW graph.
;;;
;;; Algorithm (High-level steps):
;;;   1. Generate random layer level for the new node via random-level
;;;   2. Create node struct with vector, id, level, and empty neighbor lists
;;;   2. Insert node into hash table by ID
;;;   4. Set entry-point if this is the first node
;;;   5. For each level from top to node's level:
;;;      - Search current layer to find insertion point
;;;      - Connect new node to M nearest neighbors at this level
;;;      - Update existing neighbors' connections to include new node
;;
;;; Arguments:
;;;   index    - hnw-index struct (must be from create-hnsw-index)
;;;   vector   - Feature vector (simple-array single-float, dimension dim)
;;;   id       - Unique node identifier (fixnum or hashable type)
;;
;;; Returns: NIL (modifies index in-place)
;;
;;; Algorithm Details:
;;;   The full HNSW insertion involves navigational steps:
;;;   1. Start at entry-point, perform greedy descent to layer 0
;;;   2. At each level l from top to 0:
;;;      - Examine node's neighbors at level l
;;;      - Find the closest neighbor to the new vector
;;;      - Add new node as neighbor, prune to maintain *M* connections
;;;      - Update existing neighbors' neighbor lists to include new node
;;;
;;;   The connect-neighbors function handles the detailed neighbor list
;;;   updates, ensuring that both the new node and existing nodes have
;;;   consistent neighbor references at each level.
;;;
;;; Performance: O(log N) expected for insertion with proper pruning.
;;; The dominant cost is the layer-by-layer navigation and neighbor list
;;; updates. Insertion time grows slowly with dataset size due to the
;;; logarithmic graph depth.
;;;
;;; Note: The function uses global parameters *M*, *ef-construction*, and
;;; *max-level*. All must be set appropriately before insertion operations.

;;; ============================================================================
;;; hnsw-search (original definition)
;;; ============================================================================
;;;
;;; Find k nearest neighbors using HNSW greedy descent search.
;;;
;;; Algorithm:
;;;   1. Set ef to *ef-search* for candidate collection
;;;   2. Search the HNSW layer structure starting from entry-point
;;;   3. Collect all candidates within the ef search boundary
;;;   4. Sort candidates by distance to query vector
;;;   6. Return top-k results (or fewer if fewer than k nodes exist)
;;
;;; Arguments:
;;;   index    - hnw-index struct (must be initialized with nodes)
;;;   vector   - Query vector (simple-array single-float, dimension dim)
;;;   k        - Number of neighbors to return (fixnum, default: 10)
;;
;;; Returns: Vector of up to k hnsw-node structs, sorted by distance
;;;          (closest first). Vector is empty if no nodes in index.
;;
;;; Algorithm Details:
;;;   The HNSW search procedure:
;;;   1. Start at entry-point node, set current layer to max-level
;;;   2. Perform greedy descent at current layer:
;;;      a. Examine all neighbors of current node
;;;      b. Move to closest neighbor if it improves distance
;;;      c. Otherwise, mark current position and descend to next layer
;;;   3. Collect all nodes visited during descent as candidates
;;;   4. After reaching layer 0, sort candidates by distance
;;;   5. Return top-k from sorted candidates, respecting ef-search limit
;;
;;;   The ef-search parameter controls how many candidates are maintained
;;;   during search. Larger ef values improve accuracy at the cost of speed.
;;;   Typical values: 10-100 depending on accuracy requirements.
;;;
;;; Performance: O(log N) expected per query with proper ef parameter.
;;; The search time is largely independent of dataset size due to the
;;; multi-layer graph structure and greedy descent navigation.
;;;
;;; Note: Uses global parameters *ef-search*, *M*, and the index's
;;; metric-fn. Results are approximate; exact NN would require linear scan.

(provide :hnsw-spike)