## 0.2.8 — 2026-11-27

- 升级至 `moonc 1.0.0-rc1+3c0520448` / `moon 0.1.20261126`，同步最低工具链要求、中文安装说明与当前发布版本。
- CI 固定官方 RC1 工具链，新增实际编译器版本断言，保留四后端检查/构建及测试、示例和独立 Weka/LIAC 互操作验证。
- 不改变公开 API 或 ARFF 格式兼容范围；保留现有日期模式、地区和时区边界说明。

## 0.2.7 — 2026-11-26

- 更正 README 与兼容矩阵中的当前发布版本及安装示例，使之指向 0.2.7；0.2.7 不包含新的格式语义变更，保留 0.2.6 的日期修复与其兼容边界。

## 0.2.6 — 2026-11-26

- 修复 Weka 严格日期语义：`Y`、`D` 与 `W/F` 的组合此前可能被错误接受，且年内日序未检查年周首周约束；增加字段排列差分用例，Java 17 / Weka 3.8.6 对照扩展至 2,901 个日期探针。
- 更新中文 README 与兼容矩阵，使版本状态、示例安装版本及日期支持边界与实际交付一致。

## [Unreleased]

- Match strict Weka calendar selection when week-of-year supersedes an implicit month while still validating explicit week-of-month fields; reject AD-era dates whose selected week resolves into BC. Add exact Weka regression cases and reduce 1,600 seeded 1969 formatter-to-parser comparisons to zero differences.

- Match Weka week-year precedence when `Y`/`w` resolves a date: lower-priority month and day fields no longer spuriously reject a valid week date; lock this behavior with Weka-derived regression cases.
- Expand the independent Java 17 / Weka 3.8.6 date oracle to 2,858 deterministic field-order and accept/reject/epoch probes.

- Align mixed 12/24-hour and day-of-year/day-of-month resolution with Weka 3.8.6 pattern-order semantics; expand independent date/calendar field-order probes.

- Extend Gregorian date conversion through Java Date signed-long millisecond boundaries using 64-bit day arithmetic while retaining Weka-compatible IEEE-754 storage and Java saturation at Long.MAX_VALUE.
- Expand the independent Java 17 / Weka date oracle to 2,677 parse/epoch probes including AD/BC, Java long millisecond boundaries, and pairwise calendar-field ordering patterns; pin exact formatter outputs at Long.MIN_VALUE, adjacent Double values, and the saturating positive endpoint.

- Match Weka inclusive exact IEEE-754 millisecond endpoints (`-2^53` and `2^53`) for date parsing and formatting; add strict Java 17/Weka 3.8.6 boundary and valid-pattern probes.
- Clarify strict date parsing and quoted-token escape behavior against Weka 3.8.6; record only verified compatibility boundaries.

## 0.2.4 — 2026-11-26

- Correct release-state references in the README and compatibility matrix: 0.2.3 is published; preserve the explicitly documented remaining Weka compatibility limits.

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
