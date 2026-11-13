# MoonARFF

MoonARFF 是 MoonBit 实现的 ARFF 格式库，用于 Weka 数据交换、数据接入和多实例数据处理。0.2.0 在数值、类别和文本之外，增加 **Date、嵌套 Relational、实例权重及真正按块输入／逐行输出的流式接口**。运行时不依赖 Java、Python 或 Weka。

目标是让 MoonBit 程序能保留 ARFF 的模式、缺失值、日期时间戳、关系值和权重，再交给下游处理。列变换、统计和特征编码是建立在格式读写之上的辅助功能。

## 安装与快速开始

需要 `moonc >= 0.10.16`。本版本使用 `moonc 0.10.16+b1a0e846e` 验证，CI 固定同一工具链。检查与构建覆盖 wasm-gc、wasm、js、native；测试和示例在 wasm-gc、js、Linux native 执行。Windows native 还需要本机 C 工具链，不能仅凭 MoonBit 安装保证可运行。

```sh
moon new arff_consumer
cd arff_consumer
moon add Han-Wentao/moonarff@0.2.0
```

在使用它的包的 `moon.pkg` 中添加：

```moonbit
import { "Han-Wentao/moonarff" @arff }
```

下面代码可放入该包的 `main.mbt`，并在 `moon.pkg` 中设置 `options("is-main": true)`：

```moonbit
fn main {
  let source = "@relation events\n@attribute day date 'yyyy-MM-dd'\n@attribute state {ok,bad}\n@data\n2024-02-29,ok,{2.5}\n?,bad\n"
  let data = @arff.parse(source) catch { _ => panic() }
  assert_eq(data.rows[0].weight, 2.5) catch { _ => panic() }
  let encoded = @arff.write_sparse(data) catch { _ => panic() }
  assert_eq(@arff.parse(encoded) catch { _ => panic() }, data) catch { _ => panic() }
  println(encoded)
}
```

```sh
moon run . --target js
```

如果 `moon new` 生成了子包，请把上述文件放入对应子包并调整 `moon run` 的包路径。完整调用签名见 [pkg.generated.mbti](pkg.generated.mbti)。

## 格式支持

| 能力 | 0.2.0 行为 |
| --- | --- |
| Numeric / Real / Integer | 有限 Double；密集与稀疏读写，保留负零 |
| Nominal | 有序声明域，未观察到的类别也保留；字面量 `'?'` 与缺失不同 |
| String | 引号与转义后的文本；稀疏输出总是显式写出 |
| Date | 默认格式或显式数值日期格式；保存 UTC epoch 毫秒，见下节 |
| Relational | 嵌套属性声明、匹配的 `@end`、嵌套行与权重；空关系和缺失关系不同 |
| 实例权重 | 密集及稀疏行尾 `,{weight}`；默认 1，支持有限的零、负数、小数 |
| 稀疏默认值 | 省略 Numeric 为 0、Nominal 为首项、Date 为 epoch 0；显式 `?` 为缺失 |
| 文本／关系省略 | 拒绝依赖外部字典索引的省略；用显式文本或关系值写出 |
| 增量输入 | `StreamReader::feed` 接收文本块；`feed_utf8` 可在任意字节边界分块 |
| 增量输出 | `StreamWriter` 立即写头，每次 `write` 生成并交给 sink 一行 |

支持大小写不敏感的指令、两种引号、百分号注释、CRLF/CR/LF 和常见反斜杠转义。实例权重属于交换数据，保留负权重并不表示下游机器学习算法接受它。

### Date 的确定性语义

`AttributeType::Date(pattern)` 对应 `Cell::DateValue(epoch_ms)`。未写日期格式时采用 `yyyy-MM-dd'T'HH:mm:ss`。无时区字段按 UTC 解释，避免依赖运行机器的本地时区；有数值偏移时先归一化为 UTC。输出也使用 UTC。

支持 Java `SimpleDateFormat` 的**数值日期配置范围**：`yyyy`、`M/MM`、`d/dd`、`H/HH`、`m/mm`、`s/ss`、`S/SS/SSS`、`Z`、`X/XX/XXX`，以及单引号文字和双写单引号。`S` 表示毫秒数；例如 `.1` 是 1 毫秒。相邻数值字段按字段宽度解析。格式长度为 1–256 个 UTF-16 单元。

日历采用与 Java GregorianCalendar 相同的 1582 年切换规则：1582-10-04 之后为 1582-10-15；支持年份 0001–9999。非法日期和切换空档严格报错，不使用 Weka/Java 的宽松溢出归一化。暂不支持本地化月份名、星期名、时区名、两位年份窗口、周序年份等其他 `SimpleDateFormat` 字段。

`parse_date` 和 `format_date` 可独立使用。日期写出和数据验证会检查时间戳可否按该格式无损表示：日期格式只有天却传入非零时分秒、毫秒不为整数、或 UTC 规范化后无法按原格式表示，都会报错，避免静默丢精度。

### Relational 与权重

```arff
@relation observations
@attribute day date 'yyyy-MM-dd'
@attribute samples relational
  @attribute value numeric
  @attribute state {ok,bad,unseen}
@end samples
@data
2024-02-29,'1,ok,{0.25}\n2,bad,{-0.5}',{2}
1970-01-01,''
?,?
```

关系值是包含 ARFF 子记录的引号字符串；换行用 `\n` 转义。`Relation([])` 表示空关系，`Missing` 表示缺失。内层可以继续声明 Relational，最多 16 层；嵌套行和单元格共同消耗全局预算。子记录和顶层记录都保留 `weight`。

## 真正的增量流式处理

`Reader::new(source)` 仍是对完整字符串的拉取读取器。对于文件、网络或其他分块输入，使用新的 `StreamReader`：

```moonbit
let reader = @arff.StreamReader::new() catch { _ => panic() }
let mut count = 0
reader.feed("@relation r\n@attribute n numeric\n@data\n1\n", fn(row) {
  // 在这里处理、转换或转发这一行；库内部没有记录队列。
  count += 1
  ignore(row)
}) catch { _ => panic() }
reader.feed("2", fn(_) { count += 1 }) catch { _ => panic() }
reader.finish(fn(_) { count += 1 }) catch { _ => panic() }
assert_eq(count, 2) catch { _ => panic() }
```

- `feed_utf8(bytes, callback)` 使用严格增量 UTF-8 解码，保留未完成字节序列，拒绝过长编码、代理码点、非法字节和截断 EOF。
- 输入只保存有界头部、当前物理行和少量解码状态；头部完成后释放头部文本。`buffered_units()` 可观察文本缓冲长度，不包含有界模式和当前回调中的记录。
- 回调同步执行，返回后才继续读取。调用方控制背压；回调中若主动保存所有记录，其内存由调用方负责。
- `schema()` 在 `@data` 行完成后返回独立模式快照。`finish` 消费未换行的最后一行并检查完整性，EOF 可重复调用。
- `StreamWriter::new(schema, sink, sparse=true)` 立即发送头部；`write(row)` 验证完整的当前记录后，立即将一行字符串交给 sink；`finish()` 结束写入。文件句柄、字节编码、刷新和关闭由 sink 负责。
- 读写器遇到解析／校验／回调错误后进入失败状态；不支持重入。错误前已成功交付的记录或传输片段不会回滚，调用方应按需要使用事务或临时文件。

## 五个完整工作流

```sh
moon run examples/ingestion --target js
moon run examples/curation --target js
moon run examples/inspection --target js
moon run examples/streaming --target js
moon run examples/relational --target js
```

| 工作流 | 输入、操作与结果 |
| --- | --- |
| [ingestion](examples/ingestion/main.mbt) | 数据接入程序读取带缺失值的数据，拟合声明域特征计划，输出带缺失掩码的矩阵和 CSV |
| [curation](examples/curation/main.mbt) | 整理工具拼接数据、显式合并类别域、重编码和重排列，再验证稀疏交换结果 |
| [inspection](examples/inspection/main.mbt) | 检查程序逐行消费稀疏数据，区分默认值与缺失，计算样本方差及未出现类别计数 |
| [streaming](examples/streaming/main.mbt) | 模拟传输每次送入一个 UTF-8 字节，处理日期与权重并立即交给稀疏 sink，再核验结果 |
| [relational](examples/relational/main.mbt) | 多实例数据工具接入含日期的实例包，保留内层和外层权重，投影列后进行稀疏交换与关系摘要 |

示例内有断言，失败返回非零。streaming 示例用 StringBuilder 收集输出以便断言；生产 sink 可以直接写文件或网络，流式库本身不积累输出。

## 数据运算与迁移

- `Dataset { schema, rows }`、`Record { values, weight }`。从 0.1.x 迁移时，手工构造 Record 须新增 `weight: 1.0`；模式和单元格枚举增加 Date / Relational 分支。
- `read_schema` 只验证头部，不保证数据区合法。`validate_schema`、`validate_record`、`validate` 检查程序构造的数据。
- `project` 按列名选择和重排列；`slice_rows` 采用左闭右开区间；`rename` 支持同时交换列名；`recode_nominal` 保留未出现类别并拒绝冲突。
- `concatenate` 默认要求相同列契约；只有 `union_domains=true` 才合并类别域。日期格式和嵌套模式必须一致。上述运算深复制嵌套数组并保留权重。
- `profile` 按记录数提供**未加权**摘要，不把权重当作重复次数；Date 使用 epoch 毫秒的数值摘要，Relational 统计缺失数、非缺失数和直接子记录数。数值溢出报错。
- `fit_features` 支持 Numeric、Date 毫秒直通和 Nominal one-hot；Text、Relational 要显式移除。`encode_features` 拒绝非单位权重，避免 FeatureBatch 未携带权重造成静默丢失。
- FeatureBatch 保留 `values` 和 `missing`；解码验证掩码及 one-hot 唯一性。`features_csv`、`feature_dictionary_csv` 分别输出数值矩阵和类别字典，不提供电子表格公式消毒。

## 资源预算与诊断

默认 `Limits`：16,777,216 个输入／输出 UTF-16 单元、4,096 个属性、100,000 条记录、1,000,000 个展开单元格、1,048,576 个解码词元单元。嵌套属性／记录／单元格计入共享总量；稀疏行也按展开宽度计费。另有输入 256 Mi 单元、属性 65,536、词元 16 Mi 单元的硬上限。

完整字符串 `parse`/`write` 的 `max_input` 限制整份文档；流式接口将它用于**完整头部和每条物理记录的上限**，累计输入可以更长，但累计记录／单元格仍受全局预算约束。单个关系值需要在当前父记录内完整解码；不是对子关系值字节级懒解析。单个转义词元会使用与其长度成比例的临时内存。

`ArffError` 区分 `Syntax(line,column,message)`、`Invalid`、`Limit`、`Unsupported`。词法位置按 Unicode 标量从 1 计数，长度预算按 UTF-16 单元；语义错误不一定附位置。不支持 BOM 自动剥离、非有限数值、未知转义、属性级权重、完整 Weka Java 对象序列化。项目不提供训练、插补、DataFrame 查询或未经实测的性能承诺。

## 验证与 Weka 互操作

```sh
moon update
moon info
moon fmt --check
moon check --target wasm-gc --deny-warn
moon build --target wasm-gc --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
python -m pip install liac-arff==2.5.0
python scripts/differential.py
# 需要 Java 17+ 和 javac；测试脚本下载并校验 Weka 3.8.6 JAR，也可设置 WEKA_JAR。
python scripts/weka_interop.py
```

53 项测试覆盖核心格式、变换、嵌套预算、日期、权重、流式错误和跨块边界。LIAC-ARFF 对照保留 120 份数值／类别／文本输入、240 份密集／稀疏输出。新增 Weka 对照由真实 Java Weka 执行：88 份自建样本加 88 份 Weka 写出的输入，验证 352 份密集／稀疏输出，直接核对内部日期 epoch、权重、嵌套模式及值；同时比较 Weka 的完整／增量解析，并对 MoonARFF 逐字节输入和逐记录输出做一致性检查。

两个差分脚本都在临时副本构建，不改项目。CI 在 js、wasm-gc 执行两类独立对照，并覆盖四目标检查／构建、三个可执行目标的测试和五个示例、接口及格式一致性。样本是确定性合成数据，这些结果不代表全部 Weka 文件或所有日期配置均兼容。

## 结构与来源

`scanner.mbt` / `header.mbt` / `reader.mbt` / `sparse.mbt` 处理格式；`date.mbt` 实现日期；`writer.mbt` / `sparse_writer.mbt` 负责写出；`stream.mbt` 提供分块适配；数据变换和特征运算分别实现。所有生产功能使用 MoonBit。

采用 [Apache-2.0](LICENSE)。依据公开 ARFF 格式说明独立实现，没有移植 Weka、SciPy 或 LIAC-ARFF 的解析源码。Weka GPL JAR 仅作为外部测试程序下载和调用，不进入模块、仓库或运行时依赖；Java 桥接代码为本项目独立编写。来源和许可证边界见 [SOURCES.md](SOURCES.md)，语义查重范围见 [duplicate-check.md](docs/competition/duplicate-check.md)。代码、测试和文档使用 AI 辅助并经编译、回归及独立实现核验；不据此保证无缺陷或赛事审核通过。
