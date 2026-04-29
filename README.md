# cl-codegraph

Automatic Knowledge Graph of Common Lisp code via live image introspection.

Given a package loaded in the SBCL image, builds an Ariadne graph of its symbols, class hierarchies, method specializations, call relationships, and metadata — all without parsing source code.

## Usage

```lisp
(ql:quickload :cl-codegraph)

;; Build a graph of any loaded package (exports only)
(defparameter *g* (cl-codegraph:build-graph :my-package))

;; Include internal (non-exported) symbols for full call chains
(defparameter *g* (cl-codegraph:build-graph :my-package :include-internal t))

;; Include cross-package dependencies
(defparameter *g* (cl-codegraph:build-graph :my-package :include-external-calls t))

;; Query helpers
(cl-codegraph:what-calls *g* "my-package:some-fn")       ;; what does it call?
(cl-codegraph:who-calls-p *g* "my-package:some-fn")      ;; who calls it?
(cl-codegraph:call-chain *g* "pkg:entry" "pkg:target")   ;; path from A to B
(cl-codegraph:dead-exports *g*)                          ;; exported but never called
(cl-codegraph:undocumented-exports *g*)                  ;; missing docstrings

;; Rebuild after code changes
(cl-codegraph:rebuild-graph *g* :my-package :include-internal t)

;; Use SPARQL or Ariadne's query DSL directly
(ariadne:query *g* '(select (?fn ?callee)
                     (where (?fn "cg:calls" ?callee))))
```

## Graph Model

| Predicate | Meaning |
|-----------|---------|
| `rdf:type` | Symbol kind: function, generic-function, class, macro, constant, special-variable |
| `cg:inPackage` | Symbol → package |
| `cg:exports` | Package → symbol |
| `cg:internal` | "true" for non-exported symbols |
| `cg:external` | "true" for cross-package callees |
| `cg:calls` | Function → function it calls |
| `cg:calledBy` | Function → function that calls it |
| `cg:subclassOf` | Class → superclass |
| `cg:hasSlot` | Class → slot |
| `cg:methodOf` | Method → generic function |
| `cg:specializesOn` | Method → class it specializes on |
| `cg:dependsOn` | Package → external package |
| `cg:lambdaList` | Function → parameter list string |
| `cg:docstring` | Symbol → documentation string |
| `cg:sourceFile` | Symbol → source file path |
| `cg:expandsMacro` | Function → macro it expands |
| `cg:readsVar` | Function → special variable it reads |
| `cg:writesVar` | Function → special variable it writes |

## How It Works

No source parsing. All data comes from the live SBCL image:

- **Symbol enumeration**: `do-external-symbols` / `do-symbols`
- **Call graph**: `sb-introspect:find-function-callees` (forward, O(n))
- **GF method bodies**: `sb-pcl::safe-method-fast-function` pierces the PCL trampoline
- **Signatures**: `sb-introspect:function-lambda-list`
- **Source locations**: `sb-introspect:find-definition-sources-by-name`
- **Macro usage**: `sb-introspect:who-macroexpands`
- **Variable deps**: `sb-introspect:who-references` / `who-sets`
- **Class structure**: MOP (`class-direct-superclasses`, `class-direct-slots`)

## Dependencies

- [Ariadne](~/quicklisp/local-projects/ariadne/) — Graph database
- SBCL with `sb-introspect` and `sb-pcl`
