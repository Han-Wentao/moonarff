#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Actual Weka 3.8.6 bidirectional/epoch/streaming oracle. Java 17+, no runtime dependency.
Synthetic fixtures are generated here; no GPL implementation is copied or distributed.
WEKA_JAR may point to the checksum-pinned external test jar. Otherwise download to user cache.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SHA = '932ea2f342b58fe45736389e9c426d5b5955e610d1f5f6485117f532068915e9'
URL = 'https://repo.maven.apache.org/maven2/nz/ac/waikato/cms/weka/weka-stable/3.8.6/weka-stable-3.8.6.jar'

def quote(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + "'"

def fixtures():
    # Millisecond values independently checked as numbers, not merely strings after a round trip.
    patterns = [
        ('yyyy-MM-dd G', ['9999-01-01 BC','9999-12-31 BC','0001-01-01 BC','0044-03-15 BC','0001-12-31 BC','1970-01-01 AD','2024-02-29 AD']),
        ('yy-MM-dd', ['45-01-01','46-01-01','46-12-01','00-06-15','99-07-04']),
        ('y-MM-dd', ['46-01-01','46-12-01']),
        ("YY-'W'ww-u", ['46-W01-2','46-W49-1']),
        ('yy-MM-dd G', ['46-01-01 BC','46-12-01 BC']),
        ('yyyy-MM-dd u', ['1970-01-01 4','2024-02-29 4','2024-03-01 5']),
        ('yyyy-MM-dd z', ['2024-01-01 PST','2024-07-01 PDT','2024-01-01 Pacific Standard Time','2024-07-01 Pacific Standard Time','2024-01-01 Eastern Standard Time','2024-07-01 Eastern Standard Time','2024-07-01 GMT+08:00']),
        ('yyyy-MM-dd Z', ['1970-01-01 UTC','2024-01-01 PST','2024-07-01 +0800']),
        ('yyyy-MM-dd XXX XXX', ['1970-01-01 +08:00 Z','1970-01-01 Z +08:00']),
        ('yyyy-MM-dd', ['2024-02-29suffix','2024-02-29']),
        ('yyyy-MM-dd HH:mm:ss z', ['1970-01-01 00:00:00 GMT','1970-01-01 00:00:00 GMT+08:00','1970-01-01 00:00:00 GMT-05:30']),
        ("YYYY-'W'ww-u", ['2021-W01-5','2023-W01-7','2020-W01-3']),
        ('yyyy-MM-W-u', ['2024-01-1-1','2024-01-2-1']),
        ('yyyy-MM-F-u', ['2024-02-4-4','2024-02-5-4','2023-10-1-7']),
        ('yyyy-MM-dd', ['10000-01-01','10000-12-31','10000-02-29','99999-01-01','280000-01-01','280000-12-31','1970-01-01','1969-12-31','2000-02-29','2024-02-29','1500-01-01','1582-10-04','1582-10-15','0001-01-01','9999-12-31']),
        ("yyyy-MM-dd'T'HH:mm:ss", ['1970-01-01T00:00:00','1969-12-31T23:59:59','2026-11-13T12:34:56']),
        ("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", ['1970-01-01T08:00:00.123+08:00','1969-12-31T23:59:59.999Z','2024-02-29T01:02:03.001-05:30']),
        ('yyyyMMdd HHmmss Z', ['19700101 080000 +0800','20000229 123456 -0530']),
        ('MMM-dd-yyyy-EEEE', ['Feb-29-2024-Thursday','Jan-01-1970-Thursday','Dec-31-1969-Wednesday']),
        ('MMMM-dd-yyyy', ['February-29-2024','March-01-2000']),
        ('yyyyy-MM-dd', ['02024-02-29','00001-01-01']),
        ('yyyy-DDDD', ['2024-0060','2023-0365']),
        ("yyyy-MM-dd'T'HH:mm:ss.SSSS", ['1970-01-01T00:00:00.0001','2024-02-29T12:34:56.0123']),
        ('dMMMyyyyE', ['29February2024Thursday','1January1970Thursday']),
        ('dMMMMyyyyEEEE', ['29Feb2024Thu','1Jan1970Thu']),
        ('yyyy-DDD', ['2024-060','2023-365','2000-060']),
        ('yyyy-DDD', ['1582-278','1582-355','1581-365']),
        ('yyyy-MM-dd G', ['280000-01-01 BC','100000-12-31 BC']),
        ('yyyy-MM-dd hh:mm:ss a', ['2024-02-29 12:05:06 AM','2024-02-29 12:05:06 PM','2023-12-31 11:59:59 PM']),
        ('yyyy-MM-dd KK:mm:ss a', ['2024-02-29 00:05:06 AM','2024-02-29 00:05:06 PM','2024-02-29 11:59:59 PM']),
        ('yyyy-MM-dd kk:mm:ss', ['2024-02-29 24:05:06','2024-02-29 12:00:00']),
        ('yyyy-MM-dd HH kk', ['2024-02-29 12 1','2024-02-29 1 12']),
        ('yyyy-MM-dd HH hh a', ['2024-02-29 13 01 PM','2024-02-29 00 12 AM']),
        ('yyyy-MM-dd G G', ['0001-01-01 BC AD','0001-01-01 AD BC']),
        ('LLLL dd yyyy', ['February 29 2024','January 01 1970']),
        ('yyyy-MM-dd yyyy', ['2024-02-29 2024']),
        ('yyyy-MM-dd MM MMMM', ['2024-02-29 03 February']),
        ('yyyy-MM-dd HH mm HH', ['2024-02-29 01 02 03']),
    ]
    for n in ['S','SS','SSS']:
        patterns.append(("yyyy-MM-dd'T'HH:mm:ss."+n, ['1970-01-01T00:00:00.1','1970-01-01T00:00:00.12','1970-01-01T00:00:00.123']))
    for pattern, dates in patterns:
        for date in dates:
            yield '@relation dates\n@attribute d date '+quote(pattern)+'\n@data\n'+quote(date)+',{2.5}\n?\n'
    for i in range(30):
        nested = (str(i/8)+',yes,'+quote('中文, '+str(i))+',{0.25}\n' +
                  str(-i/4)+',no,'+quote('?')+',{-0.5}')
        yield ('@relation bags_%d\n@attribute id numeric\n@attribute bag relational\n'
               '@attribute x real\n@attribute flag {yes,no,unused}\n@attribute note string\n'
               '@end bag\n@attribute when date\n@data\n%d,%s,1970-01-01T00:00:00,{%s}\n'
               '{0 0,1 %s,2 ?}\n%d,?,?\n' % (i,i,quote(nested),str(i/4),quote(''),i+1))
    for i in range(12):
        nested = '{0 '+str(i)+',1 '+quote('nested')+'},{2}\n{0 ?,1 ?},{0}'
        double = quote(nested) + ',{0.5}\n' + quote('')
        yield ('@relation deep\n@attribute outer relational\n@attribute inner relational\n'
               '@attribute n numeric\n@attribute text string\n@end inner\n@end outer\n@data\n'+quote(double)+',{3}\n')
    yield "@relation numbers\n@attribute n numeric\n@data\n0x1.0p2\n1d\n1f\n 1 \nNaN\nInfinity\n-Infinity\n1e999\n1e-999\n1,{NaN}\n1,{Infinity}\n1,{-Infinity}\n"
    yield ('@relation hex_edges\n@attribute n numeric\n@data\n' +
           '0x1.fffffffffffffp1023\n0x1p1024\n-0x1p1024\n0x0p1024\n' +
           '0x1p-1074\n0x1p-1075\n0x1.00000000000008p0\n' +
           '0x1.00000000000018p0\n0x1.0000000000000800001p0\n')
    yield ("@relation decimal_edges\n@attribute n numeric\n@data\n" +
           "4.9E-324\n1.0000000000000004\n1.0000000000000002\n" +
           "2.2250738585072014E-308\n1.7976931348623157E308\n")
    yield "@relation strings\n@attribute s string\n@data\n{}\n{0 'later'}\n{}\n"
    yield "@relation relations\n@attribute r relational\n@attribute x numeric\n@end r\n@data\n{}\n{0 '1\\n'}\n{}\n"
    for i in range(20):
        yield ('@relation sparse\n@attribute n numeric\n@attribute d date "yyyy-MM-dd"\n'
               '@attribute c {a,b,unused}\n@data\n{},{0}\n{0 %s,1 2024-02-29,2 b},{-0.5}\n{0 ?,1 ?,2 ?},{2.5}\n' % (i/8))

DRIVER = r"""
fn same_cell(attribute : @arff.Attribute, actual : @arff.Cell, expected : @arff.Cell) -> Bool {
  match actual {
    @arff.DictionaryZero => match (attribute.kind, expected) {
      (@arff.Text, @arff.Label(_)) | (@arff.Relational(_), @arff.Relation(_)) => true
      _ => false
    }
    @arff.Relation(rows) => match (attribute.kind, expected) {
      (@arff.Relational(children), @arff.Relation(other)) => same_rows(children, rows, other)
      _ => false
    }
    _ => actual == expected
  }
}
fn same_rows(attributes : Array[@arff.Attribute], actual : Array[@arff.Record], expected : Array[@arff.Record]) -> Bool {
  if actual.length() != expected.length() { return false }
  for i, row in actual {
    if row.weight != expected[i].weight || row.values.length() != attributes.length() { return false }
    for j, cell in row.values {
      if !same_cell(attributes[j], cell, expected[i].values[j]) { return false }
    }
  }
  true
}
fn attrs(attributes : Array[@arff.Attribute]) -> Json {
  Json::array(attributes.map(fn(a) {
    let kind = match a.kind {
      @arff.Numeric => Json::string("numeric")
      @arff.Text => Json::string("string")
      @arff.Date(p) => Json::array([Json::string("date"), Json::string(p)])
      @arff.Nominal(labels) => Json::array([Json::string("nominal"), Json::array(labels.map(Json::string))])
      @arff.Relational(children) => Json::array([Json::string("relation"), attrs(children)])
    }
    Json::array([Json::string(a.name), kind])
  }))
}
fn rows(records : Array[@arff.Record]) -> Json {
  Json::array(records.map(fn(r) {
    let cells = r.values.map(fn(c) {
      match c {
        @arff.Missing => Json::null()
        @arff.Number(n) | @arff.DateValue(n) =>
          if n.is_nan() { Json::null() }
          else if n == @double.infinity { Json::string("Infinity") }
          else if n == @double.neg_infinity { Json::string("-Infinity") }
          else { Json::number(n) }
        @arff.Label(s) => Json::string(s)
        @arff.Relation(children) => rows(children)
        @arff.DictionaryZero => Json::string("__dictionary_zero__")
      }
    })
    let weight = if r.weight == @double.infinity { Json::string("Infinity") }
      else if r.weight == @double.neg_infinity { Json::string("-Infinity") }
      else { Json::number(r.weight) }
    Json::array([weight, Json::array(cells)])
  }))
}
fn main {
  let sources = [SOURCES]
  for source in sources {
    let d = @arff.parse(source) catch { _ => panic() }
    // UTF-8 single-byte chunks verify actual incremental delivery against whole input.
    let reader = @arff.StreamReader::new() catch { _ => panic() }
    let streamed : Array[@arff.Record] = []
    for byte in @utf8.encode(source) {
      reader.feed_utf8([byte], fn(row) { streamed.push(row) }) catch { _ => panic() }
    }
    reader.finish(fn(row) { streamed.push(row) }) catch { _ => panic() }
    assert_true(same_rows(d.schema.attributes, streamed, d.rows)) catch { _ => panic() }
    println("@@SEM@@")
    println(Json::array([Json::string(d.schema.relation), attrs(d.schema.attributes), rows(d.rows)]).stringify())
    for sparse in [false, true] {
      let text = StringBuilder()
      let writer = @arff.StreamWriter::new(d.schema, fn(s) { text.write_string(s) }, sparse~) catch { _ => panic() }
      for row in d.rows { writer.write(row) catch { _ => panic() } }
      writer.finish() catch { _ => panic() }
      let result = text.to_string()
      assert_eq(@arff.parse(result) catch { _ => panic() }, d) catch { _ => panic() }
      println("@@ARFF@@")
      println(result)
    }
    println("@@END@@")
  }
}
"""

def main():
    jar = Path(os.environ.get('WEKA_JAR', str(Path.home()/'.cache/moonarff-tests/weka-3.8.6.jar')))
    if not jar.exists():
        jar.parent.mkdir(parents=True,exist_ok=True)
        with urllib.request.urlopen(URL,timeout=90) as response: payload=response.read()
        if hashlib.sha256(payload).hexdigest()!=SHA: raise RuntimeError('Weka artifact checksum mismatch')
        jar.write_bytes(payload)
    if hashlib.sha256(jar.read_bytes()).hexdigest()!=SHA: raise RuntimeError('Weka artifact checksum mismatch')
    with tempfile.TemporaryDirectory(prefix='moonarff-weka-') as temp:
        work=Path(temp)
        src=work/'sources'; src.mkdir()
        cases=list(fixtures())
        for i,source in enumerate(cases): (src/('%03d.arff'%i)).write_text(source,encoding='utf-8')
        def java(source,output):
            subprocess.run(['java','-cp',str(work)+os.pathsep+str(jar),'WekaOracle',str(source),str(output)],check=True)
        subprocess.run(['javac','-encoding','UTF-8','-cp',str(jar),'-d',str(work),str(ROOT/'scripts/WekaOracle.java')],check=True)
        ref=work/'reference'; java(src,ref)
        expected=[json.loads((ref/('%03d.json'%i)).read_text(encoding='utf-8'), parse_constant=lambda value: value) for i in range(len(cases))]
        written=[(ref/('%03d.arff'%i)).read_text(encoding='utf-8') for i in range(len(cases))]
        # Instances.toString uses Weka's display precision (6 decimal places),
        # so it may round subnormals to zero and nearby doubles to one. The
        # expected semantics of a Weka-written input must come from rereading
        # that exact text with Weka, not from the pre-serialization instance.
        reread=work/'reread'; java(ref,reread)
        written_expected=[json.loads((reread/('%03d.json'%i)).read_text(encoding='utf-8'), parse_constant=lambda value: value) for i in range(len(cases))]
        expectations=expected+written_expected
        sources=cases+written
        target=work/'moon';target.mkdir()
        for item in ROOT.iterdir():
            if item.name.startswith('.') or item.name in ('_build','target','scripts'): continue
            if item.is_dir(): shutil.copytree(item,target/item.name)
            else: shutil.copy2(item,target/item.name)
        driver=target/'weka_driver';driver.mkdir()
        (driver/'moon.pkg').write_text('import { "Han-Wentao/moonarff" @arff, "moonbitlang/core/encoding/utf8", "moonbitlang/core/double" }\noptions("is-main": true)\n',encoding='utf-8')
        (driver/'main.mbt').write_text(DRIVER.replace('SOURCES',',\n'.join(json.dumps(s,ensure_ascii=False) for s in sources)),encoding='utf-8')
        result=subprocess.run([os.environ.get('MOON','moon'),'run','weka_driver','--target',os.environ.get('ORACLE_TARGET','js'),'--deny-warn'],cwd=target,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if result.returncode: raise RuntimeError(result.stderr.decode('utf-8',errors='replace')+'\n'+result.stdout.decode('utf-8',errors='replace'))
        chunks=result.stdout.decode('utf-8').split('@@SEM@@\n')[1:]
        assert len(chunks)==len(sources),(len(chunks),len(sources))
        exports=work/'exports'; exports.mkdir()
        for i,(chunk,want) in enumerate(zip(chunks,expectations)):
            semantic,outputs=chunk.split('@@ARFF@@\n',1)
            assert json.loads(semantic, parse_constant=lambda value: value)==want,('MoonBit internal semantic mismatch',i,json.loads(semantic),want)
            dense,sparse=outputs.split('@@ARFF@@\n',1)
            sparse=sparse.split('@@END@@',1)[0]
            (exports/('%03d-dense.arff'%i)).write_text(dense,encoding='utf-8')
            (exports/('%03d-sparse.arff'%i)).write_text(sparse,encoding='utf-8')
        checked=work/'checked'; java(exports,checked)
        for i,want in enumerate(expectations):
            for kind in ['dense','sparse']:
                got=json.loads((checked/('%03d-%s.json'%(i,kind))).read_text(encoding='utf-8'), parse_constant=lambda value: value)
                assert got==want,('Weka output mismatch',i,kind,got,want)
        print('PASS: Weka 3.8.6; %d independent fixtures + %d Weka-written inputs; %d dense/sparse exports; internal epoch/weights/nested semantics; UTF8 byte streaming; Weka full/incremental equality' % (len(cases),len(written),len(sources)*2))

if __name__=='__main__': main()
