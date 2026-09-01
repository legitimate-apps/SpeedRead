# Mutation proposals from legs 9–11

These six proposals target the decision logic extracted in legs 9–11. They are formatted for
direct review against `Scripts/mutations.json`, but are deliberately **not** added to that file and
have not been run through `Scripts/mutation-gate.py`. The gate owner retains independent selection
and verdict measurement.

The set leans toward production defaults and small constants because those have historically been
the suite's easiest decisions to execute without actually pinning.

```json
[
  {
    "file": "SpeedRead/Views/Server/OPDSBrowseLogic.swift",
    "old": "            with: query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query",
    "new": "            with: query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query",
    "label": "OPDSBrowseLogic: search encoding character set path -> query"
  },
  {
    "file": "SpeedRead/Views/Server/OPDSBrowseLogic.swift",
    "old": "            + \"/search/{searchTerms}\"",
    "new": "            + \"/opds/search/{searchTerms}\"",
    "label": "OPDSBrowseLogic: fallback search path duplicates the OPDS component"
  },
  {
    "file": "SpeedRead/Views/Server/BrowseServerLogic.swift",
    "old": "        if servers.count == 1 {",
    "new": "        if servers.count == 2 {",
    "label": "BrowseServerLogic: automatic-selection count 1 -> 2"
  },
  {
    "file": "SpeedRead/Views/Server/ServerEditLogic.swift",
    "old": "        passwordForTag: (String) -> String? = KeychainStore.password(for:)",
    "new": "        passwordForTag: (String) -> String? = { _ in nil }",
    "label": "ServerEditLogic: DEFAULT ARGUMENT stops reading the production credential store"
  },
  {
    "file": "SpeedRead/Views/Server/ServerEditLogic.swift",
    "old": "        Int(now.timeIntervalSince1970)",
    "new": "        Int(now.timeIntervalSince1970 / 1_000)",
    "label": "ServerEditLogic: sort-index time unit seconds -> kiloseconds"
  },
  {
    "file": "SpeedRead/Views/Server/ServerEditLogic.swift",
    "old": "        generatedTag: String = UUID().uuidString",
    "new": "        generatedTag: String = \"\"",
    "label": "ServerEditLogic: DEFAULT ARGUMENT generates an empty temporary keychain tag"
  }
]
```

Review notes:

- The encoding mutant needs a query containing a character on which `.urlPathAllowed` and
  `.urlQueryAllowed` differ; a spaces-only fixture can algebraically collapse both paths to the
  same encoded URL.
- The automatic-selection mutant changes only the literal count while preserving valid Swift, so
  it distinguishes tests that truly pin one-server auto-routing from tests that merely reach the
  branch.
- The clock mutant keeps ordering monotonic for many nearby timestamps. A test that checks only
  relative ordering can therefore miss it; an exact injected epoch should kill it.
- The three default-sensitive proposals must be exercised by omitting the argument. Tests that
  always inject their dependency do not compile the production choice into the assertion path.
