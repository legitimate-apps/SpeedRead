# Mutation gate report

Coverage says a line ran. This says an assertion would have NOTICED if it were wrong.

Run 2026-09-04 02:42 · 7 mutations · 6 killed · 0 survived (0 of them expected) · 1 not counted · **1 unexpected**

Every verdict in this table was measured by this run.

| mutation | verdict | expected | measured | note |
|---|---|---|---|---|
| Formats: ensureExtension reverts to 'any extension counts' (the original bug) | **KILLED** | KILLED | this run | suite failed, as it should |
| Formats: selection guard checks only the upper bound (negative index) | **KILLED** | KILLED | this run | suite failed, as it should |
| Formats: empty filename+title yields a bare dotfile again | **KILLED** | KILLED | this run | suite failed, as it should |
| Formats: path separators in a title are no longer sanitised | **KILLED** | KILLED | this run | suite failed, as it should |
| Formats: .text stops resolving to plain text | **KILLED** | KILLED | this run | suite failed, as it should |
| Formats: text/rtf stops resolving to rich text | **KILLED** | KILLED | this run | suite failed, as it should |
| Formats: extension matching becomes case-sensitive | **INVALID** ⚠️ | KILLED | this run | no test ever executed — a build failure is not a kill |

## Unexpected outcomes

- **Formats: extension matching becomes case-sensitive** — got INVALID, expected KILLED. no test ever executed — a build failure is not a kill
