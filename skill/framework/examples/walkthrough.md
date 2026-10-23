# 循环演练：一轮完整的调度过程

以 `TASKS.example.md`（书签管理网站）为例，展示框架从启动到会话交接的真实流转。所有文件与事件内容均为示意节选。本例的主干分支是 `main`，所以 `dispatched.base` 记的是 `main`；换成 `trunk` 或游离 HEAD 时，用当时的分支名或 commit sha，不要照抄 `main`。

## 第 1 轮：初始化 + 首批派发

主控读 TASKS.md，校验通过（6 任务，依赖无环）。`loop/events.jsonl` 不存在 → 首次启动：确认 git 基线与 `.gitignore`（追加 `loop/`、`.loop-worktrees/`），确认 git 已有 `user.name` / `user.email`，创建 `loop/` 目录，追加头两条事件：

```jsonl
{"seq": 1, "ts": "...", "type": "init", "tasks": ["T1","T2","T3","T4","T5","T6"], "max_ticks": 18}
{"seq": 2, "ts": "...", "type": "session", "gen": 1}
```

`max_ticks: 18` 是 3×任务数，整份清单的保险丝。它和每会话的 `ticks_per_session`（默认 3）不是同一个数。

分析就绪任务：T1、T2 无依赖，`touches` 无重叠（`src/js/storage.js`+`docs/` vs `src/index.html`+`src/css/`），也没有共享 `resources` → **同批并行派发**。先写事件，再创建 worktree。以 T1 为例，主工作区绝对路径记作 `/repo`：

```jsonl
{"seq": 3, "ts": "...", "type": "dispatched", "task": "T1", "attempt": 1,
 "lease_expires": "...+30m", "worktree": ".loop-worktrees/T1-a1", "base": "main"}
```

```bash
git worktree add .loop-worktrees/T1-a1 -b loop/T1-a1
```

主控写**指针简报**。它不抄任务内容，但必须写上主工作区的绝对路径——Worker 的 cwd 是 worktree，里面没有被 gitignore 的 `loop/`。`loop/briefs/T1.md`：

```markdown
# 任务简报: T1 设计数据模型与存储层
- 尝试: 1 | 时限: 30m | 主干: main
- 工作区: /repo/.loop-worktrees/T1-a1
- 主工作区: /repo
- 回执: /repo/loop/reports/T1.md

## 阅读清单（下列路径都相对主工作区, 不是工作区 cwd）
1. TASKS.md：「全局上下文」节 + 「[T1]」任务节。其余任务节是禁区。
2. loop/decisions.md：只读 scope 为 [global] 的条目（不存在则跳过）
3. loop/lessons.md（不存在则跳过）

## 主控附言
无
```

随后在同一消息中派发两个子代理，指令均为：

> 读 prompts/worker.md 并遵守其中规则，然后执行 loop/briefs/T1.md 描述的任务

**Worker T1 执行**：cwd 是 `/repo/.loop-worktrees/T1-a1`。装配时按绝对路径读 `/repo/TASKS.md` 的「全局上下文」与「[T1]」节（decisions.md 尚不存在，跳过）。产出全部写在 worktree 内，**不 commit**。回执写到 `/repo/loop/reports/T1.md`，而不是 worktree 里的 `loop/reports/`：

```markdown
# 回执: T1
- 结果: 完成
- 自查:
  - ✅ 四个函数已导出（storage.js 第 12-58 行, export 语句可 grep 验证）
  - ✅ 字段含 id/title/url/tags/createdAt 五项
  - ✅ data-model.md 含字段表与四个函数签名说明

## 产出物
- src/js/storage.js — localStorage 存储模块
- docs/data-model.md — 数据模型与接口文档

## 关键决策
- [naming] id 用 crypto.randomUUID() 生成, 字符串类型
- [data] 全部书签存于单一键 "bm:bookmarks"（JSON 数组）, 简化遍历
- [data] 时间字段 createdAt 用 ISO 8601 字符串

## 对下游的提醒
- 函数签名: addBookmark({title,url,tags}) → bookmark; removeBookmark(id) → boolean;
  listBookmarks() → bookmark[]; updateBookmark(id, patch) → bookmark|null
- storage.js 是 ES Module, 引入时 script 标签需 type="module"

## 遗留问题
无
```

**主控验收**：读两份回执（各只读前 60 行）→ 自查全 ✅ → 写两份指针式验证简报（含裁决绝对路径），派发 Verifier。Verifier 在 worktree 内核查，裁决写到 `/repo/loop/verdicts/T1.md`，并删掉自己产生的临时文件。主控只读裁决前 30 行，总裁决均为「通过」。

**落地**（先封箱，再 diff，再合并）。未提交的改动对三点 diff 是不可见的，所以不能跳过 commit：

```bash
cd .loop-worktrees/T1-a1
git add -A
git commit -m "loop: T1 attempt 1"
cd /repo
git diff --name-only main...loop/T1-a1          # 越界检查: 全部在 touches 内
git merge --no-ff -m "loop: land T1 a1" loop/T1-a1
git worktree remove .loop-worktrees/T1-a1
git branch -d loop/T1-a1
```

然后才编译 `loop/checks/T1.sh`（grep 四个 export、grep 五个字段名），并**单独**执行它：

```bash
bash loop/checks/T1.sh >> loop/checks/last-run.log 2>&1
```

不要在编译前跑 `bash loop/checks/*.sh`。目录为空时这个 glob 不会展开，bash 以 127 退出；有多个脚本时也只会执行第一个。T2 同样：封箱、检查、合并、编译、再把 T1.sh 和 T2.sh 各跑一次。

随后追加本轮事件（序号示意，中间略去 T2 的对称事件）：

```jsonl
{"seq": 5, "ts": "...", "type": "report", "task": "T1", "attempt": 1, "result": "完成"}
{"seq": 6, "ts": "...", "type": "verdict", "task": "T1", "attempt": 1, "pass": true, "warns": 0}
{"seq": 7, "ts": "...", "type": "landed", "task": "T1", "attempt": 1, "commit": "a1b2c3d"}
{"seq": 8, "ts": "...", "type": "checks", "task": "T1", "attempt": 1, "pass": true}
{"seq": 9, "ts": "...", "type": "decision", "task": "T1", "scope": "data", "text": "全部书签存于单一键 \"bm:bookmarks\"（JSON 数组）"}
{"seq": 12, "ts": "...", "type": "task_done", "task": "T1", "attempt": 1}
{"seq": 13, "ts": "...", "type": "task_done", "task": "T2", "attempt": 1}
{"seq": 14, "ts": "...", "type": "tick", "n": 1, "summary": "初始化(6任务,无环); 并行派发 T1,T2 均验收通过并落地"}
```

重算投影。机器可读的三行必须是单值，不能把三个状态并列在一行：

```markdown
- 项目: 个人书签管理网站 | 清单: TASKS.md (6 任务) | tick: 1/18 | 更新: ...
- 状态: running
- 等待租约: 无
```

`loop/decisions.md` 写出 `- [T1][data] ...`。运行配置节使用规范 key，例如 `max_parallel: 3 | ticks_per_session: 3 | lessons: on`。

## 第 2 轮：诚实失败，本轮到此为止

就绪扫描：T3 的依赖 T1、T2 均 done → 就绪。T4、T5 依赖 T3，未就绪。本批只有 T3。

`loop/briefs/T3.md` 的阅读清单多了上游回执，路径仍相对主工作区 `/repo`：

```markdown
## 阅读清单（下列路径都相对主工作区, 不是工作区 cwd）
1. TASKS.md：「全局上下文」节 + 「[T3]」任务节。其余任务节是禁区。
2. 上游回执：loop/reports/T1.md、loop/reports/T2.md
   （只读「关键决策」与「对下游的提醒」两节）
3. loop/decisions.md：只读 scope 为 [global]、[data]、[naming] 的条目
4. loop/lessons.md
```

Worker T3 的回执自查有一条 ❌：「URL 非法时给出提示且不保存 — ❌ 仅校验了非空，未校验格式」。

主控追加 `task_failed`（`class: "honest", counts_retry: false`——该任务第一次诚实自查不消耗重试，也省掉一次 Verifier），丢弃 T3 的 worktree 与分支，把简报和回执归档为 `*.attempt1.md`。**重试不在这一轮里发生。** 本轮到此落盘：

```jsonl
{"seq": 20, "ts": "...", "type": "tick", "n": 2, "summary": "派发 T3, 首次自查失败(URL校验), 工作区已丢弃, 下轮带反思重试"}
```

## 第 3 轮：带反思重试，然后交接

新简报的尝试次数是 2，末尾是主控亲笔的反思（依据是上一轮回执里的 ❌，这次没有裁决）：

```markdown
## 上次失败的反思
- 未通过标准: "URL 为空或格式非法时给出提示且不保存"
- 原因: 上次实现只做了非空校验, 缺少格式校验
- 本次做法: 用 new URL() 构造做格式校验, 捕获异常时在表单下方显示中文错误提示
```

重试的 Worker 在基于最新主干的干净 worktree 里做完，自查全 ✅。Verifier 通过后：封箱提交、越界检查（diff 只有 `src/js/app.js` 与 `src/index.html`）、`git merge --no-ff -m "loop: land T3 a2"`。回归时把已有的 T1.sh、T2.sh **各执行一次**，再编译 T3.sh 并把它也执行一次。全绿后才 `checks(pass: true)`、`decision`、`task_done`。

第 3 轮落盘时本会话已满 `ticks_per_session`（3）。任务还没做完（done 3/6），所以不是终局：投影保持下面这样，输出三行交接消息后结束会话。

```markdown
- 项目: 个人书签管理网站 | 清单: TASKS.md (6 任务) | tick: 3/18 | 更新: ...
- 状态: running
- 等待租约: 无
```

> 第 1 代主控交接：本代完成 3 轮，任务 done 3/6。
> 状态已落盘 loop/events.jsonl（投影见 loop/state.md）。
> 续跑：新会话说「按 LOOP.md 继续」，或由 runner/ 驱动器自动接续。

T4 和 T5 现在都就绪，但两者的 `touches` 都包含 `src/index.html`，**不能**放进同一并行批。第 1 轮的 T1/T2 才是真的并行；这里要拆开，一个一轮。

**第 2 代**重放事件流（T1–T3 done，T4/T5 就绪，T6 还在等，当前 tick 3），只追加一次 `session`（gen: 2）。之后按重叠关系逐个做完 T4、T5、T6。最后一轮落地后若已经全部 done，先写 `loop/FINAL.md` 和 `final` 事件，投影 `状态: finished`，不要因为本代 tick 刚好打满就先交出一个 `running`。runner 看到 `finished` 后退出。

## 中断恢复插曲（假设）

若在第 2 轮 Worker T3 执行中途整个会话被杀：事件流里已经有 T3 的 `dispatched`（先写后做保证了这一点），worktree 里的改动多半还没 commit。新会话重放时，租约若尚未到期：不派新任务，投影保持 `状态: running`，并把 `等待租约` 写成 T3 的 `lease_expires`。这一轮不追加 `tick`。runner 看到未来的等待时间会休眠（单次最多 1 小时），而不是立刻再拉起一轮空转，也不会把这种等待记成停滞。

租约到期后的下一轮：追加 `lease_expired` + `discarded`（worktree 或分支已经没了也算清理成功）+ `task_failed`（`class: "transient", counts_retry: false`），然后正常重派。崩溃、人为中断、超时挂死，走的是同一条恢复路径。

再假设两个任务都改了同一个文件、又被放进同一批（本例里 T3 与 T4 有依赖，不会同批；T4 与 T5 因为都写 `src/index.html`，也不会）。各自在自己的 worktree 里工作。先通过验收的那个封箱、合并。后到的那个 `git merge` 冲突 → `merge --abort` + `discarded` + `task_failed`（`class: "conflict", counts_retry: false`）→ 下一轮基于新主干重派。冲突从互相覆盖变成一次显式重试。
