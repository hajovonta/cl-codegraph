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
- [x] Special variable read/write tracking (readsVar, writesVar)
- [x] Query: what-calls / who-calls-p
- [x] Query: dead-exports (exported but never called)
- [x] Query: undocumented-exports
- [x] Query: call-chain (BFS path from A to B)
- [x] Query: find-cycles (circular call detection)
- [x] Query: impact-of (transitive callers — what breaks if X changes?)
- [x] Query: fan-in / fan-out (connectivity metrics)
- [x] Visualization: export-dot with predicate filtering
- [x] Visualization: neighborhood subgraph extraction
- [x] Diff: compare graph snapshots (added/removed triples)
- [x] Multi-package: build-multi-graph (unified graph across packages)
- [x] Multi-package: build-system-graph (ASDF system)

- [x] REPL: describe-symbol (formatted symbol overview)
- [x] REPL: summary (graph overview with counts)

## Next

### Live Development Dashboard
- [ ] Hook into SBCL definition hooks to auto-rebuild graph on code changes
- [ ] Dedicated Emacs window showing relevant subgraphs (neighborhood of current function)
- [ ] Auto-update visualization as the user navigates/edits code
- [ ] Track graph evolution over a session — what changed since last rebuild

### Incremental Updates
- [x] refresh-graph: rebuild in-place with change reporting (:added N :removed M)
- [ ] Selective rebuild (only re-index changed symbols based on source timestamps)
- [ ] Detect which symbols were recompiled and update edges

### Additional Queries
- [x] "Unused imports" — packages in use-list but no calls to their symbols
- [ ] Per-method call edges — show callers/callees per GF method specialization instead of flattened

### REPL Integration
- [x] Slime integration with live *codegraph* buffer
- [x] Interactive navigation (RET to visit, l to go back)
- [ ] Local variable context — show binding form, enclosing function, value expression for let/lambda/parameter bindings not in the graph

## Design Decisions

- **Forward call graph only**: `find-function-callees` + `safe-method-fast-function` gives O(n) performance. No `who-calls` reverse scanning needed.
- **String URIs**: `package:symbol` (exported) or `package::symbol` (internal). Readable, queryable via SPARQL.
- **Rebuild-on-demand**: No hooks yet. Explicit `rebuild-graph` keeps things predictable.
- **SBCL-specific**: Uses `sb-introspect` and `sb-pcl` internals. Not portable to other implementations.
