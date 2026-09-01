# Mutation gate report

Coverage says a line ran. This says an assertion would have NOTICED if it were wrong.

Run 2026-09-01 16:22 · 6 mutations · 4 killed · 1 survived (0 of them expected) · 1 not counted · **2 unexpected**

Every verdict in this table was measured by this run.

| mutation | verdict | expected | measured | note |
|---|---|---|---|---|
| OPDSBrowseLogic: search encoding character set path -> query | **SURVIVED** ⚠️ | KILLED | this run | suite still green — nothing pins this |
| OPDSBrowseLogic: fallback search path duplicates the OPDS component | **KILLED** | KILLED | this run | suite failed, as it should |
| BrowseServerLogic: automatic-selection count 1 -> 2 | **KILLED** | KILLED | this run | suite failed, as it should |
| ServerEditLogic: DEFAULT ARGUMENT stops reading the production credential store | **KILLED** | KILLED | this run | suite failed, as it should |
| ServerEditLogic: sort-index time unit seconds -> kiloseconds | **KILLED** | KILLED | this run | suite failed, as it should |
| ServerEditLogic: DEFAULT ARGUMENT generates an empty temporary keychain tag | **INVALID** ⚠️ | KILLED | this run | no test ever executed — a build failure is not a kill |

## Unexpected outcomes

- **OPDSBrowseLogic: search encoding character set path -> query** — got SURVIVED, expected KILLED. suite still green — nothing pins this
- **ServerEditLogic: DEFAULT ARGUMENT generates an empty temporary keychain tag** — got INVALID, expected KILLED. no test ever executed — a build failure is not a kill
