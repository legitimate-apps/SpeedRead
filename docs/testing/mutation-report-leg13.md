# Mutation gate report

Coverage says a line ran. This says an assertion would have NOTICED if it were wrong.

Run 2026-09-04 01:33 · 6 mutations · 6 killed · 0 survived (0 of them expected) · 0 not counted · **0 unexpected**

Every verdict in this table was measured by this run.

| mutation | verdict | expected | measured | note |
|---|---|---|---|---|
| Annotations: bookmark order reverses (position ascending -> descending) | **KILLED** | KILLED | this run | suite failed, as it should |
| Annotations: highlight order reverses (start ascending -> descending) | **KILLED** | KILLED | this run | suite failed, as it should |
| Annotations: position label drops the 1-based offset | **KILLED** | KILLED | this run | suite failed, as it should |
| Annotations: range label en-dash becomes a hyphen | **KILLED** | KILLED | this run | suite failed, as it should |
| Annotations: range label end index loses its 1-based offset | **KILLED** | KILLED | this run | suite failed, as it should |
| Annotations: bookmark deletion returns offsets in reverse order | **KILLED** | KILLED | this run | suite failed, as it should |
