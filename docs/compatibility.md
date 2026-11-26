# Weka ARFF 格式兼容矩阵

最终目标是完整兼容 Weka ARFF 格式，包括日期格式及其他必要语义。0.2.3 是当前已发布的语义版本；0.2.4 仅修正文档版本状态；项目尚未达到全部格式兼容；当前工作区已用固定 Locale.US / UTC 的 Java 17、Weka 3.8.6 探针对 1400 组日期接受/拒绝及 epoch 行为作独立比较；这不等同于全部 pattern、地区与时区历史的穷尽证明。下表的待补齐项属于该目标；数据变换、统计或测试数量不能替代它们。

## 当前可复现范围

| 语义 | 0.2.3 已发布行为 | 验证入口 |
| --- | --- | --- |
| 模式、Numeric / Nominal / String、缺失值 | 读写声明类别域，区分字面量 `?` 与缺失 | 核心测试、LIAC-ARFF 差分、Weka 互操作 |
| 密集／稀疏 | 支持省略的数值／类别／日期默认值；输出显式保留文本和关系 | 稀疏测试及 Weka 双向输出 |
| Date 数值与英文文本 | 支持 SimpleDateFormat 数字/英文月份星期/纪元/时钟/数值及时区名模式子集；epoch 毫秒限制为 IEEE-754 可精确整数范围；支持 BC 及约 ±285000 日历年 | 日期回归及 Weka 3.8.6 epoch 对照（含 BC、多位字段宽度、时区名称） |
| 日期文本解析 | 英文名称不依赖 pattern 输出宽度且大小写不敏感；相邻字段按模式宽度消费；支持前导数字空白和完成 pattern 后的尾随文本；支持可识别字段组合及后写字段优先级 | 本地回归及固定版本 Weka 双向差分 |
| 日历与冲突 | GregorianCalendar 1582 切换；按字段 stamp 处理重复/组合的日期与时钟字段；支持年内日序、年周及月内周字段的常见组合 | 日期边界测试、Weka 日期/时区双向差分 |
| Relational | 递归模式、子记录、空关系／缺失关系、内层权重，受共享预算限制 | 关系回归及 Weka 内部嵌套语义对照 |
| 实例权重 | 密集／稀疏行尾权重，默认1；保留零、负数、有限数及正负无穷；NaN 权重按 Weka 归一为默认值1 | 权重测试及 Weka 内部权重对照 |
| 增量输入／输出 | 任意 UTF-8 字节边界、逐记录回调和 sink 输出，保留有界当前记录 | 流式错误／边界测试、五个工作流及 Weka 全量／增量对照 |

无时区字段按 UTC 解释。参考 Weka 进程固定 `en_US` 与 UTC。英文时区数据源为 Java 17 `DateFormatSymbols(Locale.US)` 名称及对应 JDK tzdb 2021e 规则。API 不接受 IANA/Windows 时区 ID；已针对 618 个可识别名称，以 31500 个固定日期、历史切换点、夏令时边界及重复字段样本对照 Weka 3.8.6。日期字段按 Java 严格日历在 UTC 解析时刻重新计算后核验，仍不声称覆盖其他 locale 或全部时区/格式组合。当前无效日期字段严格拒绝；SimpleDateFormat 默认宽松归一化行为未实现。

## 必须继续补齐的兼容工作

| 差异或缺口 | 后续实现约束 | 完成判据 |
| --- | --- | --- |
| 宽日期模式与年限边缘 | epoch 毫秒受精确整数边界约束，宽年份测试目前到280000年；最远可表示边界及所有 pattern 的边界组合尚未穷尽 | 针对正负精确毫秒边界及相邻越界值，与 Weka 比较格式、解析、读写结果 |
| 美式周序字段 `Y/w/u/W/F` | 已实现年周序 `Y/w/u` 与月内 `W/F` 字段；首周日开周，`Y/w` 首周含1天；1582-10 的 Gregorian cutover 月 `W/F` 按混合历法连续日期计算。对照已覆盖常规、跨年和 cutover 样本；1400组通用日期探针及31500组时区语义探针覆盖该切换月 W/F（含有/无 d、u）组合；更多年份边缘仍需独立覆盖 | Weka 3.8.6 年周跨年与常规 W/F 样本、非法第54周及无效月内序号拒绝；测试切换点有效日期、并按 Weka 行为处理其严格解析拒绝差异 |
| Named-zone edge cases and non-English locales | English Locale.US display names use the matching Java 17.0.2/tzdb 2021e historical rules; region IDs and other locales remain unsupported | Independent Java 17/Weka 3.8.6 oracle covers 618 accepted names and 31500 date/time/transition/repeated-field probes on JS and wasm-gc; broader formats/locales remain outside the verified matrix |
| SimpleDateFormat 重复/冲突字段、宽松归一化 | 重复字段按模式从左到右解析，后出现的同类字段覆盖先前值；H/k 按模式顺序确定小时，12/24 小时制混用拒绝。无效日历字段严格拒绝，不提供 Java 默认宽松归一化 | 固定 Weka 3.8.6 重复年/月/小时样本；宽松归一化仍不支持 |
| 稀疏 String／Relational 省略值 | Weka 对省略值使用该属性字典索引0；`DictionaryZero` 显式保存延迟引用，全量解析会在后续字典值出现时回填；流式回调也保留即时状态，调用方可在结束后以 `resolve_dictionary_defaults(schema, rows)` 得到副本并完成回填。若属性全程没有显式字典值，引用维持未解析且写出明确报错 | 已有稀疏字符串与嵌套关系回归及 Weka 差分样本；已有首次省略、后置首值、嵌套关系和副本非突变回归；持续通过 Weka 3.8.6 的稀疏读写互操作 |
| 其他词法及数值兼容差异 | 已支持 Weka 3.8.6 实测的 NaN/Infinity、Java 浮点后缀、十六进制浮点、外围空白及指数溢出；NaN 数值映射为缺失、NaN 权重按 Weka 归一为1。未知转义与 BOM 自动剥离仍不支持。属性权重不作为 ARFF 文本语义。 | 以 Weka 实际读写样本逐项核对，不以静默忽略实现兼容 |

后续继续处理年限边界、日期时区语义与其他格式差异；每项工作须同步模式验证、内存与流式接口、密集／稀疏写出、错误语义、文档及独立互操作样本。只有矩阵各项有可复现证据，才可宣称完成相应兼容能力。资源预算和严格输入策略仍需公开，并与格式本身的能力区分。

## 验证与来源

`python scripts/weka_interop.py` 使用校验 SHA-256 的外部 Weka 3.8.6，比较187份合成原始输入、187份Weka写回输入、748份密集／稀疏输出；同时检查内部 epoch、权重、嵌套值和全量／增量一致性。该样本集覆盖表中当前能力，不能证明所有 Weka 文件或全部日期模式兼容。`python scripts/differential.py` 保留 LIAC-ARFF 支持子集的独立对照。参考实现分别安装，不进入生产包。

行为依据为 [Weka ARFF 说明](https://waikato.github.io/weka-wiki/formats_and_processing/arff_stable/) 和 [Java 17 SimpleDateFormat](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/text/SimpleDateFormat.html)。机器学习训练、DataFrame 查询、Java 对象序列化不属于 ARFF 文本格式兼容目标。


## 已实现但有明确边界的日期语义

`y`/`yy` 等年份字段恰好解析为两位数字时，按解析时的滚动 80 年窗口和完整月日时刻边界映射；Reader/StreamReader 在创建时固定该边界，独立 `parse_date` 使用调用时边界。`G` 支持 AD 和 BC；当前 epoch 模型覆盖公元前9999年至公元9999年，超出范围拒绝。这些确定性语义不代表完整 Weka 日期兼容。 数值日期字段的 pattern 重复宽度作为最小字段宽度，独立字段读取连续数字直至非数字边界；相邻字段仍使用固定模式宽度消歧。

`W` 表示月内周序号（周日开周），`F` 表示该星期在月份内第几次出现；解析要求年月/月份和星期字段，若同时给出 `d` 则必须一致。两者均拒绝解析到相邻月份；1582 年 10 月按 GregorianCalendar 混合历法边界计算。普通日期及1582年10月的 W/F 严格选择器矩阵由 Weka 3.8.6 对照。该切换月 Java formatter 可生成部分其 strict parser 无法接收的 W/F 文本；本库拒绝不能按同 pattern 无损往返的格式请求，避免静默损失。完整年份边界、时区历史和非英文 locale 仍未穷尽。
