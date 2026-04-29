(defpackage #:cl-codegraph
  (:use #:cl)
  (:export
   ;; Core API
   #:build-graph
   #:rebuild-graph
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
   #:+depends-on+))
