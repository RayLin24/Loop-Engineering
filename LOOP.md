# LOOP.md — Loop Engineering 框架入口

> 对 LLM 说一句「**按 LOOP.md 接管任务清单**」，循环即开始。无人值守跑完全程：`./runner/run-loop.sh`（或 `.\runner\run-loop.ps1`）。

## 这是什么

一个零代码的自主循环工作流框架：你提供一份标准化任务清单（`TASKS.md`），LLM 主控自动拆解调度、派发子任务执行、验收回执、更新状态，循环直至清单完成。全部状态外置于文件，任意时刻中断都可无损续跑。

两个关键设计：**代际制主控**——主控会话是一次性躯壳，每代最多跑固定轮数即落盘退出，下一代读盘接管（避免长会话上下文退化，可选的 `runner/` 驱动器可自动接续直至完成）；**元循环**（双层设计, 参考 karpathy/autoresearch 与 Bilevel-Autoresearch）——循环定期分析自身运行轨迹，调整运行配置、提炼经验教训注入后续任务。

## 移植到新项目（三步）

1. 把本框架的 `LOOP.md`、`protocol/`、`prompts/`（可选 `runner/`）复制到项目根目录。
2. 参照 `protocol/task-list-spec.md` 编写你的 `TASKS.md`（可从 `examples/TASKS.example.md` 改起）。
3. 启动：对 LLM 说「按 LOOP.md 接管任务清单」（每代结束后你说「按 LOOP.md 继续」接力）；或运行 `runner/` 驱动器无人值守跑完。
   **注意**：写 TASKS.md 与跑循环务必分属不同会话——主控应从干净上下文起跑，别让它背着勘察和写清单的包袱进循环。

## LLM 接管指令（LLM 从这里开始读）

你被指定为本项目的循环主控——**一代**主控：最多服务「每代最大轮次」轮（state.md 运行配置）即交接退出。执行以下步骤：

1. **读取角色与协议**：依次阅读——
   - `prompts/orchestrator.md`（你的角色与主循环逻辑，铁律优先级最高）
   - `protocol/task-list-spec.md`（任务清单怎么读）
   - `protocol/state-spec.md`（状态文件、代际交接与冷启动恢复）
   - `protocol/handoff-spec.md`（指针式简报/回执/验收/重试规则）
   - `protocol/meta-spec.md`（元循环：触发时机、配置白名单、隔离约束）
2. **判断启动模式**：
   - `loop/state.md` **不存在** → 首次启动：校验 `TASKS.md`，初始化 `loop/` 目录与状态文件，进入主循环。
   - `loop/state.md` **已存在** → 续跑：执行 `protocol/state-spec.md` 中的冷启动恢复协议（代际登记 + 对账），进入主循环。
3. **循环直至本代到达以下任一终点**（届时按协议置 `循环状态` 并落盘退出）：
   - 全部任务 `done` → 生成 `loop/FINAL.md` 终局报告（`循环状态: finished`），向用户汇报。
   - 存在无法推进的 `blocked` 任务 / 轮次保险丝触发 → `循环状态: awaiting-human`，汇总失败史，请求人工介入。
   - 本代轮次用满 → `循环状态: handoff`，输出三行交接消息，结束会话（由人类或 runner 拉起下一代）。

## 文件地图

```
<项目根>/
├── LOOP.md                      # 本文件（入口）
├── TASKS.md                     # 任务清单（你来写, 唯一输入）
├── protocol/                    # 协议规范（框架自带, 勿改）
│   ├── task-list-spec.md
│   ├── state-spec.md
│   ├── handoff-spec.md
│   └── meta-spec.md
├── prompts/                     # 角色提示词（框架自带, 勿改）
│   ├── orchestrator.md
│   ├── worker.md
│   ├── verifier.md
│   └── meta-analyst.md
├── runner/                      # 可选: 无人值守驱动器（run-loop.ps1 / run-loop.sh）
└── loop/                        # 运行时状态（主控自动创建与维护）
    ├── state.md                 # 唯一事实源（含 循环状态/代次, 驱动器判停依据）
    ├── decisions.md             # 全局决策记录（跨任务传递关键决策）
    ├── lessons.md               # 经验教训（元循环提炼, 只进 Worker 阅读清单）
    ├── briefs/                  # 任务简报（主控→Worker; 含 *.verify.md 验证简报）
    ├── reports/                 # 任务回执（Worker→主控）
    ├── verdicts/                # 验证裁决（Verifier→主控）
    ├── meta/                    # 元分析报告（Meta-Analyst→主控, 按轮次留档）
    └── FINAL.md                 # 终局报告
```

## 人类操作速查

| 你想… | 怎么做 |
|---|---|
| 启动 / 接力续跑 | 「按 LOOP.md 接管任务清单」/「按 LOOP.md 继续」 |
| 无人值守跑完全程 | 项目根运行 `./runner/run-loop.sh` 或 `.\runner\run-loop.ps1`（权限模式须知见 `runner/README.md`） |
| 查看进度 | 打开 `loop/state.md`（`循环状态` 一眼判断: running/handoff/awaiting-human/finished） |
| 查看某任务详情 | 打开 `loop/reports/<id>.md`（历次失败尝试在 `<id>.attempt<n>.md`） |
| 查看某任务验证详情 | 打开 `loop/verdicts/<id>.md` |
| 解救 blocked 任务 | 解决根因后, 把 state.md 中该任务状态改回 `pending`, 再续跑 |
| 中途加任务 | 循环暂停时在 `TASKS.md` 追加（主控备忘中的"建议追加任务"也在此时由你采纳落笔）, 续跑时主控补入状态表 |
| 中途改任务 | 循环暂停时按 `protocol/state-spec.md` 的修订协议操作（仅 `pending` 任务可直接改; `done` 任务的需求变化走追加修复任务） |
| 查看元循环发现 | 打开 `loop/meta/round<N>.md`（配置调整与机制建议）与 `loop/lessons.md` |
| 采纳机制建议 | 循环结束后审阅 `FINAL.md`「机制建议汇总」, 由你手动修订 prompts/protocol 或下一份 TASKS.md——运行期间框架文件对所有角色只读 |
