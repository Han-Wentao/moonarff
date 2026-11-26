#!/usr/bin/env python3
"""Independent strict Weka date oracle; synthetic cases, no upstream code copied.
Run scripts/weka_interop.py first to populate the checksum-verified test JAR.
"""
import sys, json, subprocess, tempfile, shutil, os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
JAR=Path.home()/'.cache/moonarff-tests/weka-3.8.6.jar'
import hashlib
assert hashlib.sha256(JAR.read_bytes()).hexdigest() == '932ea2f342b58fe45736389e9c426d5b5955e610d1f5f6485117f532068915e9'
CASES=[]
def add(p, values):
    CASES.extend((p,v) for v in values)
add('yyyy-MM-dd z',['2024-01-01 PDT','2024-07-01 PST','1940-01-01 PST','1900-01-01 PST','2024-01-01 IST','2024-07-01 IST','2024-01-01 CET','2024-07-01 CET','2024-01-01 CEST','2024-07-01 CEST'])
for p,vs in [('w',['1','2','53','0']),('Y',['2024','2023']),('E',['Mon','Sun']),('u',['1','7']),('W',['0','1','2','5']),('F',['1','2','5']),('yyyy-MM-W-u',['2024-02-1-7','2024-02-0-7','2024-02-5-4']),('yyyy-MM-F-u',['2024-02-1-7','2024-02-5-4','1582-10-3-1']),('yyyy-MM-dd E',['2024-02-29 Fri','2024-02-29 Thu']),('yyyy-MM-dd u',['2024-02-29 5','2024-02-29 4']),('yyyy-MM-dd D',['2024-02-29 061','2024-02-29 060']),('yyyy-DDD-MM-dd',['2024-061-02-29','2024-060-02-29']),('yyyy-MM-dd w u',['2024-01-08 2 1','2024-01-08 3 1']),('yyyy-MM-dd HH kk',['2024-02-29 1 12','2024-02-29 12 12']),('yyyy-MM-dd HH hh a',['2024-02-29 13 01 PM','2024-02-29 13 02 PM']),('G yyyy-MM-dd',['BC 0001-01-01','BC 9999-01-01']),('yyyy-MM-dd G',['0001-01-01 BC','9999-01-01 BC'])]:add(p,vs)
# Exhaust finite combinations around week-year and Gregorian cutover.
for p in ['yyyy-w-u','YYYY-w-u','yyyy-MM-W-u','yyyy-MM-F-u']:
    for year in [1582,1969,1970,2020,2023,2024]:
        for week in [1,2,5,52,53]:
            for dow in [1,7]:
                s=('%d-%d-%d'%(year,week,dow)) if p in ['yyyy-w-u','YYYY-w-u'] else ('%d-10-%d-%d'%(year,week,dow))
                add(p,[s])
# Every W/F selector and explicit-day validation across the cutover month.
for pattern, values in [
    ('yyyy-MM-W', ['1582-10-%d' % n for n in range(0,7)]),
    ('yyyy-MM-F', ['1582-10-%d' % n for n in range(0,7)]),
    ('yyyy-MM-dd-W', ['1582-10-%02d-%d' % (d,n) for d in [1,4,15,17,18,21,31] for n in range(0,7)]),
    ('yyyy-MM-dd-F', ['1582-10-%02d-%d' % (d,n) for d in [1,4,15,17,18,21,31] for n in range(0,7)]),
    ('yyyy-MM-W-u', ['1582-10-%d-%d' % (n,u) for n in range(0,7) for u in range(1,8)]),
    ('yyyy-MM-F-u', ['1582-10-%d-%d' % (n,u) for n in range(0,7) for u in range(1,8)]),
    ('yyyy-MM-dd-W-u', ['1582-10-%02d-%d-%d' % (d,n,u) for d in [1,4,15,17,18,21,31] for n in range(0,7) for u in range(1,8)]),
    ('yyyy-MM-dd-F-u', ['1582-10-%02d-%d-%d' % (d,n,u) for d in [1,4,15,17,18,21,31] for n in range(0,7) for u in range(1,8)]),
]: add(pattern, values)
for field in ['W', 'F']:
    for n in range(0,7):
        for dow in range(1,8):
            add('yyyy-MM-'+field+'-u', ['1582-10-%d-%d' % (n,dow)])
    for day in [1,4,15,17,18,21,31]:
        for n in [1,2,3,4]:
            add('yyyy-MM-dd '+field, ['1582-10-%02d %d' % (day,n)])
for day in [1,4,15,17,18,21,31]:
    for dow in range(1,8):
        add('yyyy-MM-dd u', ['1582-10-%02d %d' % (day,dow)])
for year in [1,1582,1969,2024,280000]:
    for era in ['AD','BC']:
        add('yyyy-MM-dd G HH:mm:ss.SSS', ['%04d-01-01 %s 12:34:56.789' % (year,era)])
# Exact IEEE-754 integer endpoints remain representable, including +/-2^53.
add('yyyy-MM-dd G HH:mm:ss.SSS', [
    '283452-01-16 BC 15:00:59.008',
    '283452-01-16 BC 15:00:59.009',
    '287396-10-12 AD 08:59:00.991',
    '287396-10-12 AD 08:59:00.992',
    '292269055-12-02 BC 16:47:04.192',
    '285190822-08-22 BC 08:00:00.000',
    '285200616-07-24 AD 16:00:00.000',
    '292278994-08-17 AD 07:12:55.806',
])
# Java 17 DecimalFormat numeric parsing uses Character.digit(char, 10).
# Exercise every BMP decimal digit block independently against Weka.
for zero in [
    0x0030,0x0660,0x06F0,0x07C0,0x0966,0x09E6,0x0A66,0x0AE6,
    0x0B66,0x0BE6,0x0C66,0x0D66,0x0E50,0x0ED0,0x0F20,0x1040,
    0x1090,0x17E0,0x1810,0x1946,0x19D0,0x1A80,0x1A90,0x1B50,
    0x1BB0,0x1C40,0x1C50,0xA620,0xA8D0,0xA900,0xA9D0,0xA9F0,
    0xAA50,0xABF0,0xFF10,
]:
    digits=''.join(chr(zero+n) for n in range(10))
    add('yyyy-MM-dd',[digits[2]+digits[0]+digits[2]+digits[4]+'-'+digits[0]+digits[2]+'-'+digits[2]+digits[9]])
add("ww'x'yHH G-H", ['09x202412 AD-12'])
add('yyyy-MM-dd HH:mm:ss.SSS',[
    '2024-02-29 -0:-0:-0.-0',
    '2024-02-29 佟佗:伲伽:佶佴.侑侉侃',
])
# Cross-field SimpleDateFormat tokenization: every calendar year/month/day width
# family and 12/24-hour clock family is exercised in real date patterns.
for year_field,year_value in [('y','2024'),('yy','24'),('yyyy','2024'),('yyyyy','02024')]:
    for month_field,month_value in [('M','2'),('MM','02'),('MMM','Feb'),('MMMM','February'),('L','2'),('LLL','Feb'),('LLLL','February')]:
        for day_field,day_value in [('d','29'),('dd','29')]:
            pattern=year_field+'-'+month_field+'-'+day_field
            value=year_value+'-'+month_value+'-'+day_value
            add(pattern,[value])
            add(year_field+month_field+day_field,[year_value+month_value+day_value])
for hour_field,hour_value in [('H','23'),('HH','23'),('k','23'),('h','11'),('hh','11'),('K','11')]:
    for minute_field,minute_value in [('m','5'),('mm','05')]:
        for second_field,second_value in [('s','6'),('ss','06')]:
            for millis_field,millis_value in [('S','7'),('SSS','007')]:
                pattern='yyyy-MM-dd '+hour_field+':'+minute_field+':'+second_field+'.'+millis_field
                value='2024-02-29 '+hour_value+':'+minute_value+':'+second_value+'.'+millis_value
                add(pattern,[value])
# Valid field-width and text forms across every implemented SimpleDateFormat field.
for field, values in {
    'y':['1','12','99','100','1582','2024','9999'], 'yy':['01','12','69','99'],
    'yyyy':['0001','1582','2024','9999'], 'Y':['1','2020','2021','2024'], 'YY':['01','20','24'],
    'w':['1','2','52','53'], 'ww':['01','02','52','53'], 'W':['1','2','4','5'], 'F':['1','2','4','5'],
    'M':['1','2','10','12'], 'MM':['01','02','10','12'], 'MMM':['Jan','Feb','Oct','Dec'],
    'MMMM':['January','February','October','December'], 'L':['1','10','12'], 'LLL':['Jan','Oct','Dec'],
    'LLLL':['January','October','December'], 'd':['1','2','28','29','31'], 'dd':['01','02','28','29','31'],
    'D':['1','32','365','366'], 'DDD':['001','032','365','366'], 'E':['Mon','Thu','Sunday'],
    'EEEE':['Monday','Thursday','Sunday'], 'u':['1','4','7'], 'a':['AM','PM'], 'H':['0','1','12','23'],
    'HH':['00','01','12','23'], 'k':['1','12','24'], 'kk':['01','12','24'], 'K':['0','1','11'],
    'KK':['00','01','11'], 'h':['1','2','12'], 'hh':['01','02','12'], 'm':['0','1','59'],
    'mm':['00','01','59'], 's':['0','1','59'], 'ss':['00','01','59'], 'S':['0','1','9'],
    'SSS':['000','001','999'], 'G':['AD','BC'], 'z':['UTC','PST','Pacific Standard Time'],
    'Z':['+0000','+0800','-0500'], 'X':['Z','+08','-05'], 'XX':['Z','+0800','-0500'],
    'XXX':['Z','+08:00','-05:00'],
}.items():
    for value in values: add(field,[value])
for pattern, value in [
    ("yyyy-MM-dd'T'HH:mm:ss.SSS",'2024-02-29T23:59:58.007'),
    ('yyyy-DDD HH:mm:ss.SSS','2024-060 12:34:56.789'),
    ('YYYY-ww-u HH:mm:ss','2020-53-5 06:07:08'),
    ('yyyy-MM-W-u HH:mm:ss','2024-02-2-4 06:07:08'),
    ('yyyy-MM-F-u HH:mm:ss','2024-02-5-4 06:07:08'),
    ('yyyy-MM-dd EEEE a hh:mm:ss.SSS z','2024-02-29 Thursday PM 11:59:58.007 UTC'),
    ("G yyyy MMMM dd'T'HH:mm:ss.SSS XXX",'BC 0001 January 01T00:00:00.001 Z'),
]: add(pattern,[value])
# Deterministic calendar envelope boundary sweep across the supported range.
# Weka supplies independent accept/reject and epoch-millisecond expectations.
for year in [1, 4, 100, 400, 1500, 1582, 1583, 1600, 1700, 1800, 1900, 1969, 1970, 2000, 2038, 2100, 2400, 9999, 10000, 50000, 100000, 200000, 280000, 285000, 285420, 285426, 299999, 300000, 1000000, 5000000]:
    for month, day in [(1,1),(2,28),(3,1),(6,15),(9,30),(12,31)]:
        for era in ['AD','BC']:
            add('yyyy-MM-dd G', [f'{year:06d}-{month:02d}-{day:02d} {era}'])
# Pairwise SimpleDateFormat calendar-field precedence matrix. Exercise both
# token orders with valid values and conflicting field-family values so stamp
# ordering differences remain visible to the independent Weka oracle.
from itertools import combinations
field_values = {
    'Y': ('2024', '2023'), 'y': ('2024', '2023'), 'D': ('060', '061'),
    'd': ('29', '28'), 'W': ('5', '4'), 'F': ('5', '4'),
    'M': ('02', '10'), 'w': ('9', '8'), 'u': ('4', '5'),
    'E': ('Thu', 'Fri'), 'H': ('13', '12'),
    'h': ('01', '02'), 'a': ('PM', 'AM'),
}
for left, right in combinations(field_values, 2):
    for first, second in ((left, right), (right, left)):
        add(first+' '+second, [field_values[first][0]+' '+field_values[second][0],
                               field_values[first][1]+' '+field_values[second][1]])
# Three-field permutations expose precedence interactions that pairwise tests
# cannot observe (e.g. date-vs-week selectors combined with weekday stamps).
from itertools import permutations
triple_fields = ['y', 'Y', 'M', 'd', 'D', 'w', 'u']
for fields in combinations(triple_fields, 3):
    for order in permutations(fields):
        pattern=' '.join(order)
        add(pattern, [' '.join(field_values[f][0] for f in order),
                      ' '.join(field_values[f][1] for f in order)])
with tempfile.TemporaryDirectory(prefix='arff-probe-') as tmp:
    work=Path(tmp)
    src='''import java.util.*;import java.io.*;import weka.core.Attribute;public class Probe{public static void main(String[] a)throws Exception{TimeZone.setDefault(TimeZone.getTimeZone(\"UTC\"));Locale.setDefault(Locale.US);BufferedReader r=new BufferedReader(new InputStreamReader(System.in,\"UTF-8\"));String line;while((line=r.readLine())!=null){String[] c=line.split(\"\\\\t\",2);try{Attribute at=new Attribute(\"d\",c[0]);System.out.println((long)(double)at.parseDate(c[1]));}catch(Exception e){System.out.println(\"ERROR\");}}}}'''
    (work/'Probe.java').write_text(src,encoding='utf8')
    subprocess.run(['javac','-cp',str(JAR),str(work/'Probe.java')],check=True)
    payload=''.join(p+'\t'+v+'\n' for p,v in CASES)
    j=subprocess.run(['java','-cp',str(work)+os.pathsep+str(JAR),'Probe'],input=payload,text=True,encoding='utf8',check=True,stdout=subprocess.PIPE).stdout.splitlines()
    target=work/'moon'; target.mkdir()
    for item in ROOT.iterdir():
        if item.name.startswith('.') or item.name in ('_build','target','scripts'):continue
        if item.is_dir():shutil.copytree(item,target/item.name)
        else:shutil.copy2(item,target/item.name)
    dr=target/'probe';dr.mkdir()
    (dr/'moon.pkg').write_text('import { "Han-Wentao/moonarff" @arff }\noptions("is-main":true)\n')
    m='fn main {\n'
    for p,s in CASES:
        m+='try { println(@arff.parse_date('+json.dumps(s)+','+json.dumps(p)+').to_int64()) } catch { _ => println("ERROR") }\n'
    m+='}\n';(dr/'main.mbt').write_text(m)
    r=subprocess.run([os.environ.get('MOON','moon'),'run','probe','--target',os.environ.get('ORACLE_TARGET','js'),'--deny-warn'],cwd=target,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if r.returncode:raise RuntimeError(r.stderr.decode(errors='replace'))
    moon=r.stdout.decode().splitlines()
    assert len(moon)==len(j)==len(CASES),(len(moon),len(j),len(CASES))
    diffs=[]
    for c,a,b in zip(CASES,j,moon):
        if a!=b:diffs.append((c,a,b))
    assert not diffs, json.dumps(diffs,indent=2)
    print('PASS: %d independent Java 17 / Weka 3.8.6 date accept/reject and Double-backed epoch probes' % len(CASES))
