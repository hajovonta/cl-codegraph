# cl-codegraph

Automatic Knowledge Graph of Common Lisp code via live image introspection.

Given a package loaded in the SBCL image, builds and maintains an Ariadne graph of its symbols, class hierarchies, method specializations, call relationships, and metadata — all without parsing source code. Includes a live Emacs integration that shows code intelligence as you navigate.

## Getting Started

### 1. Install

Clone into your Quicklisp local-projects:

```bash
cd ~/quicklisp/local-projects/
git clone https://git.sr.ht/~hajovonta/cl-codegraph
git clone https://git.sr.ht/~hajovonta/ariadne
```

### 2. Emacs setup

Add to your init file:

```elisp
(add-to-list 'load-path "~/quicklisp/local-projects/cl-codegraph/emacs/")
(require 'cl-codegraph)
(cl-codegraph-enable-globally)  ;; activates in all lisp-mode buffers
```

Or, to enable per-buffer instead: `M-x codegraph-mode` in any Lisp buffer.

Requires [glue](https://melpa.org/#/glue) (available on MELPA).

### 3. Load in SBCL

Start your Lisp image and load your project as usual, then:

```lisp
(ql:quickload :cl-codegraph)
```

That's it. No further setup needed — everything else is automatic.

### 4. Use

1. Open any CL source file in Emacs
2. Move your cursor to a symbol — the `*codegraph*` buffer appears showing type, args, docstring, callers, callees
3. Click (RET) on any symbol in `*codegraph*` to jump to its source and update the view
4. Press `?` for aggregate queries (dead exports, cycles, impact analysis, call chains)
5. Press `v` to visualize in the Graph Explorer web UI (auto-starts at http://localhost:8080/)

Package detection, graph building, monitoring, and incremental updates all happen automatically on first access.

### Configuration

```elisp
;; Adjust idle delay before updating (default: 0.3s)
(setq cl-codegraph-idle-delay 0.5)

;; Change Graph Explorer port (default: 8080)
(setq cl-codegraph-explorer-port 9090)
```

If you prefer to start the web server manually (e.g., different port, or before first `v`):

```lisp
(ariadne:start-web-server :port 9090)
```

## Emacs Integration

The `*codegraph*` buffer is a live code intelligence panel:

- **Automatic** — detects package from `(in-package ...)`, auto-monitors on first access
- **Live** — updates as you move cursor (debounced, async, non-blocking)
- **Navigable** — RET on a caller/callee jumps to its source AND updates the view
- **History** — `l` goes back (browser-style), `q` closes
- **Per-method** — GFs show each method's specializers and individual callees
- **Classes** — shows superclasses, subclasses, slots, specializing methods
- **Local variables** — falls back to source walking for let/dolist/dotimes bindings
- **Transient menu** — `?` for aggregate queries (dead exports, cycles, impact, call-chain, etc.)
- **Smart completion** — bare names when unique, qualified when ambiguous

### Keybindings in `*codegraph*`

| Key | Action |
|-----|--------|
| RET | Visit symbol: jump to source + update view |
| l | Go back in history |
| v | Visualize in Graph Explorer (auto-starts web server) |
| ? | Transient menu (aggregate queries) |
| q | Close window |

### Graph Explorer

Press `v` in the `*codegraph*` buffer to visualize the current symbol or query result in Ariadne's web-based Graph Explorer. On first use, the web server starts automatically at `http://localhost:8080/`.

- **Symbol view**: focuses the explorer on the node with depth-1 neighborhood
- **Impact result**: sends a SPARQL query showing all impacted call edges
- **Call chain**: sends the chain as a subgraph query

Monitored graphs are automatically registered in the Explorer's graph selector dropdown.

```elisp
;; Change the explorer port (default: 8080)
(setq cl-codegraph-explorer-port 9090)
```

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

;; Large packages (>200 symbols) are indexed in a background thread.
;; monitor returns immediately; aggregate queries work once indexing completes.
(setf cl-codegraph:*background-index-threshold* 500)  ;; tune if needed

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
