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
with tempfile.TemporaryDirectory(prefix='arff-probe-') as tmp:
    work=Path(tmp)
    args=',\n'.join('{'+json.dumps(p)+','+json.dumps(s)+'}' for p,s in CASES)
    src='''import java.util.*;import weka.core.Attribute;public class Probe{public static void main(String[] a)throws Exception{TimeZone.setDefault(TimeZone.getTimeZone("UTC"));Locale.setDefault(Locale.US);String[][] cases={CASES};for(String[] c:cases){try{Attribute at=new Attribute("d",c[0]);System.out.println((long)at.parseDate(c[1]));}catch(Exception e){System.out.println("ERROR");}}}}'''.replace('CASES',args)
    (work/'Probe.java').write_text(src,encoding='utf8')
    subprocess.run(['javac','-cp',str(JAR),str(work/'Probe.java')],check=True)
    j=subprocess.check_output(['java','-cp',str(work)+os.pathsep+str(JAR),'Probe']).decode().splitlines()
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
    print('PASS: %d independent Java 17 / Weka 3.8.6 date accept/reject and epoch probes' % len(CASES))
