#!/usr/bin/env python3
"""Bidirectional differential checks against LIAC-ARFF 2.5.0 (test dependency only).
Synthetic deterministic fixtures; builds in a temporary checkout, leaves source clean.
"""
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile
import arff

ROOT = Path(__file__).resolve().parents[1]

def fixtures():
    rng = random.Random(20261109)
    for case in range(80):
        rows = []
        for row in range(5):
            rows.append([None if row == 4 else rng.randint(-10000, 10000) / 8,
                         None if row == 3 else rng.choice(['red', 'blue', 'green']),
                         None if row == 2 else rng.choice(['plain', 'with space', 'comma,value', '中文'])])
        data = dict(relation='case_' + str(case), attributes=[('x', 'NUMERIC'),
                    ('class', ['red', 'blue', 'green', 'unused']), ('note', 'STRING')], data=rows)
        yield arff.dumps(data), data
    for case in range(40):
        # Independently build sparse documents; omission means 0/first nominal label.
        x = case - 20
        source = ('@relation sparse_%d\n@attribute x numeric\n@attribute c {a,b,unused}\n'
                  '@data\n{}\n{0 %d,1 b}\n{0 ?,1 ?}\n' % (case, x))
        expected = dict(relation='sparse_' + str(case), attributes=[('x', 'NUMERIC'),
                        ('c', ['a', 'b', 'unused'])], data=[[0, 'a'], [x, 'b'], [None, None]])
        assert arff.loads(source)['data'] == expected['data']
        yield source, expected

def normalize(data):
    attrs = [(name, 'NUMERIC' if isinstance(kind, str) and kind.upper() in
              ('NUMERIC', 'REAL', 'INTEGER') else kind) for name, kind in data['attributes']]
    return data['relation'], attrs, data['data']

def main():
    cases = list(fixtures())
    with tempfile.TemporaryDirectory(prefix='moonarff-oracle-') as temp:
        target = Path(temp)
        for item in ROOT.iterdir():
            if item.name.startswith('.') or item.name in ('_build', 'target', 'scripts'):
                continue
            if item.is_dir():
                shutil.copytree(item, target / item.name)
            else:
                shutil.copy2(item, target / item.name)
        example = target / 'oracle_driver'
        example.mkdir()
        (example / 'moon.pkg').write_text('import { "Han-Wentao/moonarff" @arff }\noptions("is-main": true)\n', encoding='utf-8')
        literals = ',\n'.join(json.dumps(source, ensure_ascii=False) for source, _ in cases)
        code = '''fn main {
  let sources = [SOURCES]
  for source in sources {
    let data = @arff.parse(source) catch { _ => panic() }
    let dense = @arff.write(data) catch { _ => panic() }
    let sparse = @arff.write_sparse(data) catch { _ => panic() }
    assert_eq(@arff.parse(dense) catch { _ => panic() }, data) catch { _ => panic() }
    assert_eq(@arff.parse(sparse) catch { _ => panic() }, data) catch { _ => panic() }
    println("@@DENSE@@")
    println(dense)
    println("@@SPARSE@@")
    println(sparse)
    println("@@END@@")
  }
}
'''.replace('SOURCES', literals)
        (example / 'main.mbt').write_text(code, encoding='utf-8')
        result = subprocess.run([os.environ.get('MOON', 'moon'), 'run', 'oracle_driver', '--target',
                                 os.environ.get('ORACLE_TARGET', 'js'), '--deny-warn'], cwd=target,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        output = result.stdout.decode('utf-8')
        chunks = output.split('@@DENSE@@\n')[1:]
        assert len(chunks) == len(cases), (len(chunks), len(cases))
        for chunk, (_, expected) in zip(chunks, cases):
            dense, rest = chunk.split('@@SPARSE@@\n', 1)
            sparse, _ = rest.split('@@END@@', 1)
            assert normalize(arff.loads(dense)) == normalize(expected)
            assert normalize(arff.loads(sparse)) == normalize(expected)
        print('PASS: 120 reference inputs; 120 dense + 120 sparse outputs; 240 MoonBit round trips')

if __name__ == '__main__':
    main()
