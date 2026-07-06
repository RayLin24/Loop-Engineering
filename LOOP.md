# LOOP.md — Loop Engineering 框架入口

> 对 LLM 说一句「**按 LOOP.md 接管任务清单**」，循环即开始。

## 这是什么

一个零代码的自主循环工作流框架：你提供一份标准化任务清单（`TASKS.md`），LLM 主控自动拆解调度、派发子任务执行、验收回执、更新状态，循环直至清单完成。全部状态外置于文件，任意时刻中断都可无损续跑。

## 移植到新项目（三步）

1. 把本框架的 `LOOP.md`、`protocol/`、`prompts/` 复制到项目根目录。
2. 参照 `protocol/task-list-spec.md` 编写你的 `TASKS.md`（可从 `examples/TASKS.example.md` 改起）。
3. 对 LLM 说：「按 LOOP.md 接管任务清单」。

## LLM 接管指令（LLM 从这里开始读）

你被指定为本项目的循环主控。执行以下步骤：

1. **读取角色与协议**：依次阅读——
   - `prompts/orchestrator.md`（你的角色与主循环逻辑，铁律优先级最高）
   - `protocol/task-list-spec.md`（任务清单怎么读）
   - `protocol/state-spec.md`(状态文件与冷启动恢复)
   - `protocol/handoff-spec.md`（简报/回执/验收/重试规则）
2. **判断启动模式**：
   - `loop/state.md` **不存在** → 首次启动：校验 `TASKS.md`，初始化 `loop/` 目录与状态文件，进入主循环。
   - `loop/state.md` **已存在** → 续跑：执行 `protocol/state-spec.md` 中的冷启动恢复协议，对账后进入主循环。
3. **持续循环**直至以下任一终点：
   - 全部任务 `done` → 生成 `loop/FINAL.md` 终局报告，向用户汇报。
   - 存在无法推进的 `blocked` 任务 → 汇总失败史，请求人工介入。
   - 自感上下文即将耗尽 → 落盘后请用户新开会话说「按 LOOP.md 继续」。

## 文件地图

```
<项目根>/
├── LOOP.md                      # 本文件（入口）
├── TASKS.md                     # 任务清单（你来写, 唯一输入）
├── protocol/                    # 协议规范（框架自带, 勿改）
│   ├── task-list-spec.md
│   ├── state-spec.md
│   └── handoff-spec.md
├── prompts/                     # 角色提示词（框架自带, 勿改）
│   ├── orchestrator.md
│   ├── worker.md
│   └── verifier.md
└── loop/                        # 运行时状态（主控自动创建与维护）
    ├── state.md                 # 唯一事实源
    ├── decisions.md             # 全局决策记录（跨任务传递关键决策）
    ├── briefs/                  # 任务简报（主控→Worker; 含 *.verify.md 验证简报）
    ├── reports/                 # 任务回执（Worker→主控）
    ├── verdicts/                # 验证裁决（Verifier→主控）
    └── FINAL.md                 # 终局报告
```

## 人类操作速查

| 你想… | 怎么做 |
|---|---|
| 启动 / 续跑 | 「按 LOOP.md 接管任务清单」/「按 LOOP.md 继续」 |
| 查看进度 | 打开 `loop/state.md` |
| 查看某任务详情 | 打开 `loop/reports/<id>.md`（历次失败尝试在 `<id>.attempt<n>.md`） |
| 查看某任务验证详情 | 打开 `loop/verdicts/<id>.md` |
| 解救 blocked 任务 | 解决根因后, 把 state.md 中该任务状态改回 `pending`, 再说「按 LOOP.md 继续」 |
| 中途加任务 | 循环暂停时在 `TASKS.md` 追加新任务, 续跑时主控会把新任务补入状态表 |
| 中途改任务 | 循环暂停时按 `protocol/state-spec.md` 的修订协议操作（仅 `pending` 任务可直接改; `done` 任务的需求变化走追加修复任务） |
