;;; HNSW Spike - Core Algorithms
;;; HNSW (Hierarchical Navigable Small World) graph algorithms
;;;
;;; Algorithm Reference:
;;;   Malkov and Yashunsky (2016) "Efficient and robust approximate nearest
;;;   neighbor search using Hierarchical Navigable Small World graphs"

(in-package :hnsw-spike)

;;; ============================================================================
;;; create-hnsw-index
;;; ============================================================================
(defun create-hnsw-index (dim &key (metric :cosine))
  "Create and return a new empty HNSW index."
  (let ((metric-fn (case metric (:cosine #'hnsw-spike:cosine-distance)
                             (:l2 #'hnsw-spike:l2-distance)
                             (:dot #'hnsw-spike:dot-distance)
                             (t (error "Unknown metric: ~A" metric)))))
    (make-hnsw-index :dim dim
                     :metric-fn metric-fn
                     :nodes (make-hash-table)
                     :entry-point nil
                     :max-level 0)))

;;; ============================================================================
;;; random-level
;;; ============================================================================
(defun random-level (max-level)
  "Generate random HNSW layer assignment for a new node."
  (check-type max-level fixnum)
  (let ((level 0))
    (loop while (< (random 1.0) 0.5) do (incf level))
    (min level max-level)))

;;; ============================================================================
;;; search-layer
;;; ============================================================================
(defun search-layer (index query-vec ef &optional (result-so-far nil))
  "Search a single HNSW layer for up to ef candidates near the query vector.
Returns (candidates . best-distance) where candidates is a list of node IDs."
    (declare (type hnsw-index index)
             (type (simple-array single-float) query-vec)
             (type fixnum ef)
             (ignore ef result-so-far))
  (let ((candidates (make-hash-table :test 'equalp))
        (best-distance most-positive-single-float)
        (current-node (gethash (hnsw-index-entry-point index) (hnsw-index-nodes index) ))
        (dist-fn (hnsw-index-metric-fn index)))
    (when current-node
      (let* ((current-vector (hnsw-node-vector current-node))
            (start-dist (funcall dist-fn current-vector query-vec)))
        (setf (gethash (hnsw-node-id current-node) candidates) start-dist)
        (when (< start-dist best-distance)
              (setf best-distance start-dist))
            
                ;; Greedy descent: at each step, examine all neighbors at this level
        (loop while current-node
          do (let ((current-vector (hnsw-node-vector current-node))
                   (neighbors (get-neighbors current-node (hnsw-node-level current-node) index)))
               (when neighbors
                (loop for n-id in neighbors do
                  (let ((n (gethash n-id (hnsw-index-nodes index))))
                    (when n
                      (let* ((n-vector (hnsw-node-vector n))
                             (current-distance (funcall dist-fn n-vector query-vec)))
                        (when (and (not (gethash n-id candidates))
                                    (< current-distance best-distance))
                          (setf (gethash n-id candidates) current-distance
                                best-distance current-distance))))))
                                
                ;; Move to best neighbor for next iteration
                (let ((best-node (get-best-neighbor current-node query-vec index dist-fn)))
                  (if best-node
                      (setf current-node best-node)
                      (setf current-node nil))))))

      ;; Return sorted candidates by distance (closest first)
      (let ((sorted (sort (loop for id being the hash-values of candidates
                                collect (list id (gethash id candidates)))
                        #'< :key #'car)))
        (values sorted best-distance))))))

;;; ============================================================================
;;; get-neighbors
;;; ============================================================================

(defun get-neighbors (node level index)
  "Get neighbor node IDs of NODE at LEVEL. Returns list of node IDs or nil is none is found."
  (if (and node (< level (array-dimension (hnsw-node-neighbors node) 0)))
    (aref (hnsw-node-neighbors node) level)
    nil))

;;; ============================================================================
;;; get-best-neighbor
;;; ============================================================================

(defun get-best-neighbor (node query-vec index dist-fn)
  "Get the best (closest) neighbor node of NODE for a given query vector."
    (declare (type hnsw-node node)
             (type (simple-array single-float) query-vec)
             (type hnsw-index index))
  (let* ((neighbors (get-neighbors node
                                    (hnsw-node-level node)
                                    index))
         (best-node nil)
         (best-dist most-positive-single-float))
    (when neighbors
      (dolist (n-id neighbors)
        (let ((n (gethash n-id (hnsw-index-nodes index))))
          (when n
            (let ((d (funcall dist-fn query-vec (hnsw-node-vector n))))
              (when (< d best-dist)
                (setf best-dist d best-node n)))))))
    best-node))

;;; ============================================================================
;;; search-layer-for-insert
;;; ============================================================================

(defun search-layer-for-insert (index query-vec entry-id level metric-fn)
  "Search a layer for insertion. Returns list of (distance . node-id) sorted by distance."
    (declare (type hnsw-index index)
            (type (simple-array single-float) query-vec)
            (type fixnum entry-id level))
  (let ((candidates (list entry-id))
        (visited (make-hash-table)))
    (setf (gethash entry-id visited) t)
    (loop while candidates do
      (let ((current-id (pop candidates)))
        (let ((node (gethash current-id (hnsw-index-nodes index))))
          (when node
            ;; Add neighbors to candidate list


            (let ((neighbors (get-neighbors node level index)))
              (dolist (n-id neighbors)
                (unless (gethash n-id visited)
                  (setf (gethash n-id visited) t)
                  (push n-id candidates)))))))

    ;; Return all visited node IDs sorted by distance
    (let ((result (loop for node-id being the hash-keys of visited
                        with node = (gethash node-id (hnsw-index-nodes index))
                        when node
                        collect (list (funcall metric-fn (hnsw-node-vector node) query-vec) node-id))))
        
        (sort result #'< :key #'first)))))

;;; ============================================================================
;;; greedy-descent
;;; ============================================================================
(defun greedy-descent (index query-vec current-id level metric-fn visited)
  "Perform greedy descent at a single layer. Returns the best neighbor ID found."
    (declare (type hnsw-index index)
             (type (simple-array single-float) query-vec)
             (type fixnum current-id level)
             (type hash-table visited))
  (let ((best-id current-id)
        (best-dist (when current-id
                     (let ((node (gethash current-id (hnsw-index-nodes index))))
                       (when node
                         (funcall metric-fn (hnsw-node-vector node) query-vec))))))
    (when best-dist
      (loop while current-id do
        (let ((neighbors (get-neighbors current-id level index)))
          (let ((improved-id nil)
                (improved-dist best-dist))
            (dolist (n-id neighbors)
              (unless (gethash n-id visited)
                (setf (gethash n-id visited) t)
                (let ((n (gethash n-id (hnsw-index-nodes index))))
                  (when n
                    (let ((ndist (funcall metric-fn (hnsw-node-vector n) query-vec)))
                      (when (< ndist improved-dist)
                        (setf improved-id n-id improved-dist ndist)))))))
            (if improved-id
                (setf current-id improved-id best-dist improved-dist)
                (return))))))
    best-id))

;;; ============================================================================
;;; hnsw-insert
;;; ============================================================================
(defun hnsw-insert (index vector id)
  "Insert a node into the HNSW graph and return its ID."
  (declare (type hnsw-index index)
           (type (simple-array single-float) vector)
           (type fixnum id))

  (let* ((max-lvl (max 0 (hnsw-index-max-level index)))
         (node-level (random-level max-lvl))
         (neighbors-vec (make-array (1+ node-level) :initial-element nil))
         (node (make-hnsw-node :id id
                               :vector vector
                               :level node-level
                               :neighbors neighbors-vec)))
    ;; Add {id => node} to the index hash table
    (setf (gethash id (hnsw-index-nodes index)) node)
    
    ;; Set entry-point if first node (store the NODE, not just the ID)
    (unless (hnsw-index-entry-point index)
      (setf (hnsw-index-entry-point index) id
            (gethash id (hnsw-index-nodes index)) node))
    
    ;; Update max-level
    ;; FIXME: 
    ;;   - this is probably useless since node-level = (random-level (hnsw-index-max-level index))
    (when (> node-level (hnsw-index-max-level index))
      (setf (hnsw-index-max-level index) node-level))
    
    ;; For each level from current max down to node level, connect neighbors
    (let ((metric-fn (hnsw-index-metric-fn index))
          (entry-id (hnsw-index-entry-point index)))

      (loop for level from (hnsw-index-max-level index) downto 0 do
        (when (>= level node-level)
          ;; Search this layer for nearest neighbors
          (let ((candidates (search-layer-for-insert index vector entry-id level metric-fn)))
            (when candidates
              (let ((top-candidates (subseq candidates 0 (min (length candidates) *M*))))
                ;; Add neighbors to new node (using IDs)
                (setf (aref neighbors-vec level) (mapcar #'second top-candidates))
                
                ;; Add new node as neighbor to each existing neighbor
                (dolist (n-id (mapcar #'second top-candidates))
                  (let ((n (gethash n-id (hnsw-index-nodes index))))
                    (when n
                      (when (<= (array-dimension (hnsw-node-neighbors n) 0) level)
                        (adjust-array (hnsw-node-neighbors n) (1+ level) :initial-element nil))
                      (unless (member id (aref (hnsw-node-neighbors n) level))
                        (push id (aref (hnsw-node-neighbors n) level)))))))))))
    
    ;; Update entry point if this node is at the highest level (store NODE)
    (when (= node-level (hnsw-index-max-level index))
      (setf (gethash (hnsw-index-entry-point index) (hnsw-index-nodes index)) node))
    id)))

;;; ============================================================================
;;; hnsw-search
;;; ============================================================================
(defun hnsw-search (index query-vec k &key (ef *ef-search*))
  (declare (type hnsw-index index)
           (type (simple-array single-float) query-vec)
           (type fixnum k ef)
           (ignore ef))

  "Find k nearest neighbors using HNSW greedy descent search. Returns list of node IDs."
  (let* ((metric-fn (hnsw-index-metric-fn index))
         (entry-id (hnsw-index-entry-point index))
         (nodes-ht (hnsw-index-nodes index))
         (entry (gethash entry-id nodes-ht))
         (max-level (hnsw-index-max-level index))
         (result '())
         (visited (make-hash-table)))
    (when (or (null entry) (zerop (hash-table-count (hnsw-index-nodes index))))
      (return-from hnsw-search nil))
    
    ;; Phase 1: Greedy descent from max-level to level 1
    (loop for level from max-level downto 1 do
      (setf entry (greedy-descent index query-vec (hnsw-node-id entry) level metric-fn visited)))
    
    ;; Phase 2: Best-first search at level 0 with ef candidate limit
    (when entry
      (let* ((entry-node entry)
             (entry-dist (funcall metric-fn (hnsw-node-vector entry-node) query-vec))
             (candidates (list (list entry-dist entry-node)))
             (best (list (list entry-dist entry-node))))
        (setf (gethash (hnsw-node-id entry) visited) t)
        
        (loop while candidates do
          (let ((cdist (caar candidates)))
            (when (> cdist (caar (last best)))
              (return))
            (pop candidates)
            (let* ((node (cadar candidates))
                   (neighbors (get-neighbors node 0 index)))
              ;; Explore neighbors
              (dolist (n-id neighbors)
                (unless (gethash n-id visited)
                  (setf (gethash n-id visited) t)
                  (let* ((n (gethash n-id (hnsw-index-nodes index)))
                         (ndist (funcall metric-fn (hnsw-node-vector n) query-vec)))
                    (when (< ndist (caar (last best)))
                      (push (list ndist n) best)
                      (push (list ndist n) candidates))))))))
        
        ;; Sort by distance, return top k
        (let ((sorted (sort best #'< :key #'first)))
          (loop for i from 0 below (min k (length sorted))
                collect (second (nth i sorted))))))))

;; EOF
