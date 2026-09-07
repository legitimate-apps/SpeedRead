# Pre-completion SwiftData fixture

`PreCompletion.store` was generated on iOS 26.5 using the shipping Book, Bookmark,
and Highlight models before Book gained `finishedAt` (leg 24, 2026-09-06).
It contains two synthetic books, one chapter, one bookmark, and one highlight.
The SQLite ZBOOK table has no ZFINISHEDAT column. SQLite's backup API consolidated
its WAL into this standalone fixture; tests copy it before opening/migrating it.

`BookCompletionTests.preCompletionLibraryMigratesWithoutLosingContent` opens it
with the current app schema and asserts content, reading markers, relationships,
and unfinished defaults. Do not regenerate this fixture with the current schema:
that would turn the migration test into a current-schema round-trip test.
