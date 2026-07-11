---
name: loop-engineering
description: 自主循环工作流——把用户的一句话需求转成带依赖/验收标准的任务清单，然后以 Orchestrator 身份逐 tick 调度子代理执行、独立验收、合并落地、回归保护，直至全部完成。用于"帮我完整做出 X"类的多任务交付需求（如构建一个应用、批量重构、成套文档）。项目里已有 loop/events.jsonl 时说"继续"即可续跑。不用于单个小任务或定时轮询（后者用 /loop）。
---

# Loop Engineering — 自主循环交付

用户的需求在 `$ARGUMENTS` 中（可能为空）。你将分三个阶段工作：**部署框架 → 生成任务清单 → 以主控身份运行循环**。

框架的完整协议随本 skill 打包在 `framework/` 目录（本文件同级）。下文所说"框架文件"均指该目录内容。

## 阶段 0：判断模式

- 当前项目已存在 `loop/events.jsonl` → **续跑模式**：跳过阶段 1–2，直接读项目根的 `LOOP.md` 按其接管指令进入循环（相当于用户说"按 LOOP.md 继续"）。若 `$ARGUMENTS` 非空且不是"继续"类表述，把它当作新增/修订需求：先按 `protocol/task-list-spec.md` 把它转成追加任务写入 `TASKS.md`（新任务，勿动非 pending 的旧任务），再进入循环（主控 tick 开头会自动同步）。
- 无 `loop/events.jsonl` 但 `$ARGUMENTS` 为空 → 用 AskUserQuestion 问清用户想交付什么，再进入阶段 1。
- 否则 → 新项目，走阶段 1。

## 阶段 1：部署框架

1. 项目根不存在 `LOOP.md`/`protocol/`/`prompts/` 时，把 skill 的 `framework/LOOP.md`、`framework/protocol/`、`framework/prompts/` 复制到项目根（已存在的文件不覆盖——用户可能定制过）。`framework/examples/` 不复制。
2. 项目不是 git 仓库 → `git init`（事务工作区、失败回滚、冲突检测都依赖它）。工作区有未提交变更 → 先提交一个基线 commit，避免用户变更混入任务落地提交。

## 阶段 2：需求 → TASKS.md（你代行框架中"人类清单作者"的职责）

这是决定循环成败的一步。按 `protocol/task-list-spec.md` 的全部编写规则，把 `$ARGUMENTS` 转成任务清单：

1. **需求太糊先澄清**：交付物形态、技术栈、规模边界不明时，用 AskUserQuestion 问（一次问完，≤4 个问题），不要脑补大方向。
2. **拆解**：5–30 个任务，一个任务 = 一个子代理一次上下文能完成（产出 1–5 个文件或一个内聚模块）；声明 `depends_on`（无环）与尽量精确的 `touches`；能并行的不串行。
3. **验收标准可机械化优先**：能写成命令/文件存在性/grep 的就这么写（它们会被编译成 checks 脚本获得回归保护）；每任务正文自包含。
4. **按需使用可选字段**：长耗时任务加 `timeout`；有不可回滚外部副作用的任务必须声明 `effects`；安全/支付/数据迁移类标 `risk: high`；共享端口/lockfile 等用 `resources`。
5. 写出 `TASKS.md` 后，**向用户展示任务概览**（id、标题、依赖关系、总数——不必贴全文）并用 AskUserQuestion 确认：「开始循环 / 我要先改清单」。用户要改则等修订后再进入阶段 3。

## 阶段 3：运行循环

读项目根的 `LOOP.md`，按其「LLM 接管指令」以 Orchestrator 身份工作，直至其三种终点之一（全部 done / 等待人工 / 会话 tick 上限）。要点提醒（细则以框架文件为准）：

- 你是主控：不亲自执行任务、不读产出物全文、不亲自验证；Worker 与 Verifier 用 Agent 工具（general-purpose）派发，同批并行任务在同一消息派发。
- 事实只写事件（`loop/events.jsonl` 追加），每 tick 结束更新投影 `state.md`。
- 到达终点时向用户汇报：done 数量、blocked/waiting_human 及其原因（含 `loop/questions/` 待答问题）、FINAL.md 位置（若完成）。会话 tick 上限触发时告知用户下次说 `/loop-engineering 继续` 即可接续。
