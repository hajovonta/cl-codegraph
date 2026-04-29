# cl-codegraph

Automatic Knowledge Graph of Common Lisp code via live image introspection.

Given a package loaded in the SBCL image, builds an Ariadne graph of its exported symbols, class hierarchies, method specializations, and call relationships — all without parsing source code.

## Usage

```lisp
(ql:quickload :cl-codegraph)

;; Build a graph of any loaded package
(defparameter *g* (cl-codegraph:build-graph :ariadne))

;; Query it with SPARQL or Ariadne's query DSL
(ariadne:query *g* '(select (?fn ?callee)
                     (where (?fn "cg:calls" ?callee))))

;; Rebuild after code changes
(cl-codegraph:rebuild-graph *g* :ariadne)
```

## Dependencies

- [Ariadne](https://github.com/...) — Graph database
- SBCL with `sb-introspect`
