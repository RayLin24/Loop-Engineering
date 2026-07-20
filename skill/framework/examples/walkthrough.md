# 循环演练：一轮完整的调度过程

以 `TASKS.example.md`（书签管理网站）为例，展示框架从启动到会话交接的真实流转。所有文件与事件内容均为示意节选。

## 第 1 轮：初始化 + 首批派发

主控读 TASKS.md，校验通过（6 任务，依赖无环）。`loop/events.jsonl` 不存在 → 首次启动：确认 git 基线与 `.gitignore`（追加 `loop/`、`.loop-worktrees/`），创建 `loop/` 目录，追加头两条事件：

```jsonl
{"seq": 1, "ts": "...", "type": "init", "tasks": ["T1","T2","T3","T4","T5","T6"], "max_ticks": 18}
{"seq": 2, "ts": "...", "type": "session", "gen": 1}
```

分析就绪任务：T1、T2 无依赖且 `touches` 无重叠（`src/js/storage.js`+`docs/` vs `src/index.html`+`src/css/`）、无共享 `resources` → **同批并行派发**。以 T1 为例：

```bash
git worktree add .loop-worktrees/T1-a1 -b loop/T1-a1
```

先写后做——追加事件，再写简报、派 Worker：

```jsonl
{"seq": 3, "ts": "...", "type": "dispatched", "task": "T1", "attempt": 1,
 "lease_expires": "...+30m", "worktree": ".loop-worktrees/T1-a1"}
```

主控写**指针简报**——注意它不抄任务内容，只开阅读清单。`loop/briefs/T1.md`（全文即如此，≤15 行）：

```markdown
# 任务简报: T1 设计数据模型与存储层
- 尝试次数: 1
- 工作区: .loop-worktrees/T1-a1/
- 时限: 30m（租约, 超时按中断处理）

## 阅读清单（按序读取并装配你的认知, 这是你对项目的全部信息来源）
1. TASKS.md：「全局上下文」节 + 「[T1]」任务节（含 yaml 与正文）。
   其余任务节是禁区——先 Grep 定位行号, 再按行号范围 Read。
2. loop/decisions.md：只读 scope 为 [global] 的条目（不存在则跳过）
3. loop/lessons.md：经验教训（不存在则跳过）

## 主控附言
无
```

随后在同一消息中派发两个子代理，指令均为：

> 读 prompts/worker.md 并遵守其中规则，然后执行 loop/briefs/T1.md 描述的任务

**Worker T1 执行**：先**装配**——Grep 定位 TASKS.md 中「全局上下文」与「[T1]」节的行号，按范围 Read（技术栈、任务目标、touches、验收标准尽收眼底，而主控一字未抄）；decisions.md 尚不存在，跳过。随后勘察（worktree 基于干净主干）→ 计划 → 执行（全部产出写在 `.loop-worktrees/T1-a1/` 内）→ 自查 → 写回执到**主工作区** `loop/reports/T1.md`：

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

**主控验收**：读两份回执（各只读前 60 行）→ 自查全 ✅ → 写两份**指针式验证简报**（工作区字段指向各自的 worktree），派发 Verifier。Verifier 在 worktree 内独立核查（grep storage.js 确认四个 export 与 "bm:" 键名前缀）→ 读回两份 ≤30 行的裁决，总裁决均为"通过"。

**落地**（工作区事务）：

```bash
git diff --name-only main...loop/T1-a1   # 越界检查: 全部在 touches 内 ✓
git merge --no-ff loop/T1-a1             # 合并主干 ✓
git worktree remove .loop-worktrees/T1-a1 && git branch -D loop/T1-a1
bash loop/checks/*.sh > loop/checks/last-run.log 2>&1   # 回归: 暂无 checks, 空跑 ✓
```

T1 的 acceptance 全部机械可验证 → 编译出 `loop/checks/T1.sh`（grep 四个 export、grep 五个字段名）。随后追加本轮事件：

```jsonl
{"seq": 5, "ts": "...", "type": "report", "task": "T1", "attempt": 1, "result": "完成"}
{"seq": 6, "ts": "...", "type": "verdict", "task": "T1", "attempt": 1, "pass": true, "warns": 0}
{"seq": 7, "ts": "...", "type": "landed", "task": "T1", "attempt": 1, "commit": "a1b2c3d"}
{"seq": 8, "ts": "...", "type": "checks", "task": "T1", "attempt": 1, "pass": true}
{"seq": 9, "ts": "...", "type": "decision", "task": "T1", "scope": "data", "text": "全部书签存于单一键 \"bm:bookmarks\"（JSON 数组）"}
...
{"seq": 12, "ts": "...", "type": "task_done", "task": "T1", "attempt": 1}
{"seq": 13, "ts": "...", "type": "task_done", "task": "T2", "attempt": 1}
{"seq": 14, "ts": "...", "type": "tick", "n": 1, "summary": "初始化(6任务,无环); 并行派发 T1,T2 均验收通过并落地"}
```

重算投影 `loop/state.md`（状态表 T1/T2 done，`状态: running`，tick 1/18）与 `loop/decisions.md`（`- [T1][data] ...` 等条目）。

## 第 2 轮：依赖注入 + 一次失败重试

就绪扫描：T3 的依赖 T1、T2 均 done → 就绪；T4、T5 依赖 T3，未就绪。本批只有 T3。

`loop/briefs/T3.md` 的阅读清单多了「上游回执」一行——这是任务间传递信息的主通道（全局性决策另经 decisions.md 的 scope 匹配流转）：

```markdown
## 阅读清单（按序读取并装配你的认知, 这是你对项目的全部信息来源）
1. TASKS.md：「全局上下文」节 + 「[T3]」任务节。其余任务节是禁区。
2. 上游回执：loop/reports/T1.md、loop/reports/T2.md
   （只读「关键决策」与「对下游的提醒」两节）
3. loop/decisions.md：只读 scope 为 [global]、[data]、[naming] 的条目
4. loop/lessons.md：经验教训
```

Worker T3 装配后执行，回执自查报了一个 ❌：「URL 非法时给出提示且不保存 — ❌ 仅校验了非空，未校验格式」。

**主控处理失败**：追加 `task_failed`（`class: "honest", counts_retry: false`——诚实自查的首次失败免费，且省去一次 Verifier 调用）。丢弃 T3 的 worktree（`discarded`），归档旧文件（`briefs/T3.attempt1.md`、`reports/T3.attempt1.md`），新建 worktree `T3-a2`，写第 2 份简报（尝试次数: 2），末尾追加主控亲笔的反思：

```markdown
## 上次失败的反思
- 未通过标准: "URL 为空或格式非法时给出提示且不保存"
- 原因: 上次实现只做了非空校验, 缺少格式校验
- 本次做法: 用 new URL() 构造做格式校验, 捕获异常时在表单下方显示中文错误提示
```

重试的 Worker 读到反思（基于最新主干的干净 worktree，直接实现完整校验）→ 自查全 ✅ → Verifier 核查通过 → 越界检查（diff 仅 `src/js/app.js` 与 `src/index.html`，在 touches 内）→ 合并落地 → **回归**：`loop/checks/` 下已有 T1、T2 的脚本，全部重跑全绿 → 编译 T3 的 checks → 追加 `landed`/`checks`/`decision`/`task_done` 事件。

第 2 轮落盘：`tick` 事件（"派发 T3, 首次自查失败(URL校验), 带反思重试后通过并落地; 回归全绿"），重算投影。

## 第 3 轮 + 会话交接

T4、T5 就绪且 touches 无重叠 → 并行派发 → 均验收通过、落地、回归全绿。第 3 轮落盘后，**会话预算检查**命中：本会话 3 轮 ≥ 每会话 tick 上限 3。主控不判断"还能不能再撑"——到轮就交：重算投影（`状态: running`），输出三行交接消息后结束会话：

> 第 1 代主控交接：本代完成 3 轮，任务 done 5/6。
> 状态已落盘 loop/events.jsonl（投影见 loop/state.md）。
> 续跑：新会话说「按 LOOP.md 继续」，或由 runner/ 驱动器自动接续。

**第 2 代接管**（人工说「按 LOOP.md 继续」，或 runner 检测到投影 `状态: running` 自动拉起）：重放事件流（T1–T5 done、T6 pending、当前 tick 3），追加 `session`（gen: 2）→ 第 4 轮派发 T6 → 全部 done 后汇总生成 `loop/FINAL.md`，追加 `final` 事件，投影 `状态: finished`——runner 见 finished 退出。

## 中断恢复插曲（假设）

若在第 2 轮 Worker T3 执行中途整个会话被杀：事件流里 T3 是 `dispatched`（先写后做保证了这一点），lease 30 分钟后过期。新会话（或 runner 拉起）重放 → 租约检查：T3 回执未出现且租约已过期 → 追加 `lease_expired` + `discarded`（删除残留 worktree 与半成品）+ `task_failed`（`class: "transient", counts_retry: false`——中断不是 Worker 的过错）→ 正常重派。崩溃、人为中断、超时挂死，走的是同一条恢复路径——这是刻意的。

再假设 T3 与 T4 被并行派发（本例中它们有依赖不会同批，仅作示意）且都改了 `src/index.html`：两个 Worker 各自在独立 worktree 中工作互不感知；T3 先通过验收先合并；T4 合并时 `git merge` 冲突 → `merge --abort` + `discarded` + `task_failed`（`class: "conflict", counts_retry: false`）→ 下一轮基于含 T3 产出的新主干重派。冲突从"互相覆盖的静默损坏"变成"显式的重试信号"。
