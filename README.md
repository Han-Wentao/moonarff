# MoonARFF

MoonARFF 是以 MoonBit 实现的 ARFF 数据集互操作库。它面向使用 Weka 数据、整理公开机器学习数据集、以及在 MoonBit 中验证和准备特征的开发者。ARFF 同时包含列类型、类别声明顺序和记录；直接按 CSV 读取会丢失这些约束。本库提供有预算限制的类型解析、密集与稀疏读写、保留模式的数据变换，以及带缺失掩码的特征编码。

## 安装和快速运行

需要 `moonc >= 0.10.16`。本项目固定验证工具链 `0.10.16+b1a0e846e`；CI 使用同一版本。支持 wasm-gc、wasm、JavaScript 和 native 编译目标。wasm 只检查和构建，执行测试使用 wasm-gc、JavaScript 和 Linux native。

在已有 MoonBit 模块中安装：

```sh
moon add Han-Wentao/moonarff@0.1.0
```

在调用包的 `moon.pkg` 中添加：

```moonbit
import {
  "Han-Wentao/moonarff" @arff,
}
options("is-main": true)
```

将以下内容保存为 `main.mbt`，然后执行 `moon run . --target js`：

```moonbit
fn main {
  let source = "@relation sample\n@attribute size numeric\n@attribute kind {small,large}\n@data\n1,small\n?,large\n"
  let data = @arff.parse(source) catch { _ => panic() }
  let plan = @arff.fit_features(data.schema) catch { _ => panic() }
  let batch = @arff.encode_features(plan, data) catch { _ => panic() }
  assert_eq(batch.values[0], [1.0, 1.0, 0.0]) catch { _ => panic() }
  assert_eq(batch.missing[1][0], true) catch { _ => panic() }
  let restored = @arff.decode_features(plan, batch) catch { _ => panic() }
  assert_eq(restored, data) catch { _ => panic() }
  println(@arff.write_sparse(restored) catch { _ => panic() })
}
```

发布版本提供同名模块；本仓库源码的三个示例可直接运行：

```sh
moon run examples/ingestion --target js
moon run examples/curation --target js
moon run examples/inspection --target js
```

## 三个完整工作流

| 使用者 | 输入与处理 | 可验证结果 |
| --- | --- | --- |
| 机器学习开发者 | 有数值、类别和文本的 ARFF；显式投影文本列，再按声明拟合特征计划 | 特征矩阵、缺失掩码、CSV、逆向还原；保留未观察类别 |
| 数据维护者 | 两份列名和类型相同、类别域不同的数据；显式合并类别、重编码、重排列、重命名 | 类别顺序明确的稀疏 ARFF，重新解析后与整理结果相等 |
| 评测或教学人员 | 含省略值和显式缺失的稀疏 ARFF；逐行消费，再计算列摘要 | 区分默认零与缺失、统计均值和样本方差、保留计数为零的类别 |

每个示例都包含断言，失败返回非零。示例源文件分别位于 [ingestion](examples/ingestion/main.mbt)、[curation](examples/curation/main.mbt)、[inspection](examples/inspection/main.mbt)。

## API 与数据语义

- `parse` 返回 `Dataset { schema, rows }`；列类型为 `Numeric`、`Nominal(Array[String])`、`Text`，单元格为 `Number`、`Label`、`Missing`。
- `Reader::new`、`reader.schema()` 和 `reader.next()` 支持逐行消费，不保留先前记录。输入仍是受限的完整字符串，扫描器保留 Unicode 标量副本；这不是无限流或网络流读取器。出错后 Reader 终止，继续调用会报错；EOF 后返回 `None`。
- `read_schema` 只验证头部，不保证数据区合法。`validate_schema`、`validate_record`、`validate` 可检查程序构造的对象。
- `write` 输出密集 ARFF，`write_sparse` 输出稀疏 ARFF。所有用户字符串加引号，字面量 `'?'` 不会变成缺失。数值必须有限，负零符号在读写中保留。
- 稀疏行省略数值表示 `0`，省略类别表示声明域中的第一个值；显式 `?` 才表示缺失。省略文本的 Weka 字典索引语义无法由独立文件安全推断，因此拒绝，写出时文本总是显式出现。索引要求从零开始且严格递增。
- `project` 按名称选择和重排列，拒绝重复列。`slice_rows` 使用左闭右开区间。`rename` 同时应用重命名，允许交换列名但拒绝冲突。
- `recode_nominal` 同时修改声明域和记录，保留未出现类别，拒绝映射冲突。`concatenate` 默认要求完全相同的列契约；显式 `union_domains=true` 才合并类别域，按左侧顺序加右侧新标签，关系名取左侧。
- `profile` 给出数值计数、缺失数、最小值、最大值、均值、样本方差；类别按声明顺序计数；文本只统计缺失、非缺失和最长 UTF-16 长度。无观察值或样本不足返回 `None`；有限数值导致摘要溢出时明确报错。
- `fit_features` 仅依据声明域拟合 numeric passthrough 和完整 one-hot，不根据观察记录推断标签，也不做填补。文本列需显式移除。`encode_features` 要求名称、类型和类别顺序一致；关系名可以不同。计划拥有独立模式快照。
- `FeatureBatch` 同时含 `values` 和 `missing`；缺失载荷为零，但必须保留掩码。类别组掩码一致；非缺失组恰有一个 1。`validate_features` 和 `decode_features` 会拒绝损坏的外部矩阵。
- `features_csv` 使用稳定列名 f0、f1，空单元格表示缺失。`feature_dictionary_csv` 单独输出属性和类别，以 `category_present` 区分类别空字符串与数值列。CSV 面向程序交换，不提供电子表格公式消毒。

数据集结构中的数组可由调用方修改；每次公开数据运算重新验证输入，返回结果拥有独立数组。Reader 和 FeaturePlan 内部模式不向外暴露可变引用。

## 边界、诊断和资源限制

支持大小写不敏感的指令、numeric/real/integer、string、有序 nominal、两种引号、百分号注释、CRLF/CR/LF、常见反斜杠转义。默认限制：输入和序列化输出 16,777,216 个 UTF-16 单元，4,096 个属性，100,000 行，1,000,000 个展开单元格，单个解码词元 1,048,576 个 UTF-16 单元。稀疏输入也按展开宽度计费；one-hot 展开同样受属性和单元格预算约束。可传 `limits=...` 调整，另有输入 256 Mi 单元、属性 65,536、词元 16 Mi 单元的硬上限以限制整数运算和分配。

`ArffError` 区分 `Syntax(line,column,message)`、`Invalid`、`Limit`、`Unsupported`。词法位置按 Unicode 标量从 1 计数，整体长度预算按 UTF-16 单元。不是每个语义错误都附带位置。写入器在追加输出前检查预算；单个转义字符串仍会创建与词元长度成比例的临时字符串。

不支持 date、relational 嵌套属性、实例权重、文本省略字典推断、BOM 自动剥离、非有限数值、任意未知转义。不提供 DataFrame 查询、机器学习训练、插补、完整 Weka Java 序列化或性能优于其他库的承诺。

## 开发与复现

```sh
moon update
moon check --target wasm-gc --deny-warn
moon build --target wasm-gc --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon info
moon fmt --check
python -m pip install liac-arff==2.5.0
python scripts/differential.py
```

差分脚本在临时目录构建，使用固定随机种子的合成数据。它对照 LIAC-ARFF 2.5.0 检查 120 份输入、120 份密集输出和 120 份稀疏输出，同时执行 240 次 MoonBit 读写回环。比较范围是双方共享的数值、类别和字符串子集，不等同于兼容所有 Weka 扩展。CI 包含四目标检查与构建、三个可执行目标的测试和三个示例，以及独立差分和接口一致性门禁。

## 结构、许可证与来源

解析流程分为 `scanner.mbt`、`header.mbt`、`reader.mbt`、`sparse.mbt`；写入器独立；数据变换、摘要和特征计划各自成模块文件。公开接口见 `pkg.generated.mbti`。所有功能实现采用 MoonBit；Python 只用于测试互操作。

采用 [Apache-2.0](LICENSE)。这是依据公开 ARFF 格式说明设计的独立实现，没有翻译或复制 Weka、SciPy、LIAC-ARFF 的解析源码；不依赖它们运行。参考范围和许可证边界见 [SOURCES.md](SOURCES.md)，严格语义查重记录见 [duplicate-check.md](docs/competition/duplicate-check.md)。代码、测试、调试与文档使用 AI 辅助生成，并经过编译、测试和跨实现核对；维护者仍需承担审阅责任。查重结论仅限已记录范围，不保证全球唯一或赛事审核通过。
