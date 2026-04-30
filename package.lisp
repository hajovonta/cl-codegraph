(defpackage #:cl-codegraph
  (:use #:cl)
  (:export
   ;; Core API
   #:build-graph
   #:rebuild-graph
   ;; Query helpers
   #:what-calls
   #:who-calls-p
   #:dead-exports
   #:undocumented-exports
   #:call-chain
   ;; Visualization
   #:export-dot
   #:neighborhood
   ;; Diff
   #:diff-graphs
   #:diff-summary
   ;; Multi-package
   #:build-multi-graph
   #:build-system-graph
   ;; Advanced queries
   #:find-cycles
   #:impact-of
   #:fan-in
   #:fan-out
   ;; Incremental
   #:refresh-graph
   ;; REPL
   #:describe-symbol
   #:summary
   ;; Package hygiene
   #:unused-packages
   ;; Live monitoring
   #:monitor
   #:unmonitor
   #:graph
   #:ensure-monitor
   #:describe-symbol-live
   ;; Predicates (URIs used in the graph)
   #:+type+
   #:+calls+
   #:+called-by+
   #:+subclass-of+
   #:+has-slot+
   #:+method-of+
   #:+specializes-on+
   #:+exports+
   #:+in-package+
   #:+external+
   #:+depends-on+
   #:+lambda-list+
   #:+docstring+
   #:+source-file+
   #:+expands-macro+
   #:+reads-var+
   #:+writes-var+
   #:+value+))
