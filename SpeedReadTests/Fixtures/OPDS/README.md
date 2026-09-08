# OPDS fixtures — captured, not authored

Every file here is a verbatim HTTP response body from a real Calibre-Web-NextGen instance.
They are **samples, not constructions**. If a test disagrees with a fixture, the fixture is
ground truth and the parser is what is wrong — never hand-edit one to make a test pass.

| File | Captured | What it is |
|---|---|---|
| `cwng-root.xml` | 2026-05-21 | `/opds` catalogue root |
| `cwng-root-2026-09-07.xml` | 2026-09-07 | the same root, 3.5 months later |
| `cwng-new.xml` | 2026-05-21 | acquisition feed |
| `cwng-search.xml` | 2026-05-21 | search response |
| `cwng-osd.xml` | 2026-05-21 | OpenSearch description (byte-identical on 2026-09-07) |
| `cwng-books-navigation.xml` | 2026-09-07 | `/opds/books`, 28 entries |
| `cwng-search-results.xml` | 2026-09-07 | a search response with **zero** results — the capture searched for the literal `{searchTerms}` placeholder, so this is the empty-result shape, which is worth having |
| `cwng-acquisition-hot.xml` | 2026-09-07 | `/opds/hot`, 42 entries with cover links |

## Why there are two roots

The catalogue grew thirteen navigation sections between the two captures — Hot Books, Top
Rated, Discover, Read Books, Currently Reading, Unread Books, Authors, Publishers,
Categories, Series, Languages, Ratings and File formats. Keeping both is the point: a single
sample shows what a server *did*, never what it *is*, and the pair is the only evidence in
this repo that the shape drifts under us.

## A sampled fixture is necessary and not sufficient

An earlier version of this file claimed `OPDSEntry.language` was never populated because the
parser matched `"language"` while the server sends `<dcterms:language>`. **That was wrong.**
`OPDSAtomParser` normalises every element name through `localOPDSName` before switching on it,
which strips any namespace prefix, so the case matches and language parses correctly. The claim
was written after grepping for the `case` and the namespace flag without reading the two lines
above the switch, and it was disproved by running a test against the unmodified parser: 59
language values across 60 entries.

The point the wrong example was reaching for still stands, so here it is with a true one. These
fixtures were sampled from a real server in May and committed, and a test has loaded them ever
since. That did not stop a real defect living in the parser the whole time: nested element text
was being dropped, so a `<summary>` containing markup returned only its final text node. Sampling
the fixture is what makes an assertion meaningful; it is not what makes someone write the
assertion. Ground truth in the repo that nothing interrogates is just a large file.
