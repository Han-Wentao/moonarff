#!/usr/bin/env python3
"""Broad independent Weka/Java oracle for every checked-in English date-zone label.

Requires Java 17.0.2 and checksum-verified Weka 3.8.6 from date_semantics.py.
The oracle invokes Attribute.parseDate (SimpleDateFormat Locale.US) and compares
accept/reject plus epoch milliseconds to the MoonBit public API on JS or wasm-gc.
"""
import datetime, hashlib, json, os, re, shutil, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JAR = Path.home() / '.cache/moonarff-tests/weka-3.8.6.jar'
EXPECTED_SHA256 = '932ea2f342b58fe45736389e9c426d5b5955e610d1f5f6485117f532068915e9'
assert hashlib.sha256(JAR.read_bytes()).hexdigest() == EXPECTED_SHA256, 'Weka oracle JAR checksum mismatch'

# Keep dates independent of the production offset table: include pre-epoch
# historical standard time, post-war changes, modern standard/daylight seasons,
# both US DST transition days, and calendar year boundaries.
DATES = [
    '0001-01-01', '1582-10-15', '1800-01-01', '1880-07-01', '1900-01-01',
    '1940-01-01', '1940-07-01', '1969-12-31', '1970-01-01',
    '2000-01-01', '2024-01-01', '2024-03-10', '2024-03-11',
    '2024-07-01', '2024-11-03', '2024-11-04', '9999-12-31',
]
source = (ROOT / 'date_zone.mbt').read_text(encoding='utf-8')
# Parse source declarations (not a second maintained alias list).
names = re.findall(r'^\s*\(("(?:\\.|[^"\\])*")\s*,\s*-?\d+\s*,\s*\d+\s*,\s*"(?:\\.|[^"\\])*"\s*,\s*\d+\),\s*$', source, re.M)
names = list(dict.fromkeys(json.loads(x) for x in names))
assert len(names) >= 600, f'Expected complete generated name table, found only {len(names)} names'
CASES = [('yyyy-MM-dd z', d + ' ' + n) for n in names for d in DATES]
# Historical discontinuities must be tested at noon as well as midnight:
# strict GregorianCalendar rechecks raw offsets at the resulting UTC instant.
BOUNDARY_DATES = [
    '1900-08-20', '1925-07-19', '1994-12-30', '1994-12-31',
    '1995-01-01', '2011-12-29', '2011-12-30', '2011-12-31',
]
CASES += [('yyyy-MM-dd HH:mm:ss.SSS z', d + ' 12:00:00.000 ' + n)
          for n in names for d in DATES + BOUNDARY_DATES]
CASES += [('yyyy-MM-dd z', d + ' ' + n) for n in names for d in BOUNDARY_DATES]
# Repeated zone fields preserve the active zone and individual Calendar stamps.
for labels in [
    ['China Standard Time', 'CST', 'CDT'],
    ['India Standard Time', 'IST'],
    ['Central European Standard Time', 'CET', 'CEST'],
    ['Singapore Standard Time', 'SGT', 'SGST'],
    ['Western European Standard Time', 'WET', 'WEST'],
    ['Apia Standard Time', 'Apia Daylight Time'],
    ['UTC', 'GMT', '+0530', 'PST', 'PDT'],
]:
    for first in labels:
        for second in labels + ['UTC', 'GMT', '+0530', 'PST', 'PDT']:
            for d in ['1900-01-01', '1940-07-01', '2024-01-01', '2024-07-01']:
                CASES.append(('yyyy-MM-dd z z', d + ' ' + first + ' ' + second))
# Explicit DST stamps can make civil-gap labels valid; raw historical changes
# still invalidate supplied clock fields. Expectations come only from Weka.
CASES += [
    ('yyyy-MM-dd HH:mm z', '2024-03-10 02:30 Pacific Standard Time'),
    ('yyyy-MM-dd HH:mm z', '2024-03-10 02:30 Pacific Daylight Time'),
    ('yyyy-MM-dd HH:mm z', '1940-07-01 00:00 Argentina Standard Time'),
    ('yyyy-MM-dd HH:mm z', '2024-03-10 00:00 Cuba Standard Time'),
]
CASES = list(dict.fromkeys(CASES))


with tempfile.TemporaryDirectory(prefix='moonarff-zone-oracle-') as td:
    work = Path(td)
    java = '''import java.util.*; import java.io.*; import weka.core.Attribute;
public class ZoneOracle { public static void main(String[] a) throws Exception {
 TimeZone.setDefault(TimeZone.getTimeZone("UTC")); Locale.setDefault(Locale.US);
 BufferedReader r = new BufferedReader(new InputStreamReader(System.in, "UTF-8")); String line;
 while ((line = r.readLine()) != null) { String[] c = line.split("\\t", 2);
  try { System.out.println((long)new Attribute("d", c[0]).parseDate(c[1])); }
  catch (Exception e) { System.out.println("ERROR"); }
 }
} }'''
    (work / 'ZoneOracle.java').write_text(java, encoding='utf-8')
    subprocess.run(['javac', '-cp', str(JAR), str(work / 'ZoneOracle.java')], check=True)
    payload = ''.join(p + '\t' + v + '\n' for p, v in CASES)
    expected = subprocess.run(['java', '-cp', str(work) + os.pathsep + str(JAR), 'ZoneOracle'],
                              input=payload, text=True, encoding='utf-8', check=True, stdout=subprocess.PIPE).stdout.splitlines()

    project = work / 'consumer'; project.mkdir()
    for item in ROOT.iterdir():
        if item.name.startswith('.') or item.name in ('_build', 'target', 'scripts', 'node_modules'):
            continue
        if item.is_dir(): shutil.copytree(item, project / item.name)
        else: shutil.copy2(item, project / item.name)
    moon = os.environ.get('MOON', 'moon')
    target = os.environ.get('ORACLE_TARGET', 'js')
    actual = []
    for batch_start in range(0, len(CASES), 800):
        batch = CASES[batch_start:batch_start + 800]
        probe = project / 'zone_probe'; probe.mkdir(exist_ok=True)
        (probe / 'moon.pkg').write_text('import { "Han-Wentao/moonarff" @arff }\noptions("is-main":true)\n', encoding='utf-8')
        lines = ['fn main {', 'let cases : Array[(String, String)] = [']
        lines.extend('(' + json.dumps(p) + ', ' + json.dumps(v, ensure_ascii=False) + '),' for p, v in batch)
        lines.extend([']', 'for (pattern, value) in cases {',
                      'try { println(@arff.parse_date(value, pattern).to_int64()) } catch { _ => println("ERROR") }',
                      '}', '}'])
        (probe / 'main.mbt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
        run = subprocess.run([moon, 'run', probe.name, '--target', target, '--deny-warn'], cwd=project,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8')
        if run.returncode:
            print(run.stderr)
            raise SystemExit(run.returncode)
        actual.extend(run.stdout.splitlines())

assert len(actual) == len(expected) == len(CASES), (len(actual), len(expected), len(CASES))
diffs = [(CASES[i], expected[i], actual[i]) for i in range(len(CASES)) if expected[i] != actual[i]]
if diffs:
    print(json.dumps({'cases': len(CASES), 'unique_names': len(names), 'mismatches': diffs[:100], 'mismatch_count': len(diffs)}, indent=2))
    raise SystemExit(1)
print(f'PASS: {len(CASES)} independent Java 17/Weka 3.8.6 probes across {len(names)} accepted names and historical/duplicate-field boundaries ({target})')
