# 事件流规范与状态重放协议（event-spec）

`loop/events.jsonl` 是循环的**唯一事实源（single source of truth）**：一个只追加（append-only）的事件日志，每行一个 JSON 事件。任务的当前状态不存储在任何地方——它永远由**重放事件流**计算得出。任何一个新上下文读完 `TASKS.md` + 重放 `events.jsonl`，就能完整接管循环。

为什么是事件流而不是状态表：

- **追加一行是原子的**。最坏情况丢最后一行，此前历史完好；而全量重写状态表时中断 = 整个状态损坏。
- **重放是机械的**。恢复不依赖"LLM 按协议对账"的纪律，而是确定性计算。
- **历史免费**。每任务尝试次数、耗时、失败分类，全部可从事件流统计，无需另行记忆。

`loop/state.md` 仍然存在，但降级为**投影**（projection）：每 tick 由主控从事件流重算生成，仅供人类查看进度。它损坏、过期、丢失都无害——重算即可。

## 事件格式

每行一个 JSON 对象，公共字段：

```jsonl
{"seq": 17, "ts": "2026-07-08T14:30:00Z", "type": "dispatched", ...}
```

- `seq`：单调递增整数（上一行的 seq + 1）。
- `ts`：ISO 8601 时间。
- `type`：事件类型（见下）。

**写入纪律**：一个事件 = 一次追加命令（shell 追加重定向或等价物），**永远不重写、不编辑此文件**。追加前先读文件末行获得当前 seq。

## 事件类型

### 状态事件（决定任务状态，同一任务 last-wins）

| type | 附加字段 | 含义 → 任务状态 |
|---|---|---|
| `dispatched` | `task, attempt, lease_expires, worktree` | 已派发 Worker → `dispatched` |
| `task_done` | `task, attempt` | 验收通过且已落地 → `done`（终态） |
| `task_failed` | `task, attempt, class, counts_retry, reason` | 本次尝试失败 → `failed`（待重试） |
| `task_blocked` | `task, reason` | 重试耗尽或需人工 → `blocked` |
| `task_waiting` | `task, question` | 等待人类回答 `loop/questions/<task>.md` → `waiting_human` |
| `task_reset` | `task, reason` | 人工解救 / 指令重置 → `pending` |

### 记录事件（证据与审计，不改变状态）

| type | 附加字段 | 含义 |
|---|---|---|
| `init` | `tasks, max_ticks` | 首次启动，校验通过 |
| `tasks_synced` | `added, revised, removed` | TASKS.md 修订已同步 |
| `report` | `task, attempt, result, failure_class?` | 回执已读取 |
| `checks` | `task, attempt, pass, failed?` | 机械检查脚本结果 |
| `verdict` | `task, attempt, pass, warns` | 裁决已读取 |
| `landed` | `task, attempt, commit` | 已合并主干 |
| `discarded` | `task, attempt, reason` | 工作区已丢弃（回滚/中断/冲突） |
| `regression` | `task, caused_by, failed_checks` | done 任务的 checks 被后续落地破坏 |
| `lease_expired` | `task, attempt` | 租约超时，按中断处理 |
| `decision` | `task, scope, text` | 验收通过任务的关键决策（scope 见 handoff-spec） |
| `note` | `text` | 跨 tick 备忘 |
| `tick` | `n, summary` | 一个 tick 结束（一句话决策摘要） |
| `final` | - | 全部完成，FINAL.md 已生成 |

## 重放规则（任意新上下文接管的第一步）

顺序扫描 `events.jsonl` 一遍，得出：

1. **每任务状态** = 该任务**最后一条状态事件**的映射结果；从未出现过状态事件的任务 = `pending`。
2. **每任务尝试次数** = 该任务 `dispatched` 事件中最大的 `attempt`。
3. **每任务已消耗重试数** = 该任务 `counts_retry: true` 的 `task_failed` 事件数。
4. **决策索引** = 全部 `decision` 事件。
5. **待记备忘** = 全部 `note` 事件（已失效的可忽略，判断依据是内容本身）。
6. **当前 tick 序号** = 最后一条 `tick` 事件的 `n`（无则为 0）。

## 状态机

```
pending ──派发──> dispatched ──验收通过+落地──> done (终态)
                     │
              失败(裁决/checks/回归/中断/冲突)
                     ▼
                  failed ──带反思重试──> dispatched
                     │
        确定性失败达重试上限(2次) / 环境性失败
                     ▼
                  blocked ──人工解救(task_reset)──> pending

任一状态 ──需要人类决策──> waiting_human ──问题文件出现答案──> pending
```

## 租约（lease）：时间上限即故障检测

每个 `dispatched` 事件必须携带 `lease_expires` = 派发时刻 + 该任务的 `timeout`（任务清单可选字段，默认 **30 分钟**）。

- 每 tick 开始时机械检查所有 `dispatched` 任务：**回执已出现** → 正常走验收；**回执未出现且租约未过期** → 视为仍在执行，跳过（仅并行/异步派发时会出现）；**回执未出现且租约已过期** → 追加 `lease_expired`，丢弃其工作区（`discarded`），追加 `task_failed`（`class: "transient", counts_retry: false`——中断不是 Worker 的过错，不消耗重试）。
- **防误杀**：若被判超时的 Worker 其实还在跑，无碍——它在自己的隔离工作区里，重派的新尝试在另一个工作区，先通过验收者落地，后到者合并会被拒绝丢弃（见 handoff-spec 事务规则）。
- 同一任务**连续 2 次**租约超时 → 不再重派，追加 `task_blocked`（大概率是任务本身会挂死，如等待永不返回的命令），升级人工。
- 崩溃、人为中断、超时挂死，三种故障**走完全相同的恢复路径**——这是刻意的：不为不同故障发明不同恢复分支。

## 投影文件

主控每 tick 结束时从重放结果重新生成（覆盖写，损坏无害）：

### `loop/state.md`（人类进度视图）

```markdown
# Loop State（投影 — 事实源是 events.jsonl, 本文件可随时重算）
- 项目: <项目名> | 清单: TASKS.md (N 任务) | tick: 12/60 | 更新: <ISO 时间>

## 任务状态表
| id | 状态 | 尝试 | 已耗重试 | 备注 |
|---|---|---|---|---|
| T1 | done | 1 | 0 | |
| T3 | failed | 2 | 1 | 上次: URL 格式校验缺失 |
| T7 | waiting_human | 1 | 0 | 等待回答 questions/T7.md |

## 近期 tick 摘要（最后 10 条 tick 事件）
- [tick 11] T3 裁决不通过(URL校验), 带反思重试。
- [tick 12] T3 通过并落地; 回归 checks 全绿。
```

### `loop/decisions.md`（决策索引投影）

全部 `decision` 事件的列表，每条一行：`- [<task-id>][<scope>] <text>`（如 `- [T1][naming] 存储键名统一以 "bm:" 为前缀`）。主控组装简报时从此索引**筛选**与目标任务相关的条目（scope 与其 touches/依赖匹配者）注入，而非全文注入。

## 冷启动恢复协议

任何新会话/新 tick 接管时（这不是特殊流程——**每个 tick 都这么开始**，冷启动只是碰巧上一 tick 在另一个会话里）：

1. 读 `LOOP.md` → 读 `TASKS.md` → 重放 `loop/events.jsonl`。
2. 检查 `loop/inbox/` 有无人类指令、`loop/questions/` 有无新答案（见 handoff-spec）。
3. 按租约规则处理所有 `dispatched` 任务。
4. 进入正常 tick 流程。

`events.jsonl` 不存在 → 首次启动：校验 TASKS.md，初始化 `loop/` 目录，追加 `init` 事件。

## 任务清单修订协议（TASKS.md 变更同步）

`TASKS.md` 对主控和 Worker 只读，人类可随时修订（无需等循环暂停——每 tick 开头会重读）。主控在 tick 开头发现 TASKS.md 与事件流已知任务集不一致时：

- **新增任务**：补入（重放视为 `pending`），重新校验依赖无环，追加 `tasks_synced`。
- **修改任务**：仅 `pending` 状态的任务生效；`done` 任务的需求变化必须走追加修复任务（`depends_on` 指向原任务）；`dispatched/failed/blocked/waiting_human` 的修改暂不生效并在 state.md 备注提醒人类。
- **删除任务**：仅 `pending` 可删，且需校验无其他任务依赖它。
