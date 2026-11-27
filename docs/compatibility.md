# Weka ARFF 格式兼容矩阵

最终目标是完整兼容 Weka ARFF 格式，包括日期格式及其他必要语义。0.2.8 是当前发布版本，包含 0.2.6 对新增差分样本发现的年周、年内日序及月内周字段冲突修复；项目仍未达到全部格式兼容；固定 Locale.US / UTC 的 Java 17、Weka 3.8.6 独立探针覆盖 2901 组日期接受/拒绝及 epoch 行为；这不等同于全部 pattern、地区与时区历史的穷尽证明。下表的待补齐项属于该目标；数据变换、统计或测试数量不能替代它们。

## 当前可复现范围

| 语义 | 0.2.8 交付行为（含 0.2.6 日期修复） | 验证入口 |
| --- | --- | --- |
| 模式、Numeric / Nominal / String、缺失值 | 读写声明类别域，区分字面量 `?` 与缺失 | 核心测试、LIAC-ARFF 差分、Weka 互操作 |
| 密集／稀疏 | 支持省略的数值／类别／日期默认值；输出显式保留文本和关系 | 稀疏测试及 Weka 双向输出 |
| Date 数值与英文文本 | 支持 SimpleDateFormat 数字/英文月份星期/纪元/时钟/数值及时区名模式子集；日期数字遵循 Java 17 `Character.digit(char, 10)`（BMP 十进制数字），并接受数值字段的负零；epoch 以 IEEE-754 Double 表示；日历转换覆盖 Java Date 的有符号 long 毫秒边界；Double epoch 在大于 2^53 毫秒后分辨率自然降低；支持 BC | 日期回归及 Weka 3.8.6 epoch 对照（含 Unicode 十进制数字、负零、BC、多位字段宽度、时区名称） |
| 日期文本解析 | 英文名称不依赖 pattern 输出宽度且大小写不敏感；相邻字段按模式宽度消费；支持前导数字空白和完成 pattern 后的尾随文本；支持可识别字段组合及后写字段优先级 | 本地回归及固定版本 Weka 双向差分 |
| 日历与冲突 | GregorianCalendar 1582 切换；按字段 stamp 处理重复/组合的日期与时钟字段；选中的年周字段优先于月份/日等字段；Y+D 组合要求后置星期选择器且落在该周年的第1周；支持已验证的年内日序及月内周字段组合 | 日期边界测试、Weka 日期/时区双向差分 |
| Relational | 递归模式、子记录、空关系／缺失关系、内层权重，受共享预算限制 | 关系回归及 Weka 内部嵌套语义对照 |
| 实例权重 | 密集／稀疏行尾权重，默认1；保留零、负数、有限数及正负无穷；NaN 权重按 Weka 归一为默认值1 | 权重测试及 Weka 内部权重对照 |
| 增量输入／输出 | 任意 UTF-8 字节边界、逐记录回调和 sink 输出，保留有界当前记录 | 流式错误／边界测试、五个工作流及 Weka 全量／增量对照 |

无时区字段按 UTC 解释。参考 Weka 进程固定 `en_US` 与 UTC。英文时区数据源为 Java 17 `DateFormatSymbols(Locale.US)` 名称及对应 JDK tzdb 2021e 规则。API 不接受 IANA/Windows 时区 ID；已针对 618 个可识别名称，以 31500 个固定日期、历史切换点、夏令时边界及重复字段样本对照 Weka 3.8.6。日期字段按 Java 严格日历在 UTC 解析时刻重新计算后核验，仍不声称覆盖其他 locale 或全部时区/格式组合。当前无效日期字段严格拒绝；Weka ARFF 日期属性使用严格日历，本库也拒绝无效日历字段；未穷尽的兼容场景包括非英语 locale、pattern 与时区组合；Java long 毫秒边界的有限探针不证明全部日期语义。

## 已知兼容边界与持续验证项

| 差异或缺口 | 后续实现约束 | 完成判据 |
| --- | --- | --- |
| Wide date patterns and epoch boundary | 日期 epoch 使用 IEEE-754 Double，日期日历已扩展至 Java Date 的 Long.MIN_VALUE..Long.MAX_VALUE 毫秒边界；Double-backed API 在 `abs(epoch_ms)` > 2^53 时不保证逐毫秒精度，Long.MAX_VALUE 转 Double 后按 Java 饱和转换格式化。全部 pattern/locale/zone 组合尚未穷尽。 | `scripts/date_semantics.py` 使用 Weka 3.8.6 对 2,901 个日期样本独立验证解析接受/拒绝及 epoch；JS 与 wasm-gc 均通过。该有限矩阵不能证明完整语义。 |
| 美式周序字段 `Y/w/u/W/F` | 已实现年周序 `Y/w/u` 与月内 `W/F` 字段；首周日开周，`Y/w` 首周含1天；1582-10 的 Gregorian cutover 月 `W/F` 按混合历法连续日期计算。对照已覆盖常规、跨年和 cutover 样本；2901组通用日期探针及31500组时区语义探针覆盖该切换月 W/F（含有/无 d、u）组合；更多年份边缘仍需独立覆盖 | Weka 3.8.6 年周跨年与常规 W/F 样本、非法第54周及无效月内序号拒绝；测试切换点有效日期、并按 Weka 行为处理其严格解析拒绝差异 |
| Named-zone edge cases and non-English locales | English Locale.US display names use the matching Java 17.0.2/tzdb 2021e historical rules; region IDs and non-English localized names remain unsupported | Independent Java 17/Weka 3.8.6 oracle covers 618 accepted names and 31500 date/time/transition/repeated-field probes on JS and wasm-gc; broader formats/locales remain outside the verified matrix |
| SimpleDateFormat repeated/conflicting fields | Weka 3.8.6 `DateAttributeInfo` calls `setLenient(false)`; strict invalid-date rejection matches the oracle. Java `DecimalFormat` Unicode decimal digits and signed-zero input are covered by fixed probes. Repeated fields and clock precedence are covered by fixed probes. | `scripts/date_semantics.py`；包含额外 Y/D/W/F 顺序与组合探针；该有限矩阵不代表穷尽。 |
| 稀疏 String／Relational 省略值 | Weka 对省略值使用该属性字典索引0；`DictionaryZero` 显式保存延迟引用，全量解析会在后续字典值出现时回填；流式回调也保留即时状态，调用方可在结束后以 `resolve_dictionary_defaults(schema, rows)` 得到副本并完成回填。若属性全程没有显式字典值，引用维持未解析且写出明确报错 | 已有稀疏字符串与嵌套关系回归及 Weka 差分样本；已有首次省略、后置首值、嵌套关系和副本非突变回归；持续通过 Weka 3.8.6 的稀疏读写互操作 |
| Other lexical/numeric behavior | Weka-compatible numeric spellings and unknown quoted-token escapes are implemented; BOM-prefixed input is rejected by both Weka and this parser. Attribute weights are not ARFF text semantics. | Fixed Weka fixtures and `scripts/weka_interop.py`; do not generalize beyond verified cases. |

仍需持续处理尚未覆盖的 locale、时区 ID、日期模式组合及其他格式差异；每项工作须同步模式验证、内存与流式接口、密集／稀疏写出、错误语义、文档及独立互操作样本。只有矩阵各项有可复现证据，才可宣称完成相应兼容能力。资源预算和严格输入策略仍需公开，并与格式本身的能力区分。

## 验证与来源

`python scripts/weka_interop.py` 使用校验 SHA-256 的外部 Weka 3.8.6，比较190份合成原始输入、190份Weka写回输入、760份密集／稀疏输出；同时检查内部 epoch、权重、嵌套值和全量／增量一致性。该样本集覆盖表中当前能力，不能证明所有 Weka 文件或全部日期模式兼容。`python scripts/differential.py` 保留 LIAC-ARFF 支持子集的独立对照。参考实现分别安装，不进入生产包。

行为依据为 [Weka ARFF 说明](https://waikato.github.io/weka-wiki/formats_and_processing/arff_stable/) 和 [Java 17 SimpleDateFormat](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/text/SimpleDateFormat.html)。机器学习训练、DataFrame 查询、Java 对象序列化不属于 ARFF 文本格式兼容目标。


## 已实现但有明确边界的日期语义

`y`/`yy` 等年份字段恰好解析为两位数字时，按解析时的滚动 80 年窗口和完整月日时刻边界映射；Reader/StreamReader 在创建时固定该边界，独立 `parse_date` 使用调用时边界。`G` 支持 AD 和 BC；日期日历计算覆盖 Java Date 有符号 64 位毫秒范围；epoch API 与 Weka Instances 一样以 IEEE-754 Double 保存，超过 2^53 毫秒时毫秒精度降低，`Long.MAX_VALUE` 转 Double 后按 Java 饱和转换格式化。这些确定性语义不代表完整 Weka 日期兼容。 数值日期字段的 pattern 重复宽度作为最小字段宽度，独立字段读取连续数字直至非数字边界；相邻字段仍使用固定模式宽度消歧。

`W` 表示月内周序号（周日开周），`F` 表示该星期在月份内第几次出现；解析要求年月/月份和星期字段，若同时给出 `d` 则必须一致。两者均拒绝解析到相邻月份；1582 年 10 月按 GregorianCalendar 混合历法边界计算。普通日期及1582年10月的 W/F 严格选择器矩阵由 Weka 3.8.6 对照。该切换月 Java formatter 可生成部分其 strict parser 无法接收的 W/F 文本；本库拒绝不能按同 pattern 无损往返的格式请求，避免静默损失。Java long 边界附近已覆盖固定探针；其他日期模式、时区历史和非英文 locale 的组合仍未穷尽。
