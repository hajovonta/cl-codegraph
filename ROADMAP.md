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

## Next

### Diff / Change Detection
- [ ] Snapshot comparison — what symbols/edges were added/removed between two builds
- [ ] Integration with git — rebuild after commit, diff against previous

### Multi-Package Graphs
- [ ] Build a unified graph spanning multiple packages (e.g., an entire ASDF system)
- [ ] ASDF system dependency edges (system → system)

### Visualization
- [ ] Export to Graphviz via Ariadne's export-dot
- [ ] Call graph subgraph extraction (neighborhood of a symbol)

### Live Development Dashboard
- [ ] Hook into SBCL definition hooks to auto-rebuild graph on code changes
- [ ] Dedicated Emacs window showing relevant subgraphs (neighborhood of current function)
- [ ] Auto-update visualization as the user navigates/edits code
- [ ] Track graph evolution over a session — what changed since last rebuild

### Incremental Updates
- [ ] Hook into SBCL definition hooks for live graph updates during development
- [ ] Selective rebuild (only re-index changed symbols)

### REPL Integration
- [ ] Pretty-printed query results for interactive use
- [ ] Slime/Sly integration for "show me the graph around this symbol"

### Additional Queries
- [ ] Circular call detection
- [ ] "Impact analysis" — what breaks if I change this function?
- [ ] Complexity metrics (fan-in, fan-out per symbol)

## Design Decisions

- **Forward call graph only**: `find-function-callees` + `safe-method-fast-function` gives O(n) performance. No `who-calls` reverse scanning needed.
- **String URIs**: `package:symbol` (exported) or `package::symbol` (internal). Readable, queryable via SPARQL.
- **Rebuild-on-demand**: No hooks yet. Explicit `rebuild-graph` keeps things predictable.
- **SBCL-specific**: Uses `sb-introspect` and `sb-pcl` internals. Not portable to other implementations.
