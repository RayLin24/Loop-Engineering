# 事件流规范与状态重放协议（event-spec）

`loop/events.jsonl` 是循环的**唯一事实源（single source of truth）**：一个只追加（append-only）的事件日志，每行一个 JSON 事件。任务的当前状态不存储在任何地方——它永远由**重放事件流**计算得出。任何一个新上下文读完 `TASKS.md` + 重放 `events.jsonl`，就能完整接管循环。

为什么是事件流而不是状态表：

- **追加一行是原子的**。最坏情况丢最后一行，此前历史完好；而全量重写状态表时中断 = 整个状态损坏。
- **重放是机械的**。恢复不依赖"LLM 按协议对账"的纪律，而是确定性计算。
- **历史免费**。每任务尝试次数、耗时、失败分类，全部可从事件流统计，无需另行记忆。

`loop/state.md` 仍然存在，但降级为**投影**（projection）：每轮由主控从事件流重算生成，仅供人类与 `runner/` 驱动器查看进度。它损坏、过期、丢失都无害——重算即可。

## 目录布局（主控首轮初始化）

```
<项目根>/
├── TASKS.md              # 任务清单（人类编写，运行期对主控/Worker 只读）
├── LOOP.md               # 框架入口提示词
├── runner/               # 可选: 无人值守驱动器（框架自带, 见 runner/README.md）
├── .loop-worktrees/      # 任务隔离工作区（git worktree, 每任务每次尝试一个; 已 gitignore）
└── loop/                 # 运行时状态（已 gitignore, 不进版本库）
    ├── events.jsonl      # 事件流（本规范定义, 唯一事实源）
    ├── state.md          # 人类进度视图（投影, 每轮重算）
    ├── decisions.md      # 决策索引（投影, 每轮重算）
    ├── lessons.md        # 经验教训（Meta-Analyst 维护, 只进 Worker 阅读清单, 见 meta-spec）
    ├── briefs/           # 主控 → Worker 的任务简报（含 *.verify.md 验证简报）
    ├── reports/          # Worker → 主控 的回执（重试时上次尝试归档为 <id>.attempt<n>.md）
    ├── verdicts/         # Verifier → 主控 的裁决
    ├── checks/           # 机械检查脚本（验收标准编译产物, 回归保护, 见 handoff-spec）
    ├── questions/        # 主控 → 人类 的提问（等待回答, 见 handoff-spec）
    ├── inbox/            # 人类 → 主控 的指令（含 done/ 子目录存档, 见 handoff-spec）
    ├── meta/             # 元分析报告（Meta-Analyst → 主控, 按轮次留档）
    └── FINAL.md          # 终局报告（全部完成后生成）
```

初始化时主控还须保证：项目已是 git 仓库且有基线提交（worktree 事务依赖它，见 handoff-spec）；`.gitignore` 含 `loop/` 与 `.loop-worktrees/` 两行（追加，不覆盖既有内容）。

## 事件格式

每行一个 JSON 对象，公共字段：

```jsonl
{"seq": 17, "ts": "2026-07-08T14:30:00Z", "type": "dispatched", ...}
```

- `seq`：单调递增整数（上一行的 seq + 1）。
- `ts`：ISO 8601 时间。
- `type`：事件类型（见下）。

**写入纪律**：一个事件 = 一次追加命令（shell 追加重定向或等价物），**永远不重写、不编辑此文件**。追加前先读文件末行获得当前 seq。**半行容忍**：追加过程中崩溃可能留下半行 JSON——重放时末行若不是合法 JSON，忽略之（视同该事件未发生，由恢复流程补偿）。

## 事件类型

### 状态事件（决定任务状态，同一任务 last-wins）

| type | 附加字段 | 含义 → 任务状态 |
|---|---|---|
| `dispatched` | `task, attempt, lease_expires, worktree, base?` | 已派发 Worker → `dispatched`。`base` 是当时的主干分支名（游离 HEAD 时为 commit sha）；旧事件没有该字段时，越界检查回退到当前主干 |
| `task_done` | `task, attempt` | 验收通过且已落地 → `done`（终态） |
| `task_failed` | `task, attempt, class, counts_retry, reason` | 本次尝试失败 → `failed`（待重试） |
| `task_blocked` | `task, reason` | 重试耗尽或需人工 → `blocked` |
| `task_waiting` | `task, question` | 等待人类回答 `loop/questions/<task>.md` → `waiting_human` |
| `task_reset` | `task, reason` | 人工解救 / 问题已回答 / 指令重置 → `pending` |

### 记录事件（证据与审计，不改变状态）

| type | 附加字段 | 含义 |
|---|---|---|
| `init` | `tasks, max_ticks` | 首次启动，校验通过。`max_ticks` = 3×任务数（至少为 1），是整份清单的轮次保险丝，不是「每会话 tick 上限」 |
| `session` | `gen` | 一个主控会话开始（第 gen 代；每次冷启动接管时追加） |
| `config` | `key, old, new, source` | 运行配置变更。`key` 只用 meta-spec 的规范名；`source` 为 `meta/round<N>.md` 或 `inbox/<file>`。主控是执行守门人 |
| `tasks_synced` | `added, revised, removed` | TASKS.md 修订已同步 |
| `report` | `task, attempt, result, failure_class?` | 回执已读取 |
| `checks` | `task, attempt, pass, failed?` | 机械检查脚本结果（单任务编译或落地后回归） |
| `verdict` | `task, attempt, pass, warns` | 裁决已读取 |
| `landed` | `task, attempt, commit` | 工作区分支已合并主干 |
| `discarded` | `task, attempt, reason` | 工作区已丢弃（回滚/中断/冲突/验收失败） |
| `regression` | `task, caused_by, failed_checks` | done 任务的 checks 被后续落地破坏 |
| `lease_expired` | `task, attempt` | 租约超时，按中断处理 |
| `decision` | `task, scope, text` | 验收通过任务的关键决策（scope 规则见 handoff-spec） |
| `note` | `text` | 跨轮备忘（含"建议追加任务"，人类在修订 TASKS.md 时采纳） |
| `tick` | `n, summary` | 一轮结束（一句话决策摘要） |
| `final` | - | 全部完成，FINAL.md 已生成 |

## 失败类别词表（`task_failed.class` 与循环度量的固定词表）

| class | 含义 | counts_retry |
|---|---|---|
| `acceptance` | 裁决不通过（含回归破坏） | true |
| `honest` | Worker 自查诚实报 ❌ | **首次 false**，第二次起 true |
| `constraint` | 约束违反 / 越界写入 | true |
| `report_missing` | 回执缺失或格式残缺 | true |
| `transient` | 中断、租约超时（不是 Worker 的过错） | false |
| `conflict` | 合并冲突（后到者被拒） | false |
| `environment` | 环境噪音（复核推翻的假失败） | false |

`counts_retry: false` 的失败不消耗重试上限；可疑裁决复核推翻的假失败只记日志与度量备注，不产生 `task_failed`。

## 重放规则（任意新上下文接管的第一步）

顺序扫描 `events.jsonl` 一遍（末行非法 JSON 忽略），得出：

1. **每任务状态** = 该任务**最后一条状态事件**的映射结果；从未出现过状态事件的任务 = `pending`。
2. **每任务尝试次数** = 该任务 `dispatched` 事件中最大的 `attempt`。
3. **每任务已消耗重试数** = 该任务 `counts_retry: true` 的 `task_failed` 事件数。
4. **决策索引** = 全部 `decision` 事件。
5. **运行配置** = 白名单五项各自的 `config` 事件 last-wins（规范 key 与默认值见 meta-spec）。不认识的 key 忽略。`source` 以 `meta/` 开头且 key 为 `max_ticks` 的事件一律忽略，并在本轮 `note` 里记下这次拒绝。
6. **max_ticks** = 最后一条有效的 `key: "max_ticks"` 的 `config.new`；否则 `init.max_ticks`；再否则 `3×当前任务数`。
7. **待记备忘** = 全部 `note` 事件（已失效的可忽略，判断依据是内容本身）。
8. **当前轮次** = 最后一条 `tick` 事件的 `n`（无则为 0）；**当前代次** = 最后一条 `session` 事件的 `gen`（无则为 0）。`session` 每个主控会话只追加一次，不是每轮一次。
9. **循环度量** = 每任务的尝试数、结局、最近一次 `task_failed.class` 汇总。

## 状态机

```
pending ──派发──> dispatched ──验收通过且 checks 全绿──> done (终态)
                     │
              失败(裁决/checks/回归/中断/冲突/越界)
                     ▼
                  failed ──带反思重试(下一轮)──> dispatched
                     │
        确定性失败达重试上限 / 连续 2 次租约超时
                     ▼
                  blocked ──人工解救(inbox 指令 → task_reset)──> pending

任一非终态 ──需要人类决策──> waiting_human ──问题文件出现答案(task_reset)──> pending
```

`environment` 不产生 `task_failed`（复核推翻的假失败只留在日志和度量备注里）。git 身份未配置、缺少 bash 这类环境缺口走 `waiting_human`，不要记成可以无限重试的 `transient`。

## 租约（lease）：时间上限即故障检测

每个 `dispatched` 事件必须携带 `lease_expires` = 派发时刻 + 该任务的 `timeout`（任务清单可选字段，默认 **30 分钟**）。

- 每轮开始时机械检查所有 `dispatched` 任务：**回执已出现** → 正常走验收；**回执未出现且租约未过期** → 视为仍在执行，跳过（冷启动时上一会话已死、但租约还没到，也会走到这里）；**回执未出现且租约已过期** → 追加 `lease_expired`，丢弃其工作区（`discarded`；目录或分支已经不在就算清理成功），追加 `task_failed`（`class: "transient", counts_retry: false`——中断不是 Worker 的过错，不消耗重试）。
- **防误杀**：若被判超时的 Worker 其实还在跑，无碍——它在自己的隔离工作区里，重派的新尝试在另一个工作区，先通过验收者落地，后到者合并会被拒绝丢弃（见 handoff-spec 事务规则）。
- 同一任务**连续 2 次**租约超时 → 不再重派，追加 `task_blocked`（大概率是任务本身会挂死，如等待永不返回的命令），升级人工。
- 崩溃、人为中断、超时挂死，三种故障**走完全相同的恢复路径**——这是刻意的：不为不同故障发明不同恢复分支。

## 投影文件

主控每轮结束时从重放结果重新生成（覆盖写，损坏无害）：

### `loop/state.md`（人类进度视图 + runner 判停依据）

```markdown
# Loop State（投影 — 事实源是 events.jsonl, 本文件可随时重算）
- 项目: <项目名> | 清单: TASKS.md (N 任务) | tick: 12/60 | 更新: <ISO 时间>
- 状态: running
- 等待租约: 无
- 会话: 第 2 代（本代已完成 2 轮）

## 运行配置（config 事件重放; key 见 meta-spec, 不要改用别的拼法）
- max_parallel: 3 | max_retries: 2 | ticks_per_session: 3 | lessons: on | verify_level: standard

## 任务状态表
| id | 状态 | 尝试 | 已耗重试 | 备注 |
|---|---|---|---|---|
| T1 | done | 1 | 0 | |
| T3 | failed | 2 | 1 | 上次: URL 格式校验缺失 |
| T7 | waiting_human | 1 | 0 | 等待回答 questions/T7.md |

## 循环度量（事件流统计, Meta-Analyst 的主要输入）
| id | 尝试 | 结局 | 失败类别 |
| T1 | 1 | done | - |
| T3 | 2 | 重试中 | acceptance |

## 备忘（note 事件重放, 跨轮需要记住的事）
- T4 回执提到 API 限流，T6 派发时需在简报中提醒。

## 近期轮次摘要（最后 10 条 tick/session/config 事件）
- [轮11] T3 裁决不通过(URL校验), 带反思重试。
- [轮12] T3 通过并落地; 回归 checks 全绿。
```

**机器可读的三行**（runner 只解析这些，写错就不会停在该停的地方）：

| 行 | 规则 |
|---|---|
| `项目` 行里的 `tick: <n>/<max_ticks>` | `<n>` 是最后一条 `tick` 事件的 `n`。驱动器用这个分子判断有没有进展，备忘里另写的 `tick:` 不算 |
| `状态` | **只能是** `running`、`waiting-human`、`finished` 三者之一，单独占这一行的值。不要写成 `running \| waiting-human \| finished`，不要在同一行加注释。任务状态里的 `waiting_human`（下划线）是另一个字段，不要写到这里 |
| `等待租约` | 平时写 `无`。只有「没有就绪任务，但存在回执未到且租约未到期的 dispatched」时，写成那些租约里最早的 `lease_expires`（UTC，形如 `2026-07-08T15:00:00Z`）。这一轮不要追加 `tick`，写完投影就结束会话 |

**`状态` 字段派生规则**（runner 的判停依据，主控每轮写入）：

| 值 | 条件 | runner 动作 |
|---|---|---|
| `finished` | 每个任务都是 `done`，且本轮已经追加 `final`、写好 FINAL.md | 退出 0 |
| `waiting-human` | 没有就绪任务，也没有未到期的在途 `dispatched`，并且存在 `blocked`/`waiting_human` 任务；或 tick 达到 max_ticks 保险丝 | 退出 2，通知人类 |
| `running` | 其余一切情况，包括还有未完成任务、以及会话中途崩溃 | 拉起新会话续跑 |

历史 `final` 事件**不会**把循环永久钉在 `finished`。人类之后往 TASKS.md 增加的任务按修订协议是 `pending`，只要还存在未完成任务，状态就回到 `running` 并继续调度。下次全部完成时覆盖 FINAL.md，再追加一条 `final`（旧的留在事件流里）。驱动器不读事件流：它只相信投影里的 `状态` 行。因此终局之后若只改了 TASKS.md 就立刻跑 runner，驱动器仍会看到 `finished` 并退出；需要先有一轮「按 LOOP.md 继续」把投影改回来。`loop/FINAL.md` 单独存在、但投影写着 `running` 时，以投影为准（终局文件可能是上一轮留下的）。

### `loop/decisions.md`（决策索引投影）

全部 `decision` 事件按时间列出，每条一行：`- [<task-id>][<scope>] <text>`（如 `- [T1][naming] 存储键名统一以 "bm:" 为前缀`）。主控组装简报时按 scope **筛选**相关条目写进阅读清单（只列 scope 名，不抄内容），Worker 自行按 scope 匹配读取——不全文注入（见 handoff-spec）。

## 冷启动恢复协议（每轮开头都重放）

重放、inbox、提问和租约检查**每一轮都做**。`session` 事件**每个主控会话只追加一次**（新会话的第一轮），不要每轮都追加——代次被刷高之后，「本代完成了几轮」就无法计算。

1. 读 `LOOP.md` → 读 `TASKS.md` → 重放 `loop/events.jsonl`。
2. 若是这个会话还没记过 `session`：追加 `session` 事件（gen = 上一代 + 1）。
3. 检查 `loop/inbox/` 有无人类指令、`loop/questions/` 有无新答案（处理规则见 handoff-spec）。
4. 对比 TASKS.md 与事件流已知任务集，处理修订（见下节）。
5. 按租约规则处理所有 `dispatched` 任务。处理完之后如果**没有就绪任务**、但仍有租约未到期的 `dispatched`：投影保持 `running`，`等待租约` 写成最早的到期时间，本轮不追加 `tick`，结束会话。还有别的就绪任务时不要停，照常派发。
6. 进入正常轮次流程。

`events.jsonl` 不存在 → 首次启动：校验 TASKS.md（id 唯一、依赖无环、touches 并行度提醒），确认 git 基线与 `.gitignore`，初始化 `loop/` 目录，追加 `init` 事件。

## 会话边界（确定性轮换）

主控会话是一次性躯壳：每个会话最多服务「每会话 tick 上限」轮（运行配置 `ticks_per_session`，默认 3，白名单 1–5），**到轮就交，不做自我评估**——上下文余量的自我感知不可靠，确定性轮换把上下文管理从元认知问题降为计数问题。

落盘并重算投影之后、决定交接之前，先再判一次终止条件：全部任务 `done` → 写 FINAL.md、追加 `final`、`状态: finished`，直接结束，不要为了交接再交出一个其实已经做完的 `running`；没有就绪任务且需要人工 → `状态: waiting-human` 并停止。只有仍有未完成工作、且本会话轮次已满时，才保持 `状态: running`（`等待租约: 无`），输出三行交接消息（本代完成几轮、任务 done x/总数、续跑方式），结束会话。若代内出现明显上下文退化（找不到早先记录、重复已做过的动作），允许提前交接，禁止硬撑。

## 任务清单修订协议（TASKS.md 变更同步）

`TASKS.md` 对主控和 Worker 只读，人类可随时修订（无需等循环暂停——每轮开头会重读）。主控在轮次开头发现 TASKS.md 与事件流已知任务集不一致时：

- **新增任务**：补入（重放视为 `pending`），重新校验依赖无环，追加 `tasks_synced`。主控在 `note` 事件中登记的"建议追加任务"，也由人类在此时采纳落笔——主控自己永不写 TASKS.md。
- **修改任务**：仅 `pending` 状态的任务生效；`done` 任务的需求变化必须走追加修复任务（`depends_on` 指向原任务）；`dispatched/failed/blocked/waiting_human` 的修改暂不生效并在 state.md 备注提醒人类。
- **删除任务**：仅 `pending` 可删，且需校验无其他任务依赖它。

## 兼容与迁移

事件类型没有删除，旧事件照常重放。下面几条会改变主控或驱动器的行为，正在跑的循环从下一轮按新协议执行即可，不必改写已有的 `events.jsonl`：

- 投影「状态」行只能是 `running` / `waiting-human` / `finished` 之一。把三个值用竖线写在同一行时，驱动器会当成无法解析，并在停滞保险丝处停下，不再误读成永远的 `running`。
- 任务状态 `waiting_human`（下划线）和投影状态 `waiting-human`（连字符）不是同一个字段。
- 历史 `final` 事件不再让循环无视新任务。清单里出现未完成任务时，状态回到 `running`。
- `max_ticks` 的人工修改必须落成 `config` 事件（`key` 为 `max_ticks`，`source` 指向 inbox 文件）。只写在备忘里的调整，重放后会丢。Meta-Analyst 仍然不能改这个键。
- `config.key` 以 meta-spec 的规范名为准（`max_parallel`、`max_retries`、`ticks_per_session`、`lessons`、`verify_level`）。以前如果用了别的拼法，重放时认不出来，会退回默认值；需要的话由人类用 inbox 指令重写一次。
- `dispatched` 可以多带可选字段 `base`。没有该字段的旧事件，越界检查用当前主干。
- 投影新增「等待租约」行。旧投影没有这一行时，驱动器不等待，行为与加上这一行之前相同。
- 同一失败类别触发元分析的窗口，改为自上一次元分析以来，不再是从循环开头的累计值。已经累计超过 3 次的旧循环，不会因此每轮都再派一次 Meta-Analyst。
