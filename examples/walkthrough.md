# 循环演练：完整的 tick 流转

以 `TASKS.example.md`（书签管理网站）为例，展示框架从启动到落地回归的真实流转。所有文件内容均为示意节选。

## Tick 1：初始化 + 首批派发

主控读 TASKS.md，校验通过（6 任务，依赖无环，项目是 git 仓库）。`loop/events.jsonl` 不存在 → 首次启动，创建 `loop/` 目录并追加首个事件：

```jsonl
{"seq":1,"ts":"2026-07-08T10:00:00Z","type":"init","tasks":6,"max_ticks":18}
```

就绪分析：T1、T2 无依赖且 `touches`/`resources` 均无重叠 → **同批并行派发**。逐任务执行：组装简报 → 建隔离工作区 → **先写事件后派发**：

```bash
git worktree add loop/worktrees/T1.attempt1 -b loop/T1-a1
```

```jsonl
{"seq":2,"ts":"...","type":"dispatched","task":"T1","attempt":1,"lease_expires":"2026-07-08T10:30:00Z","worktree":"loop/worktrees/T1.attempt1"}
{"seq":3,"ts":"...","type":"dispatched","task":"T2","attempt":1,"lease_expires":"2026-07-08T10:30:00Z","worktree":"loop/worktrees/T2.attempt1"}
```

简报 `loop/briefs/T1.attempt1.md`（节选）：

```markdown
# 任务简报: T1 设计数据模型与存储层
- 尝试次数: 1
- 工作区: loop/worktrees/T1.attempt1

## 任务目标
设计书签的数据结构，并实现基于 localStorage 的存储模块。...

## 允许写入的路径
- src/js/storage.js
- docs/data-model.md

## 验收标准
- src/js/storage.js 导出 addBookmark / removeBookmark / listBookmarks / updateBookmark 四个函数
- ...

## 约束
- 存储键名统一以 "bm:" 为前缀
```

同一消息并行派发两个子代理，指令均为：

> 读 prompts/worker.md 并遵守其中规则，然后执行 loop/briefs/T1.attempt1.md 描述的任务

**Worker T1 执行**（ReAct）：理解简报 → 进入自己的 worktree（干净的主干副本）→ 计划 → 执行 → 自查 → `git commit` → 写回执 `loop/reports/T1.attempt1.md`：

```markdown
# 回执: T1 (尝试 1)
- 结果: 完成
- 自查:
  - ✅ 四个函数已导出（storage.js, export 语句可 grep 验证）
  - ✅ 字段含 id/title/url/tags/createdAt 五项
  - ✅ data-model.md 含字段表与四个函数签名说明

## 产出物
- src/js/storage.js — localStorage 存储模块
- docs/data-model.md — 数据模型与接口文档（含函数签名, 即接口契约）

## 关键决策
- [api] id 用 crypto.randomUUID(), 字符串类型
- [storage] 全部书签存于单一键 "bm:bookmarks"（JSON 数组）, 简化遍历
- [format] 时间字段 createdAt 用 ISO 8601 字符串

## 对下游的提醒
- 接口契约见 docs/data-model.md（函数签名与行为的权威定义）
- storage.js 是 ES Module, 引入时 script 标签需 type="module"

## 遗留问题
无
```

**验收**：主控读两份回执 → 自查全 ✅、产出物均在 touches 内 → 生成验证简报派发 Verifier。这是 T1 的**首次验证**，Verifier 把机械标准编译成 `loop/checks/T1.sh`（grep 四个 export、grep "bm:" 前缀、检查 data-model.md 含字段表）并执行，再语义核查文档完整性 → 裁决"通过"。主控合并落地：

```bash
git merge --squash loop/T1-a1   # 提交信息 "loop: T1 设计数据模型与存储层"
git worktree remove loop/worktrees/T1.attempt1
```

```jsonl
{"seq":4,"type":"report","task":"T1","attempt":1,"result":"done"}
{"seq":5,"type":"checks","task":"T1","attempt":1,"pass":true}
{"seq":6,"type":"verdict","task":"T1","attempt":1,"pass":true,"warns":0}
{"seq":7,"type":"landed","task":"T1","attempt":1,"commit":"a1b2c3d"}
{"seq":8,"type":"decision","task":"T1","scope":"api","text":"id 用 crypto.randomUUID(), 字符串类型"}
{"seq":9,"type":"decision","task":"T1","scope":"storage","text":"全部书签存于单一键 bm:bookmarks"}
{"seq":10,"type":"task_done","task":"T1","attempt":1}
```

T2 同理落地（回归检查：此时无其他 done 任务，跳过）。Tick 收尾——追加 tick 事件并重新生成投影 `loop/state.md`：

```jsonl
{"seq":14,"type":"tick","n":1,"summary":"初始化(6任务); 并行派发 T1/T2, 均验收落地"}
```

## Tick 2：依赖注入 + 一次失败重试

重放事件流：T1、T2 done，其余 pending。就绪扫描：T3 依赖满足 → 派发（T4/T5 依赖 T3 未就绪）。

简报 `loop/briefs/T3.attempt1.md` 的「上游交接」由 T1、T2 回执**机械组装**，接口契约直接给文件路径：

```markdown
## 上游交接
[来自 T1] 关键决策: [api] id 用 crypto.randomUUID(); [storage] 单一键 bm:bookmarks; ...
[来自 T1] 提醒: 接口契约见 docs/data-model.md; storage.js 是 ES Module
[来自 T2] 提醒: 三个容器 id 为 #add-form/#bookmark-list/#tag-filter;
          卡片样式类 .bookmark-card 已定义, 直接使用
```

Worker T3 执行后回执自查报了一个 ❌：「URL 非法时给出提示且不保存 — ❌ 仅校验了非空，未校验格式」。

**主控处理失败**：自查含 ❌ → 直接判 deterministic 失败，**不派 Verifier**（省一次验证）。因为是**诚实自查**报出的首次失败，不消耗重试次数。丢弃工作区（主干零污染——上次的半成品不会留在主干上），写事件：

```jsonl
{"seq":16,"type":"report","task":"T3","attempt":1,"result":"failed","failure_class":"deterministic"}
{"seq":17,"type":"discarded","task":"T3","attempt":1,"reason":"self-check-failed"}
{"seq":18,"type":"task_failed","task":"T3","attempt":1,"class":"deterministic","counts_retry":false,"reason":"URL格式校验缺失(诚实自查,首次免耗)"}
```

生成第 2 份简报 `loop/briefs/T3.attempt2.md`（旧文件无需归档——attempt 编号天然隔离），末尾追加：

```markdown
## 上次失败的反思
- 未通过标准: "URL 为空或格式非法时给出提示且不保存"
- 原因: 上次实现只做了非空校验, 缺少格式校验
- 本次做法: 用 new URL() 构造做格式校验, 捕获异常时在表单下方显示中文错误提示
```

重试 Worker 在**全新的干净工作区**从头实现（带着反思，不接手脏状态）→ 自查全 ✅ → Verifier 首验编译并执行 `loop/checks/T3.sh` + 语义核查 → 通过 → 合并落地。

**落地后回归**：T3 的变更 touches `src/js/app.js`、`src/index.html`，与 done 任务中 T2 的 touches（`src/index.html`）相交 → 机械重跑 `loop/checks/T2.sh` → 通过，T2 的验收标准仍然成立：

```jsonl
{"seq":24,"type":"landed","task":"T3","attempt":2,"commit":"e4f5g6h"}
{"seq":25,"type":"checks","task":"T2","attempt":1,"pass":true}   // 回归重跑
{"seq":26,"type":"task_done","task":"T3","attempt":2}
{"seq":27,"type":"tick","n":2,"summary":"T3 自查失败(URL校验)免耗重试, 二次通过落地; T2 回归绿"}
```

## Tick 3：并行 + 一次回归捕获（假设情景）

T4、T5 就绪且 touches 无重叠 → 并行派发，各自在隔离 worktree 执行，先后验收通过。假设 T5 落地时，回归重跑 `loop/checks/T3.sh` 失败——T5 给 index.html 加导入导出按钮时误删了 T3 的 script 标签：

```jsonl
{"seq":35,"type":"regression","task":"T3","caused_by":"T5","failed_checks":["T3.sh: script 标签 app.js 缺失"]}
```

主控对 T5 生成修复性重试（反思注明"破坏了 T3 的验收标准 X"）。在旧版设计里这个破坏会**静默存活到交付**——回归保护是本版新增的正确性保障。

## Tick 4+（略）

T6 就绪 → 派发 → 落地；全部 done → 主控汇总生成 `loop/FINAL.md`（含产出物索引、决策汇总、⚠️ 未验证项、`loop/checks/` 验收套件、从事件流统计的循环度量），追加 `final` 事件，结束。

## 中断恢复插曲

若 Tick 2 中 Worker T3 执行中途会话被杀：事件流里 T3 是 `dispatched`（先写后做保证了这一点）。用户新开会话说「按 LOOP.md 继续」→ 新主控重放事件流 → 发现 T3 dispatched 且无回执：

- **租约未到**（如果是并行派发、Worker 可能还活着）→ 跳过等待；
- **租约已到**（30 分钟默认）→ 追加 `lease_expired`，丢弃 worktree，按 transient 免费重派。

注意这**不是特殊的恢复流程**——每个 tick 都这样开始，冷启动只是碰巧上一 tick 在别的会话里。即使被杀时 Worker 其实还活着并稍后写完了回执也无碍：两次尝试在各自 worktree，先通过验收者落地，后到者合并被拒绝丢弃。

## 人机异步插曲（假设）

若 T5 的 Worker 报告"导入功能需要测试用的书签 JSON 样例数据，简报未提供"——主控判定 environmental，写 `loop/questions/T5.md`（背景 + 建议选项），T5 标 `waiting_human`，**循环继续做 T4 和其他可推进任务**。用户随时在问题文件「回答」节作答并改状态为"已回答"，下一 tick 主控读到 → `task_reset` → 带着答案要点重新派发 T5。升级不停机。
