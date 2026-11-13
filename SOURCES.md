# Sources and licensing boundaries

The production implementation is independently written MoonBit under Apache-2.0.
No third-party parser code, Weka data sets, compiled artifacts or vendor copies are
included. All examples and differential fixtures are synthetic.

- Weka ARFF specification: https://ml.cms.waikato.ac.nz/weka/arff.html and
  https://waikato.github.io/weka-wiki/formats_and_processing/arff_stable/ .
  Reference for grammar, dense/sparse defaults, Date, Relational and instance weights.
  Weka's Java implementation is GPLv3; none of its implementation source is copied.
  `scripts/weka_interop.py` downloads the separate Weka 3.8.6 test JAR from Maven
  Central and checks SHA-256 932ea2f342b58fe45736389e9c426d5b5955e610d1f5f6485117f532068915e9.
  The independently written Apache-2.0 Java adapter invokes that external test
  program. Neither the JAR nor Weka source is distributed in this module;
  production code has no Weka/Java dependency.
- SciPy loadarff documentation: https://docs.scipy.org/doc/scipy/reference/generated/scipy.io.arff.loadarff.html .
  Capability comparison only; no SciPy code is included or required. SciPy is BSD-3-Clause.
- LIAC-ARFF 2.5.0: https://github.com/renatopp/liac-arff .
  MIT-licensed, installed separately only as a Python differential-test oracle.
  The installed arff.py copyright/license header and implementation were inspected
  to establish test behavior, not ported into production. Its code is not vendored.
- MoonBit core: https://github.com/moonbitlang/core , Apache-2.0.
  Uses the selected toolchain's standard string, double and debug packages; tests/examples use UTF-8 encoding.
- Java SimpleDateFormat and GregorianCalendar API documentation: numeric pattern
  semantics, epoch milliseconds and the 1582 calendar cutover. No JDK source is copied.
  https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/text/SimpleDateFormat.html
  https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/GregorianCalendar.html

AI assistance was used for design, implementation, tests and documentation. Claims
are limited to implemented behavior and recorded checks, not official acceptance.
