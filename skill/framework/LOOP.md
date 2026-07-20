# LOOP.md — Loop Engineering 框架入口

> 对 LLM 说一句「**按 LOOP.md 接管任务清单**」，循环即开始。无人值守跑完全程：`./runner/run-loop.sh`（或 `.\runner\run-loop.ps1`）。

## 这是什么

一个零代码的自主循环工作流框架：你提供一份标准化任务清单（`TASKS.md`），LLM 主控自动拆解调度、派发子任务执行、独立验收、合并落地、回归保护，循环直至清单完成。全部状态外置于 `loop/events.jsonl`（只追加事件流），任意时刻中断都可无损续跑。

两个关键设计：**事件溯源**——状态永远由重放事件流算出，崩溃恢复是确定性计算而非纪律；**会话轮换**——主控会话是一次性躯壳，每个会话最多跑固定轮数即落盘退出，下一个会话重放事件流接管（避免长会话上下文退化；可选的 `runner/` 驱动器自动接续直至完成）。另有**元循环**（双层设计，参考 karpathy/autoresearch 与 Bilevel-Autoresearch）——循环定期分析自身运行轨迹，调整运行配置、提炼经验教训注入后续任务。

## 移植到新项目（三步）

1. 把本框架的 `LOOP.md`、`protocol/`、`prompts/`（可选 `runner/`）复制到项目根目录。
2. 参照 `protocol/task-list-spec.md` 编写你的 `TASKS.md`（可从 `examples/TASKS.example.md` 改起）。
3. 启动：对 LLM 说「按 LOOP.md 接管任务清单」（每个会话结束后你说「按 LOOP.md 继续」接力）；或运行 `runner/` 驱动器无人值守跑完。
   **注意**：写 TASKS.md 与跑循环务必分属不同会话——主控应从干净上下文起跑，别让它背着勘察和写清单的包袱进循环。

**前置要求**：项目必须是 git 仓库（任务在独立 git worktree 中执行、合并落地、回归保护都依赖它）。不是仓库也无妨——主控首次启动会自行 `git init` 并提交基线。

## LLM 接管指令（LLM 从这里开始读）

你被指定为本项目的循环主控——**一个会话**的主控：最多服务「每会话 tick 上限」轮（运行配置，见 state.md 投影）即交接退出。执行以下步骤：

1. **读取角色与协议**：依次阅读——
   - `prompts/orchestrator.md`（你的角色与主循环逻辑，铁律优先级最高）
   - `protocol/task-list-spec.md`（任务清单怎么读）
   - `protocol/event-spec.md`（事件流、重放规则、投影、租约、冷启动恢复）
   - `protocol/handoff-spec.md`（指针式简报/回执/裁决、工作区事务、人机通道、重试规则）
   - `protocol/meta-spec.md`（元循环：触发时机、配置白名单、隔离约束）
2. **判断启动模式**：
   - `loop/events.jsonl` **不存在** → 首次启动：校验 `TASKS.md`，确认 git 基线与 `.gitignore`，初始化 `loop/` 目录并追加 `init`/`session` 事件，进入主循环。
   - `loop/events.jsonl` **已存在** → 续跑：执行 `protocol/event-spec.md` 中的冷启动恢复协议（重放 + session 登记 + inbox/questions/租约处理），进入主循环。
3. **循环直至本会话到达以下任一终点**（届时按协议落盘并更新投影状态）：
   - 全部任务 `done` → 生成 `loop/FINAL.md` 终局报告（`状态: finished`），向用户汇报。
   - 存在无法推进的 `blocked`/`waiting_human` 任务 / 轮次保险丝触发 → `状态: waiting-human`，汇总失败史与待答问题，请求人工介入。
   - 本会话轮次用满 → `状态: running` 落盘，输出三行交接消息，结束会话（由人类或 runner 拉起下一代）。

## 文件地图

```
<项目根>/
├── LOOP.md                      # 本文件（入口）
├── TASKS.md                     # 任务清单（你来写, 唯一输入）
├── protocol/                    # 协议规范（框架自带, 勿改）
│   ├── task-list-spec.md
│   ├── event-spec.md
│   ├── handoff-spec.md
│   └── meta-spec.md
├── prompts/                     # 角色提示词（框架自带, 勿改）
│   ├── orchestrator.md
│   ├── worker.md
│   ├── verifier.md
│   └── meta-analyst.md
├── runner/                      # 可选: 无人值守驱动器（run-loop.ps1 / run-loop.sh）
├── .loop-worktrees/             # 任务隔离工作区（git worktree, 主控维护, 已 gitignore）
└── loop/                        # 运行时状态（主控自动创建与维护, 已 gitignore）
    ├── events.jsonl             # 唯一事实源（只追加事件流）
    ├── state.md                 # 进度视图（投影, 每轮重算, runner 判停依据）
    ├── decisions.md             # 决策索引（投影, 跨任务传递关键决策）
    ├── lessons.md               # 经验教训（元循环提炼, 只进 Worker 阅读清单）
    ├── briefs/                  # 任务简报（主控→Worker; 含 *.verify.md 验证简报）
    ├── reports/                 # 任务回执（Worker→主控）
    ├── verdicts/                # 验证裁决（Verifier→主控）
    ├── checks/                  # 回归检查脚本（验收标准编译产物）
    ├── questions/               # 主控→人类的提问（待回答）
    ├── inbox/                   # 人类→主控的指令（done/ 为已处理存档）
    ├── meta/                    # 元分析报告（Meta-Analyst→主控, 按轮次留档）
    └── FINAL.md                 # 终局报告
```

## 人类操作速查

| 你想… | 怎么做 |
|---|---|
| 启动 / 接力续跑 | 「按 LOOP.md 接管任务清单」/「按 LOOP.md 继续」 |
| 无人值守跑完全程 | 项目根运行 `./runner/run-loop.sh` 或 `.\runner\run-loop.ps1`（权限模式须知见 `runner/README.md`） |
| 查看进度 | 打开 `loop/state.md`（投影，`状态` 一眼判断：running/waiting-human/finished） |
| 查看某任务详情 | 打开 `loop/reports/<id>.md`（历次失败尝试在 `<id>.attempt<n>.md`） |
| 查看某任务验证详情 | 打开 `loop/verdicts/<id>.md` |
| 回答主控的提问 | 打开 `loop/questions/<id>.md`，在「## 答案」节下填写，保存即可（下轮自动生效） |
| 解救 blocked 任务 | 解决根因后，在 `loop/inbox/` 写一个指令文件（内容如"重置 T5"），下轮自动处理 |
| 中途加/改/删任务 | 直接编辑 `TASKS.md`（无需暂停，每轮开头自动同步；仅 `pending` 任务可改可删，规则见 event-spec 修订协议） |
| 终止或暂停循环 | 在 `loop/inbox/` 写指令（如"终止循环"） |
| 查看元循环发现 | 打开 `loop/meta/round<N>.md`（配置调整与机制建议）与 `loop/lessons.md` |
| 采纳机制建议 | 循环结束后审阅 `FINAL.md`「机制建议汇总」，由你手动修订 prompts/protocol 或下一份 TASKS.md——运行期间框架文件对所有角色只读 |
