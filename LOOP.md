# LOOP.md — Loop Engineering 框架入口

> 对 LLM 说一句「**按 LOOP.md 接管任务清单**」，循环即开始。

## 这是什么

一个零代码的自主循环工作流框架：你提供一份标准化任务清单（`TASKS.md`），LLM 主控以 tick 为单位自动调度——派发子任务到隔离工作区执行、独立验收、合并落地、回归保护——循环直至清单完成。全部事实记录在一个只追加的事件日志里，任意时刻中断都可无损续跑（续跑与正常运行是同一条路径）。

## 移植到新项目（三步）

1. 把本框架的 `LOOP.md`、`protocol/`、`prompts/` 复制到项目根目录；项目若不是 git 仓库，`git init` 一下（一条命令，换来隔离工作区与失败回滚的全部事务能力）。
2. 参照 `protocol/task-list-spec.md` 编写你的 `TASKS.md`（可从 `examples/TASKS.example.md` 改起）。
3. 对 LLM 说：「按 LOOP.md 接管任务清单」。

## LLM 接管指令（LLM 从这里开始读）

你被指定为本项目的循环主控。执行以下步骤：

1. **读取角色与协议**：依次阅读——
   - `prompts/orchestrator.md`（你的 tick 流程，铁律优先级最高）
   - `protocol/task-list-spec.md`（任务清单怎么读）
   - `protocol/event-spec.md`（事件流、状态重放、租约、冷启动）
   - `protocol/handoff-spec.md`（事务工作区、简报/回执/裁决、checks、失败分类）
2. **判断启动模式**：
   - `loop/events.jsonl` **不存在** → 首次启动：校验 `TASKS.md`，初始化 `loop/`，追加 `init` 事件，进入 tick。
   - `loop/events.jsonl` **已存在** → 续跑：重放事件流重建状态，收租约，进入 tick——与每个普通 tick 的开头完全相同，没有特殊恢复流程。
3. **逐 tick 循环**直至以下任一终点：
   - 全部任务 `done` → 生成 `loop/FINAL.md`，向用户汇报。
   - 剩余任务全部 `blocked` 或 `waiting_human` → 汇总情况，等待人工（`waiting_human` 的任务在 `loop/questions/` 回答后即可续跑）。
   - 会话内已连续执行约 8–10 个 tick → 完成当前 tick 落盘后收尾，请用户新开会话说「按 LOOP.md 继续」。

## 文件地图

```
<项目根>/
├── LOOP.md                      # 本文件（入口）
├── TASKS.md                     # 任务清单（你来写, 唯一输入; 可随时修订, 每 tick 自动同步）
├── protocol/                    # 协议规范（框架自带, 勿改）
│   ├── task-list-spec.md
│   ├── event-spec.md
│   └── handoff-spec.md
├── prompts/                     # 角色提示词（框架自带, 勿改）
│   ├── orchestrator.md
│   ├── worker.md
│   └── verifier.md
└── loop/                        # 运行时（主控自动创建与维护）
    ├── events.jsonl             # 唯一事实源（只追加的事件日志）
    ├── state.md                 # 进度投影（人类视图, 可随时从事件重算）
    ├── decisions.md             # 决策索引投影
    ├── briefs/                  # 简报（主控→Worker; 含 *.verify.md 验证简报）
    ├── reports/                 # 回执（Worker→主控）
    ├── verdicts/                # 裁决（Verifier→主控）
    ├── checks/                  # 每任务的机械验收脚本（可重跑; 回归保护; 最终交付物）
    ├── questions/               # 主控 → 人类的问题（异步, 不阻塞其他任务）
    ├── inbox/                   # 人类 → 主控的指令（异步）
    ├── worktrees/               # 执行中任务的隔离工作区（git worktree, 用后即删）
    └── FINAL.md                 # 终局报告
```

## 人类操作速查

| 你想… | 怎么做 |
|---|---|
| 启动 / 续跑 | 「按 LOOP.md 接管任务清单」/「按 LOOP.md 继续」 |
| 查看进度 | 打开 `loop/state.md`（投影，即使过期也可让主控重算） |
| 查看某任务详情 | `loop/reports/<id>.attempt<n>.md`（历次尝试全部保留） |
| 查看某任务验证详情 | `loop/verdicts/<id>.attempt<n>.md` |
| 回答主控的提问 | 在 `loop/questions/<id>.md` 的「回答」节作答并把状态改为"已回答"——**无需暂停循环** |
| 给主控下指令（跳过任务/暂停等） | 往 `loop/inbox/` 放一个说明文件，下一 tick 被消费 |
| 解救 blocked 任务 | 解决根因后在 `loop/inbox/` 留指令"重置 T5"（或直接在续跑时说明） |
| 中途加/改任务 | 直接修订 `TASKS.md`——每 tick 开头自动同步（规则见 `protocol/event-spec.md`：仅 `pending` 可改可删；`done` 的需求变化走追加修复任务） |
| 手动重跑某任务的验收 | 执行 `loop/checks/<id>.sh` |
