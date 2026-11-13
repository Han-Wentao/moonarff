# 语义查重与选题记录

日期：2026-11-09。选题：MoonARFF，类型化 ARFF 数据交换、预算限制、模式变换与可逆特征编码。

## 方法与范围

按 moonbit-hackathon-builder 和 osc2026-guide 的项目检索指导执行：检索 MoonCakes、GitHub、awesome-moonbit 和本地永久项目注册表，读取邻近项目说明、实际源码与测试，按可替代的使用流程比较。公开索引查询不是唯一性裁决。

MoonCakes 分三组执行 35 次关键词查询，每次 limit=100，包括 arff、ARFF、weka、weka Instances、parse_arff、loadarff、attribute relation、relation format、libsvm、keel、dataset、dataframe、csv、pcap、survival、kaplan、vcd、robots、sparse、tzif 等。ARFF/Weka/parse_arff/loadarff/libsvm 未返回直接模块；泛化 csv 检索达到 100 上限，不能视作全量覆盖。

GitHub 仓库查询 `arff language:MoonBit`、`weka language:MoonBit`、`arff MoonBit in:readme` 均未发现仓库；代码查询 `"ARFF" language:MoonBit` 返回 18 个结果，检查为 DWARF 标识符等语义无关结果。`"loadarff" language:MoonBit`、`"parse_arff" language:MoonBit`、`"@relation" "@attribute" language:MoonBit` 未返回直接候选。查询 per_page=100，响应 incomplete_results=false；结果快照保存在仓库外审计目录。

官方 awesome 列表：https://github.com/moonbitlang/awesome-moonbit 。永久注册表按 ARFF/Weka/稀疏数据集/类别编码能力检索并读取邻近指纹。注册表用于避免与本机已有项目重选，不是生态完整索引。

## 三个不同领域候选

| 候选 | 发现与实际检查 | 决策 |
| --- | --- | --- |
| 网络抓包解析 | cghyyrrt/moonbit-pcap 0.1.2，读取 README、binary_reader、bit_reader、CSV exporter 和仓库树 | 成熟直接重复，淘汰 |
| 生存分析 | Lyl66655/moon-survival 0.2.4，读取 README、CSV 导入、Kaplan-Meier 及对应测试 | 核心工作流重复，淘汰 |
| ARFF 模式数据交换 | 未发现直接 ARFF 模块；继续比较下表的数据处理邻居 | 通过有限范围选题门禁 |

对通过候选的工程判断（5 分制）：明确标准和成熟跨语言使用基线 5、三个复用受众 4、生态缺口证据 4、MoonBit 实现可行性 5、差异可验证性 5。淘汰项不以评分绕过重复硬门槛。

## 邻近项目能力矩阵与源码核对

| 项目 | 核对材料 | 相交能力 | 关键边界 |
| --- | --- | --- | --- |
| ihb2032/MoonFrame 0.8.1 | 仓库完整树、根 README（仅短占位）、io/csv.mbt、csv_test.mbt、csv_wbtest.mbt、MoonCakes 文档 | DataFrame、CSV、类型列 | 树与源码检索未见 ARFF 头部/稀疏默认值/声明类别域协议 |
| moonbit-community/pandas 0.7.1 | README、完整树、src/lib/pandas/csv.mbt、MoonCakes 文档 | 表格处理和 CSV 输入 | 未发现 ARFF 模式协议；本项目不构建 DataFrame 查询引擎 |
| AlexenderSokolov/moonsplit 0.3.0 | README、完整树、MoonCakes 文档；未宣称逐文件源码审计 | 数据集划分 | 输入准备相邻；本项目不实现 train/test 切分或分层抽样 |
| 本地已登记 MoonRecoder/MoonConcept | 注册表中完整邻近能力指纹 | 类别重编码、形式概念分析 | 不把类别重编码当新颖性；核心是 ARFF 双向模式交换、稀疏默认语义和带掩码可逆编码 |

上述项目是邻居而非被引用代码。没有复制其源码、测试数据或文档。选题的必要性来自保留有序类别域和稀疏缺失语义的数据交换需求；通用 CSV、矩阵或重编码 API 不能直接替代这条完整输入输出路径。

## 反向检查、边界和复核

用实际用户输入反问：已有项目能否直接读取带 @relation/@attribute、数值/类别/字符串、密集/稀疏混合记录，保留省略默认值与显式缺失，完成模式变换并写回，再按声明域生成可逆特征？记录范围内未见成熟直接替代。若后来发现这种替代，应重新审查必要性，不能只改名字继续。

以下为 2026-11-09 的 **0.1.0 历史范围**：当时不支持 Date、Relational、实例权重、文本省略字典推断、完整 Weka 扩展或机器学习训练。**0.2.0 已补全 Date、Relational 和实例权重，当前边界以 README 和下方 2026-11-13 复核为准。**发布前再次执行核心 MoonCakes 与 GitHub 查询，复核结果保存在独立审计记录。索引延迟、私有仓库、搜索上限和未遍历的源码路径仍构成限制；不保证全球唯一，不声称组委会已认可。


## 2026-11-13 格式补全复核

本次保留现有项目，补全 Date、嵌套 Relational、实例权重及增量流式接口；不是重新选题。重新执行 GitHub 的 ARFF/Weka 仓库检索与 relation+attribute、parse_arff、loadarff 代码检索（per_page=100，均无 incomplete 结果）。ARFF 仓库检索仅返回本项目；其他四项未返回候选。

MoonCakes 重跑 arff、weka、parse_arff、loadarff、libsvm、attribute relation（limit=100）。前三项只返回本模块0.1.0，loadarff/libsvm没有结果。attribute relation 的17个结果为 Office/XML、ER图、ORM、文档结构等方向，从其公开功能说明未见 ARFF 数据集协议的直接替代能力；关键词中的 relation 不等于 Weka Relational。保留此前 MoonFrame/pandas 的表格处理与 moonsplit 的数据集划分边界比较，不把这些相邻方向说成不存在。

本轮对照 Weka 3.8.6 的格式语义并执行真实 Java 双向测试；这是跨语言标准参考，不作为 MoonBit 内重复选题的证据。公开索引和先前源码阅读范围有限，结论仅为记录范围内没有发现直接成熟替代，不保证全球唯一。
