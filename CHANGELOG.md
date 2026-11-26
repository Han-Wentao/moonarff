## 0.2.3 — 2026-11-26

- Match strict Weka timezone normalization across 618 English names and historical/modern transitions; compare all 31500 broad date, clock, boundary and repeated-zone probes against Java 17.0.2 / Weka 3.8.6. Pin CI to the exact Java oracle runtime and add regression cases for historical offsets, transition gaps, explicit daylight labels, and rejected overlaps.

- Correct Gregorian cutover week-field validation to match Weka strict parsing for W/F selectors and explicit weekdays; ensure date formatting rejects text that cannot be parsed back without timestamp loss.
- Replace the prior non-empty-only cutover assertion with exact W/F field outputs, strict-parser acceptance/rejection, and public formatter losslessness checks.
- Expand the independent Java 17 / Weka 3.8.6 date oracle to 1,400 deterministic accept/reject and epoch probes, including W/F combinations with and without explicit day/weekday fields.

- Match SimpleDateFormat minimum-width semantics for repeated numeric date fields and variable-width standalone numeric fields; add fixed-width adjacent parsing regressions.
- Expand independent Weka 3.8.6 coverage to 159 source inputs, 159 Weka-written inputs, and 636 dense/sparse exports; derive written-input expectations by reparsing Weka’s actual serialized text.
- Match Weka numeric parsing for NaN/missing, infinities and weights, Java floating suffixes, hexadecimal floats, surrounding whitespace, and exponent overflow/underflow.
- Match Java SimpleDateFormat's rolling 80-year interpretation for two-digit `y`/`Y` values, comparing the complete candidate instant against the pivot boundary.
- Freeze the pivot at Reader/StreamReader creation so one data set cannot change interpretation while streaming.
- Resolve Weka sparse String/Relational dictionary-index-zero references during full parsing; preserve explicit unresolved references in immediate streaming callbacks and add a public post-stream resolver that returns copied rows after later dictionary values are known.
- Match Weka 24-hour `H`/`k` and repeated-field precedence; add exact IEEE-754 bit regressions for hexadecimal normal/subnormal boundaries and decimal edge values.
- Document remaining compatibility limits against the 159-case independent Weka matrix.
- Extend Java date-pattern handling with week/calendar field defaults, suffix parsing, repeated zone fields, English timezone names and exact-millisecond range checks; add Weka probes for these semantics.
- Extend the independent Weka matrix to 187 input fixtures, 187 Weka-written inputs and 748 dense/sparse exports. Remaining locale/zone edge cases and lenient normalization are still explicit gaps.

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
