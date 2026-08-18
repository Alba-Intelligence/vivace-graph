#!/usr/bin/env sbcl --noinform --non-interactive
(load "spikes/hnsw-perf.lisp")
(run-benchmark)
(terpri)
(terpri)
(princ "SUCCESS")
(terpri)
(quit)