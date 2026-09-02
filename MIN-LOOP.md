# 最小环 v0（可执行方案）

目标：一个任务接一个任务地做完清单。调度、验收、恢复由 runner 完成；模型只在隔离工作区里改文件。

非目标（v0 不做）：并行、LLM Verifier、Meta-Analyst、租约超时、主控会话、事件由模型追加、`skill/framework` 双份同步。

宿主：任意能「在指定目录改文件并退出」的 CLI（Claude Code / Cursor agent / 其他）。runner 不解析模型输出，只看 git 与 checks 退出码。

---

## 1. 角色

| 谁 | 允许做 | 禁止做 |
|---|---|---|
| 人 | 写/改 `TASKS.md`；答 `loop/NEED_HUMAN.md`；设保险丝 | 让模型改清单、改 runner、改本页 |
| runner | 解析清单、选下一个、建工作区、调 Worker、跑 checks、merge、追加事件、投影状态、判停 | 改业务代码、改 `TASKS.md`、发明任务 |
| Worker | 只读简报列出的文件；只写 `touches` | git 提交/merge、改 `TASKS.md`、写 `loop/events.jsonl` |

---

## 2. `TASKS.md` 最小字段

保留现规范的骨架，只留 runner 真用得到的键。

```markdown
# 任务清单：<项目名>

## 全局上下文
<≤30 行，所有任务都需要的背景。密钥只写环境变量名。>

## 任务

### [T1] <标题>
id: T1
depends_on: []
touches:
  - src/foo.py
checks:
  - python -m pytest tests/test_foo.py -q
context_files:
  - src/foo.py
<正文：给「只看见本任务」的 Worker。>
```

| 字段 | 必填 | runner 怎么用 |
|---|---|---|
| `id` | 是 | `T` + 数字，与标题 `[T1]` 一致 |
| `depends_on` | 是 | 列表全为 `done` 才就绪；启动时检环，有环则停并写 `NEED_HUMAN.md` |
| `touches` | 是 | 目录以 `/` 结尾。merge 前 `git diff --name-only` 必须 ⊆ 此集合（前缀包含算命中） |
| `checks` | 是 | 每条是一条 shell。在即将 merge 的工作区里、干净环境执行；非 0 则本 tick 失败。不要再另写「编译成 checks 脚本」的步骤——清单里的命令就是回归集：每次成功落地后，**全部已 done 任务的 checks 都要再跑一遍** |
| `context_files` | 否 | 写进 Worker 简报的阅读清单；只列文件不列目录 |
| 正文 | 是 | 只给 Worker，不进状态机 |

刻意砍掉：`acceptance`（改成 `checks`；不能写成命令的验收先不要进 v0）、`constraints`（写进正文）、`resources` / `timeout` / `risk` / `effects`（并行和租约不做）。

人可以随时改 `TASKS.md`。runner 每个 tick **开始时**重读；已 `done` 的 id 若被删，视为需要人确认（写 `NEED_HUMAN.md` 后停）。

---

## 3. 状态（全部由事件重放算出，禁止手改投影）

任务状态：

```
pending ──dispatch─┆ running ──checks 全 0 且 diff⊆touches 且 merge 成功─┆ done
                         │
                         ├──checks 非 0 或越界─┆ failed
                         └──Worker 写出 loop/ASK.md─┆ waiting
failed 在 depends 仍满足时可再次 dispatch（同一 id 最多 3 次尝试，含第一次）。
waiting 只等人改 `TASKS.md` 或删掉 ASK 里的问题后，下一 tick 变回 pending。
```

尝试次数记在事件里，不记在 `TASKS.md`。

循环状态（`loop/state.md` 唯一来源：重放）：

- `fresh`：无 `loop/events.jsonl`
- `running`：有未完成任务且不在等人
- `waiting-human`：存在 `waiting` 任务，或环、或已 done 被删
- `finished`：全部任务 `done`，并已写 `loop/FINAL.md`
- `stalled`：连续 2 个 tick 没有新的 `task_done` / `task_failed` / `task_waiting`（由 runner 退出码表达，不写进任务状态）

合法事件（仅 runner 追加到 `loop/events.jsonl`，一行一个 JSON）：

`loop_started` | `dispatched` | `task_done` | `task_failed` | `task_waiting` | `loop_finished`

每条必有 `seq`（从 1 递增）、`ts`（UTC）、`type`。`dispatched` / 终态三条带 `id`；`task_failed` 带 `reason`（`checks` | `touches` | `worker-nonzero` | `retry-exhausted`）。

---

## 4. 一个 tick（runner 伪代码，必须按此顺序）

```
1. 读 TASKS.md；重放 events.jsonl → 得每个 id 的状态与 attempt。
2. 检环；检「已 done 的 id 被删除」。失败 → 写 NEED_HUMAN.md，退出 2。
3. ready = 状态 in {pending, failed} 且 depends_on 全 done 且 attempt < 3。
   空 ready：
     - 还有 waiting → 退出 2
     - 还有 failed 且 attempt 用尽 → 退出 2（等人改任务或放宽 checks）
     - 否则写 FINAL.md，追加 loop_finished，退出 0
4. 取 ready 中 id 数字最小的一个（v0 串行，禁止挑多个）。
5. 追加 dispatched；git worktree（或分支）基于当前 HEAD，路径 .loop-worktrees/<id>-a<attempt>。
6. 写 loop/briefs/<id>.md：全局上下文路径、正文、context_files、touches、checks 原文。不超过一屏。
7. 调 Worker：工作目录 = worktree；参数 = 简报路径。等待退出。
     退出码非 0 → 追加 task_failed reason=worker-nonzero，拆 worktree，tick 结束。
     worktree 内出现 loop/ASK.md → 追加 task_waiting，保留工作区供人看，tick 结束。
8. git diff --name-only HEAD..worktree 必须 ⊆ touches；越界 → task_failed reason=touches，不 merge。
9. 在 worktree 内按顺序跑：本任务 checks，然后所有已 done 任务的 checks。任一条非 0 → task_failed reason=checks。
10. git merge --no-ff 进主工作区当前分支；追加 task_done；拆 worktree；重写 state.md。
```

Worker 调用约定（适配层，一行配置）：

```
LOOP_WORKER='claude -p --permission-mode acceptEdits'
# runner 实际执行：
#   (cd "$WORKTREE" && $LOOP_WORKER "$(cat loop/briefs/<id>.md)")
```

Wait: the brief is written in the MAIN repo's loop/briefs/, but Worker cwd is the worktree. Make this work correctly: copy/write the brief where Worker can read it (worktree-relative path or pass absolute path). Do not let Worker write events.jsonl.

v0 不要求 Worker 写回执。需要给人看的信息进 commit message（由 runner 在 merge 时写：`loop: T1 ok` / `loop: T1 fail checks`）。

---

## 5. 磁盘约定

TASKS.md 人写，tick 中模型不可改
MIN-LOOP.md 本页，模型不可改
runner/run-loop.sh 唯一调度器
prompts/worker.md 唯一提示词（只约束 touches 与 ASK.md）
loop/events.jsonl 只追加，仅 runner 写
loop/state.md 仅 runner 从事件投影，可随时删了重算
loop/briefs/<id>.md runner 写，Worker 读
loop/NEED_HUMAN.md runner 写，人处理完删掉再跑
loop/FINAL.md 全部 done 时 runner 写
.loop-worktrees/ git worktree；进 .gitignore

.gitignore 必含：loop/（可选择把 events.jsonl 纳入版本，v0 建议纳入，作为恢复依据）、.loop-worktrees/

恢复：删掉 state.md 不影响正确性。有 events.jsonl 就能重放。进程被杀：未追加终态事件的 worktree 视为未发生，下一 tick 可对同一 id 重新 dispatched（重复 dispatched 且无终态 = 上次崩溃，attempt 不增加）。

---

## 6. 停机与退出码

0 finished 读 FINAL.md
2 waiting-human 读 NEED_HUMAN.md / ASK.md
3 连续 2 tick 无终态事件
4 代数上限（默认 30）LOOP_MAX_TICKS 默认 3 × 任务数
