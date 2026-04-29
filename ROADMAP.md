# cl-codegraph Roadmap

## Done

- [x] Symbol classification (function, generic, class, macro, constant, special-variable)
- [x] Package membership and exports
- [x] Class hierarchy (subclassOf, hasSlot)
- [x] Generic function structure (methodOf, specializesOn)
- [x] Call graph via `find-function-callees`
- [x] Cross-package call analysis (:include-external-calls)
- [x] Lambda lists / signatures
- [x] Docstrings
- [x] Source file locations
- [x] Macro expansion tracking (expandsMacro)
- [x] Special variable read/write tracking (readsVar, writesVar)

## Next

### Query Helpers
- [ ] "What calls X?" / "What does X call?" convenience wrappers
- [ ] "Find dead exports" — exported but never called within the package
- [ ] "Call chain from A to B" — path query using Ariadne traversal
- [ ] "Undocumented exports" — symbols missing docstrings

### Diff / Change Detection
- [ ] Snapshot comparison — what symbols/edges were added/removed between two builds
- [ ] Integration with git — rebuild after commit, diff against previous

### Multi-Package Graphs
- [ ] Build a unified graph spanning multiple packages (e.g., an entire ASDF system)
- [ ] ASDF system dependency edges (system → system)

### Visualization
- [ ] Export to Graphviz via Ariadne's export-dot
- [ ] Call graph subgraph extraction (neighborhood of a symbol)

### Incremental Updates
- [ ] Hook into SBCL definition hooks for live graph updates during development
- [ ] Selective rebuild (only re-index changed symbols)

### REPL Integration
- [ ] Pretty-printed query results for interactive use
- [ ] Slime/Sly integration for "show me the graph around this symbol"

## Design Decisions

- **Forward call graph only**: `find-function-callees` gives us O(n) performance.
  `who-calls` (reverse) is used only for macro/variable xrefs where the set is small.
- **Exported symbols only**: Internal symbols are implementation details.
  Could be added as an option later.
- **Rebuild-on-demand**: No hooks yet. Explicit `rebuild-graph` keeps things predictable.
- **String URIs**: `package:symbol` format. Simple, readable, queryable via SPARQL.
