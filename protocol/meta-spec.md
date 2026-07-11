# 元循环规范（meta-spec）— 双层循环

内层循环（主控 + Worker + Verifier）优化的是**任务产出**；元循环优化的是**循环自身的运行方式**。设计参考两个上游项目：

- [karpathy/autoresearch](https://github.com/karpathy/autoresearch)：「评测不可被优化对象篡改」原则（`prepare.py` 只读）与量化实验台账（`results.tsv`）。
- [EdwardOptimization/Bilevel-Autoresearch](https://github.com/EdwardOptimization/Bilevel-Autoresearch)（arXiv:2603.23420）：双层结构——外层分析内层轨迹并调整其搜索方式，消融实验显示相对单层 5× 增益；以及关键隔离约束「经验只影响提案，永不影响评判」。

## 三层职责划分

| 层 | 角色 | 优化对象 | 生效方式 |
|---|---|---|---|
| Level 1（内层） | 主控 / Worker / Verifier | 任务产出 | 正常调度循环 |
| Level 1.5（配置层） | Meta-Analyst | 运行配置（白名单内） | 主控直接应用到 state.md |
| Level 2（机制层） | Meta-Analyst | prompts / protocol / TASKS.md 写法 | **只写建议留给人类**，运行期间机制不可自改 |

Level 1.5 管战术调整（"并行度降到 1"、"关闭 lessons 注入"），Level 2 管结构发现（"验收标准普遍写得不可验证，建议下份清单如何改"）。分开是为了让机制发现不被参数微调稀释——这是 Bilevel 消融实验中 C 组胜出的原因。

## 触发时机

主控在每轮落盘后检查，满足任一条件即派发一次 Meta-Analyst（一次性子代理，同一轮最多一次）：

1. 自上次元分析起已过 **5 轮**；
2. 本轮有任务进入 `blocked`；
3. 「循环度量」表中同一失败类别累计出现 **≥3 次**。

派发指令："读 `prompts/meta-analyst.md` 并遵守其中规则，然后基于 `loop/state.md` 与 `loop/` 下的归档回执/裁决完成元分析，写出 `loop/meta/round<N>.md`"（N 为当前轮次）。

主控读回报告后：应用「配置调整」到 state.md 的运行配置节（越出白名单的调整拒绝并记日志），在日志记一条元分析结论摘要。

## 控制面白名单（Level 1.5 唯一可调项）

| 配置项 | 默认 | 允许范围 |
|---|---|---|
| 每批并行上限 | 3 | 1–3 |
| 每任务重试上限 | 2 | 0–3 |
| 每代最大轮次 | 3 | 1–5（调小 = 主控更早交接更保守; 降级串行模式下主控自行固定为 1, 不受此项调整） |
| lessons 注入 Worker 简报 | 开 | 开 / 关 |
| 验证抽查强度 | 标准 | 标准 / 严格（严格 = 验证简报中要求 Verifier 通读全部产出物而非抽查） |

白名单之外一切不可调：最大轮次保险丝（只有人类可改）、验收标准、协议与提示词文件、TASKS.md。当前值记录在 state.md「运行配置」节。

## 经验教训 `loop/lessons.md`

由 Meta-Analyst 维护（每次元分析**全量重写**，≤20 行）：从归档的失败尝试与裁决中提炼**跨任务可复用**的教训。写模式不写个案——"T3 忘了跑测试"是个案；"本项目 Worker 普遍漏跑 `npm test`，简报应显式列出命令"是模式。

**隔离约束（Bilevel 关键规则）**：lessons 只进 **Worker 的阅读清单**（影响提案），**Verifier 的禁读清单明令禁止读取**（不得影响裁决）。评审者被"经验"预设立场，验收就失去独立性——同理 `loop/decisions.md` 也在 Verifier 禁读清单中。

## 元分析报告格式 `loop/meta/round<N>.md`

```markdown
# 元分析: 第 <N> 轮
- 触发原因: <定期 | blocked | 失败类别重复>

## 轨迹诊断
<2–5 行: 从度量表与日志中观察到的模式。例:
 "3 个任务共 5 次失败, 4 次属『验收不达标』且都栽在同一条模糊标准上">

## 配置调整  <!-- 仅白名单项; 无调整写"无" -->
- 每批并行上限: 3 → 1（原因: 两次越界写入均发生在并行批中）

## 经验教训更新
<本次写入 loop/lessons.md 的完整内容, 或"无变化">

## 机制建议  <!-- Level 2, 只留给人类, 主控不执行 -->
- <对 prompts/protocol/TASKS.md 写法的结构性建议, 每条注明依据>
```

报告 ≤40 行。历次报告按轮次留档不覆盖，`FINAL.md` 汇总全部「机制建议」。

## 铁律边界（评测不可篡改原则）

1. **prompts/ 与 protocol/ 运行期间对所有角色只读**——包括 Meta-Analyst。被优化的循环不得自改评分规则，这是 Karpathy 方案中 `prepare.py` 只读的直接对应。
2. Meta-Analyst **不读产出物、不跑命令**，只依据 state.md（度量 + 日志 + 配置）与归档的回执/裁决。它分析的是循环的轨迹，不是任务的内容。
3. Meta-Analyst 只写 `loop/meta/` 与 `loop/lessons.md`，其余一切只读。
4. 配置调整必须落在白名单范围内，主控是执行守门人。
