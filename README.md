# cl-codegraph

Automatic Knowledge Graph of Common Lisp code via live image introspection.

Given a package loaded in the SBCL image, builds and maintains an Ariadne graph of its symbols, class hierarchies, method specializations, call relationships, and metadata — all without parsing source code. Includes a live Emacs integration that shows code intelligence as you navigate.

## Quick Start

```lisp
;; In the REPL:
(ql:quickload :cl-codegraph)
```

```elisp
;; In Emacs:
(add-to-list 'load-path "~/quicklisp/local-projects/cl-codegraph/emacs/")
(require 'cl-codegraph)
(cl-codegraph-enable-globally)
```

That's it. Open any CL source file, move your cursor — the `*codegraph*` buffer appears showing type, args, docstring, callers, callees, and value for the symbol at point. Everything is automatic: package detection, graph building, and incremental updates.

## Emacs Integration

The `*codegraph*` buffer is a live code intelligence panel:

- **Automatic** — detects package from `(in-package ...)`, auto-monitors on first access
- **Live** — updates as you move cursor (debounced, async, non-blocking)
- **Navigable** — RET on a caller/callee jumps to its source AND updates the view
- **History** — `l` goes back (browser-style), `q` closes
- **Per-method** — GFs show each method's specializers and individual callees

### Keybindings in `*codegraph*`

| Key | Action |
|-----|--------|
| RET | Visit symbol: jump to source + update view |
| l | Go back in history |
| q | Close window |

## Programmatic API

```lisp
;; Build a graph manually
(defparameter *g* (cl-codegraph:build-graph :my-package :include-internal t))

;; Query helpers
(cl-codegraph:what-calls *g* "pkg:fn")          ;; what does it call?
(cl-codegraph:who-calls-p *g* "pkg:fn")         ;; who calls it?
(cl-codegraph:call-chain *g* "pkg:a" "pkg:b")   ;; path from A to B
(cl-codegraph:dead-exports *g*)                  ;; exported but never called
(cl-codegraph:undocumented-exports *g*)          ;; missing docstrings
(cl-codegraph:find-cycles *g*)                   ;; circular dependencies
(cl-codegraph:impact-of *g* "pkg:fn")           ;; what breaks if I change this?
(cl-codegraph:fan-in *g* "pkg:fn")              ;; how many call it
(cl-codegraph:fan-out *g* "pkg:fn")             ;; how many it calls
(cl-codegraph:unused-packages *g* :my-package)  ;; unused use-list entries

;; Visualization
(cl-codegraph:export-dot *g* :predicates '("cg:calls"))
(cl-codegraph:neighborhood *g* "pkg:fn" :depth 2)

;; Change detection
(cl-codegraph:diff-summary *before* *after*)
(cl-codegraph:refresh-graph *g* :my-package :include-internal t)

;; Live monitoring (used automatically by Emacs integration)
(cl-codegraph:monitor :my-package :include-internal t)
(cl-codegraph:graph :my-package)  ;; always current — flushes dirty symbols
(cl-codegraph:unmonitor :my-package)

;; Multi-package
(cl-codegraph:build-multi-graph '(:pkg-a :pkg-b))
(cl-codegraph:build-system-graph :my-system)

;; REPL
(format t "~A" (cl-codegraph:describe-symbol *g* "pkg:fn"))
(format t "~A" (cl-codegraph:summary *g*))
```

## Graph Model

| Predicate | Meaning |
|-----------|---------|
| `rdf:type` | Symbol kind: function, generic-function, class, macro, constant, special-variable |
| `cg:inPackage` | Symbol → package |
| `cg:exports` | Package → symbol |
| `cg:internal` | "true" for non-exported symbols |
| `cg:calls` | Function/method → function it calls |
| `cg:calledBy` | Function → function that calls it |
| `cg:subclassOf` | Class → superclass |
| `cg:hasSlot` | Class → slot |
| `cg:methodOf` | Method → generic function |
| `cg:specializesOn` | Method → class it specializes on |
| `cg:dependsOn` | Package → external package |
| `cg:lambdaList` | Function → parameter list string |
| `cg:docstring` | Symbol → documentation string |
| `cg:sourceFile` | Symbol → source file path |
| `cg:value` | Constant/variable → current value |
| `cg:expandsMacro` | Function → macro it expands |
| `cg:readsVar` | Function → variable/constant it reads |
| `cg:writesVar` | Function → variable it writes |
| `cg:external` | "true" for cross-package callees |

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
- **Live updates**: `sb-int:*setf-fdefinition-hook*` + encapsulated `%defvar`/`%defparameter`/`load-defclass`

## Dependencies

- [Ariadne](https://sr.ht/~hajovonta/ariadne/) — Graph database (in-process)
- [Glue](https://melpa.org/#/glue) — Emacs ↔ CL transport (Slime/Sly)
- SBCL with `sb-introspect` and `sb-pcl`
