# Changelog

## 0.2.2 — 2026-11-25

- Update the pinned MoonBit toolchain to moonc 0.10.22 and migrate sources/interfaces to its current formatter and generated API format.
- Add regression coverage for date overflow rejection, leap-year day-of-year bounds, Gregorian cutover, and dense/sparse/stream reader paths.
- Keep the complete Weka compatibility gaps explicit; this maintenance release does not claim full format compatibility.

## 0.2.1 — 2026-11-16

- Expand Date patterns with English month and weekday names, day-of-year, AM/PM, and 12/24-hour fields; reject inconsistent calendar fields.
- Accept both full and abbreviated English date names independently of output width, parse variable-width numbers before text fields, and reject ambiguous mixed-clock patterns.
- Run Weka date interoperability checks with an explicit English Java locale and add bidirectional fixtures for the expanded patterns.
- Clarify that complete Weka ARFF and date-semantic compatibility remains the project goal; publish exact supported and unsupported date fields.
- Add a compatibility matrix with observable completion criteria for outstanding date and other format semantics; keep those gaps within the project goal.

## 0.2.0 — 2026-11-13

- Add Date attributes and UTC epoch-millisecond values, numeric Java date patterns and GregorianCalendar cutover behavior; reject invalid dates and lossy date output.
- Add nested Relational schemas and values, empty/missing distinction, shared depth/attribute/row/cell limits and schema-aware dense/sparse output.
- Add finite instance weights to dense/sparse and nested records; transformations deep-copy relations and preserve weights.
- Add bounded chunk-fed StreamReader, strict incremental UTF-8 decoding, synchronous row callbacks and immediate StreamWriter sinks; failures are terminal.
- Add real Weka 3.8.6 Java full/incremental and bidirectional semantic tests; retain LIAC-ARFF regression coverage. Add streaming and multi-instance workflows and CI reproduction.
- Breaking change: programmatically constructed Record requires weight (normally 1.0). Public enums add Date/Relational variants. Feature encoding rejects non-unit weights to prevent silent loss. Profiles remain explicitly unweighted.

## 0.1.0

- Initial typed dense/sparse ARFF interchange with finite numbers, explicit missing values and source diagnostics.
- Bounded input, decoded tokens, expanded cells, feature matrices and output accumulation.
- Independent schema snapshots, projection, slicing, simultaneous rename, nominal recode and explicit domain union.
- Numeric/nominal/text profiles; declared-domain feature plans, masked encoding, strict decoding and CSV dictionaries.
- Three runnable workflows, adversarial regression tests and LIAC-ARFF differential checks.
