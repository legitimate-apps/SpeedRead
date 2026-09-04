# Mutation gate report

Coverage says a line ran. This says an assertion would have NOTICED if it were wrong.

Run 2026-09-04 18:25 · 7 mutations · 7 killed · 0 survived (0 of them expected) · 0 not counted · **0 unexpected**

Every verdict in this table was measured by this run.

| mutation | verdict | expected | measured | note |
|---|---|---|---|---|
| review: asks on the 2nd launch instead of the 3rd | **KILLED** | KILLED | this run | suite failed, as it should |
| review: off-by-one lets the stored count grow past the cap | **KILLED** | KILLED | this run | suite failed, as it should |
| review: this launch counts as two | **KILLED** | KILLED | this run | suite failed, as it should |
| review: process gate admits every appearance but the first | **KILLED** | KILLED | this run | suite failed, as it should |
| formats: readable and unreadable swap sides | **KILLED** | KILLED | this run | suite failed, as it should |
| formats: duplicate badge names stop collapsing | **KILLED** | KILLED | this run | suite failed, as it should |
| formats: support link points at the wrong page | **KILLED** | KILLED | this run | suite failed, as it should |
