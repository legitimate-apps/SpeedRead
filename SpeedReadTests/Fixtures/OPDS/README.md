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
| `cwng-acquisition-hot.xml` | 2026-09-07 | `/opds/hot`, 42 entries with cover links |

## Why there are two roots

The catalogue grew thirteen navigation sections between the two captures — Hot Books, Top
Rated, Discover, Read Books, Currently Reading, Unread Books, Authors, Publishers,
Categories, Series, Languages, Ratings and File formats. Keeping both is the point: a single
sample shows what a server *did*, never what it *is*, and the pair is the only evidence in
this repo that the shape drifts under us.

## A sampled fixture is necessary and not sufficient

`cwng-new.xml` contains `<dcterms:language>` 59 times and has since May. `OPDSAtomParser`
sets `shouldProcessNamespaces = false`, so its delegate receives the qualified element name
and its `case "language"` never matches — `OPDSEntry.language` has been nil in production
the whole time. A test loads this very fixture and passed throughout.

So the ground truth was already here, already correct, already being read. What was missing
was a test that asked the question. Sampling the fixture stops you asserting against
something you invented; it does not, on its own, make anyone look.
