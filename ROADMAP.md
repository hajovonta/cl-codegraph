# cl-codegraph Roadmap

## Done

- [x] Symbol classification (function, generic, class, macro, constant, special-variable)
- [x] Package membership and exports
- [x] Class hierarchy (subclassOf, hasSlot)
- [x] Generic function structure (methodOf, specializesOn)
- [x] Call graph via `find-function-callees` (forward, O(n))
- [x] GF method call graph via `sb-pcl::safe-method-fast-function`
- [x] Cross-package call analysis (:include-external-calls)
- [x] Internal symbol indexing (:include-internal)
- [x] Lambda lists / signatures
- [x] Docstrings
- [x] Source file locations
- [x] Macro expansion tracking (expandsMacro)
- [x] Special variable/constant read/write tracking (readsVar, writesVar)
- [x] Variable/constant values (cg:value)
- [x] Query: what-calls / who-calls-p
- [x] Query: dead-exports (exported but never called)
- [x] Query: undocumented-exports
- [x] Query: unused-packages
- [x] Query: call-chain (BFS path from A to B)
- [x] Query: find-cycles (circular call detection)
- [x] Query: impact-of (transitive callers — what breaks if X changes?)
- [x] Query: fan-in / fan-out (connectivity metrics)
- [x] Visualization: export-dot with predicate filtering
- [x] Visualization: neighborhood subgraph extraction
- [x] Diff: compare graph snapshots (added/removed triples)
- [x] Diff: refresh-graph with change reporting
- [x] Multi-package: build-multi-graph (unified graph across packages)
- [x] Multi-package: build-system-graph (ASDF system)
- [x] REPL: describe-symbol (type, args, value, doc, calls, callers, references)
- [x] REPL: summary (graph overview with counts)
- [x] Live monitoring: per-symbol dirty tracking via SBCL hooks
- [x] Live monitoring: hooks for defun/defmacro/defmethod/defvar/defparameter/defclass
- [x] Live monitoring: auto-monitor on first access (ensure-monitor)
- [x] Emacs: live *codegraph* side buffer with idle-timer updates
- [x] Emacs: auto-detect buffer package from (in-package) form
- [x] Emacs: interactive navigation (RET to visit, l to go back)
- [x] Emacs: jump to source definition in source window
- [x] Emacs: clickable callers/callees/references/methods/classes as links
- [x] Emacs: enable-globally for all Lisp buffers
- [x] Emacs: :: fallback for internal symbol lookup
- [x] Emacs: method URI navigation (shows per-method callees/specializers)
- [x] Emacs: class details (superclasses, subclasses, slots, specializing methods)
- [x] Emacs: local variable context (parameters, let/dolist/dotimes bindings with value forms)
- [x] Emacs: graceful handling of unloaded packages

## Next

### Emacs UI
- [ ] Transient menu in *codegraph* buffer for aggregate queries:
  - call-chain (prompt for target, show path)
  - impact-of (what breaks if I change this?)
  - find-cycles (show circular dependencies)
  - dead-exports / undocumented-exports
  - unused-packages
  - diff-summary (what changed since last build?)

### Visualization
- [ ] Interactive web-based graph viewer via Ariadne's Cytoscape.js (browse call graphs, filter by edge type, click to explore)

### Code Intelligence
- [x] Per-method call edges — show callers/callees per GF method specialization
- [x] Local variable context — show binding form, enclosing function, value expression for let/dolist/dotimes/multiple-value-bind/destructuring-bind
- [ ] Loop variable context — detect `loop for x ...` bindings

### KG-Specific Value (beyond Slime)
- [ ] Architecture validation via SHACL shapes on code structure
- [ ] CI integration — detect cycles/dead code/missing docs in PRs
- [ ] Graph persistence — save/load/compare across sessions
- [ ] Architectural drift tracking over time

## Design Decisions

- **Forward call graph only**: `find-function-callees` + `safe-method-fast-function` gives O(n) performance. No `who-calls` reverse scanning needed.
- **String URIs**: `package:symbol` (exported) or `package::symbol` (internal). Readable, queryable via SPARQL.
- **Lazy updates**: SBCL hooks mark symbols dirty; re-indexing happens on next query. Zero cost when not querying.
- **Auto-monitor**: Packages are monitored automatically on first access with `:include-internal t`.
- **SBCL-specific**: Uses `sb-introspect` and `sb-pcl` internals. Not portable to other implementations.
