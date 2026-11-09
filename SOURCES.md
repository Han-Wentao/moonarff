# Sources and licensing boundaries

The production implementation is independently written MoonBit under Apache-2.0.
No third-party parser code, Weka data sets, compiled artifacts or vendor copies are
included. All examples and differential fixtures are synthetic.

- Weka ARFF specification: https://ml.cms.waikato.ac.nz/weka/arff.html and
  https://waikato.github.io/weka-wiki/formats_and_processing/arff_stable/ .
  Reference for grammar, dense/sparse defaults and unsupported date/relational scope.
  Weka's Java implementation is GPL; none of its source is copied or linked.
- SciPy loadarff documentation: https://docs.scipy.org/doc/scipy/reference/generated/scipy.io.arff.loadarff.html .
  Capability comparison only; no SciPy code is included or required. SciPy is BSD-3-Clause.
- LIAC-ARFF 2.5.0: https://github.com/renatopp/liac-arff .
  MIT-licensed, installed separately only as a Python differential-test oracle.
  The installed arff.py copyright/license header and implementation were inspected
  to establish test behavior, not ported into production. Its code is not vendored.
- MoonBit core: https://github.com/moonbitlang/core , Apache-2.0.
  Uses the selected toolchain's standard string, double and debug packages.

AI assistance was used for design, implementation, tests and documentation. Claims
are limited to implemented behavior and recorded checks, not official acceptance.
