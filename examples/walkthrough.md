# 循环演练：一轮完整的调度过程

以 `TASKS.example.md`（书签管理网站）为例，展示框架从启动到代际交接的真实流转。所有文件内容均为示意节选。

## 第 1 轮：初始化 + 首批派发

主控读 TASKS.md，校验通过（6 任务，依赖无环）。`loop/state.md` 不存在 → 首次启动，初始化（`循环状态: running`、`代次: 1`、`本代轮次: 0`）后分析就绪任务：

- T1、T2 无依赖且 `touches` 无重叠（`src/js/storage.js`+`docs/` vs `src/index.html`+`src/css/`）、无共享 `resources` → **同批并行派发**。

主控写两份**指针简报**——注意它不抄任务内容，只开阅读清单。以 `loop/briefs/T1.md` 为例（全文即如此，≤15 行）：

```markdown
# 任务简报: T1 设计数据模型与存储层
- 尝试次数: 1

## 阅读清单（按序读取并装配你的认知, 这是你对项目的全部信息来源）
1. TASKS.md：「全局上下文」节 + 「[T1]」任务节（含 yaml 与正文）。
   其余任务节是禁区——先 Grep 定位行号, 再按行号范围 Read。
2. loop/decisions.md：全局决策记录（不存在则跳过）
3. loop/lessons.md：经验教训

## 主控附言
无
```

派发前落盘（先写后做），state.md 状态表变为：T1 `dispatched`、T2 `dispatched`、其余 `pending`。随后在同一消息中派发两个子代理，指令均为：

> 读 prompts/worker.md 并遵守其中规则，然后执行 loop/briefs/T1.md 描述的任务

**Worker T1 执行**：先**装配**——Grep 定位 TASKS.md 中「全局上下文」与「[T1]」节的行号，按范围 Read（技术栈、任务目标、touches、验收标准、约束尽收眼底，而主控一字未抄）；decisions.md 尚不存在，跳过。随后勘察（目录为空，无半成品）→ 计划 → 执行 → 自查 → 写回执 `loop/reports/T1.md`：

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
- id 用 crypto.randomUUID() 生成, 字符串类型
- 全部书签存于单一键 "bm:bookmarks"（JSON 数组）, 而非一书签一键, 简化遍历
- 时间字段 createdAt 用 ISO 8601 字符串

## 对下游的提醒
- 函数签名: addBookmark({title,url,tags}) → bookmark; removeBookmark(id) → boolean;
  listBookmarks() → bookmark[]; updateBookmark(id, patch) → bookmark|null
- storage.js 是 ES Module, 引入时 script 标签需 type="module"

## 遗留问题
无
```

**主控验收**：读两份回执（各只读前 60 行）→ 自查全 ✅，产出物均在 touches 范围内 → 写两份**指针式验证简报**（`loop/briefs/T1.verify.md`、`T2.verify.md`）。以 T1 为例：

```markdown
# 验证简报: T1 设计数据模型与存储层

## 验证依据（按序读取）
1. TASKS.md：「全局上下文」节 + 「[T1]」任务节（acceptance 逐条核查;
   constraints 与 touches 同为核查对象）。其余任务节是禁区。
2. 回执 loop/reports/T1.md：只读「产出物」与「关键决策」两节。
   不要参照其自查结论——你的价值在于独立重查。

## 禁读清单（评判独立性红线）
- loop/lessons.md 与 loop/decisions.md
- loop/briefs/T1*.md 与 loop/verdicts/ 下任何历史裁决

## 授权验证命令
- acceptance 中出现的构建/测试/grep 等机械验证命令, 视为已授权

## 附加约束
无
```

派发 Verifier 独立核查（自行读 TASKS.md 原文获得标准 → grep storage.js 确认四个 export 与 "bm:" 键名前缀）→ 读回两份 ≤30 行的裁决，总裁决均为"通过" → 把 T1 回执的三条「关键决策」**追加**进 `loop/decisions.md`。

第 1 轮**增量落盘**：状态表 T1、T2 两行改为 `done`，日志追加一条，轮次 1、本代轮次 1：

```markdown
## 日志
- [轮1] 初始化(6任务,依赖无环)。并行派发 T1、T2, 均验收通过。
```

## 第 2 轮：依赖注入 + 一次失败重试

就绪扫描：T3 的依赖 T1、T2 均 done → 就绪；T4、T5 依赖 T3，未就绪。本批只有 T3。

`loop/briefs/T3.md` 的阅读清单多了「上游回执」一行——这是任务间传递信息的主通道（全局性决策另经 decisions.md 流转，Worker 同样自取）：

```markdown
## 阅读清单（按序读取并装配你的认知, 这是你对项目的全部信息来源）
1. TASKS.md：「全局上下文」节 + 「[T3]」任务节。其余任务节是禁区。
2. 上游回执：loop/reports/T1.md、loop/reports/T2.md
   （只读「关键决策」与「对下游的提醒」两节）
3. loop/decisions.md：全局决策记录
4. loop/lessons.md：经验教训
```

Worker T3 装配后执行，回执自查报了一个 ❌：「URL 非法时给出提示且不保存 — ❌ 仅校验了非空，未校验格式」。

**主控处理失败**：标记 T3 `failed`。因为这是 Worker **诚实自查**报出的首次失败，不计入重试次数（自首从宽）。先把上次尝试归档（`briefs/T3.attempt1.md`、`reports/T3.attempt1.md`），再写第 2 份简报（尝试次数: 2），末尾追加主控亲笔的反思——这是简报中唯一非指针的实质内容：

```markdown
## 上次失败的反思
- 未通过标准: "URL 为空或格式非法时给出提示且不保存"
- 原因: 上次实现只做了非空校验, 缺少格式校验
- 本次做法: 用 new URL() 构造做格式校验, 捕获异常时在表单下方显示中文错误提示;
  其余已通过的部分保留, 检查现有 app.js 后增量修改即可
```

重试的 Worker 读到反思，勘察发现 app.js 已有上次的产出，增量补上 URL 校验 → 自查全 ✅ → 回执「结果: 完成」。主控派 Verifier 核查，裁决"通过"，标记 `done`。

（注意第一次失败没有派 Verifier——Worker 自查已报 ❌，直接判 failed，省一次验证调用。）

第 2 轮落盘：日志追加 `- [轮2] 派发 T3, 首次验收失败(URL格式校验缺失), 带反思重试后通过。`，本代轮次 2。

## 第 3 轮 + 代际交接

T4、T5 就绪且 touches 无重叠 → 并行派发 → 均验收通过。第 3 轮落盘后，**代际预算检查**命中：本代轮次 3 ≥ 每代最大轮次 3。主控不判断"还能不能再撑"——到轮就交：`循环状态` 置为 `handoff`，输出三行交接消息后结束会话：

> 第 1 代主控交接：本代完成 3 轮，任务 done 5/6。
> 状态已落盘 loop/state.md。
> 续跑：新会话说「按 LOOP.md 继续」，或由 runner/ 驱动器自动接续。

**第 2 代接管**（人工说「按 LOOP.md 继续」，或 runner 检测到 `handoff` 自动拉起）：冷启动协议——代次 2、本代轮次归零、`循环状态` 置回 `running`；对账无非终态残留；日志追加 `- [轮4] 第 2 代接管，冷启动对账: 无残留。`。随后第 4 轮派发 T6，全部 done 后汇总各回执生成 `loop/FINAL.md`，`循环状态: finished`，循环结束——runner 见 FINAL.md 即退出。

## 中断恢复插曲（假设）

若在第 2 轮 Worker T3 执行中途会话被杀：state.md 里 T3 是 `dispatched`（先写后做保证了这一点），`循环状态` 仍是 `running`。新会话（或 runner 发现会话已退出）按冷启动接管 → 对账：发现 T3 无回执 → 判定执行中断 → 新简报「主控附言」注明「此前有一次被中断的尝试，先检查 touches 下的现有产出再决定重做或续做」→ 重新派发。其余状态不受影响——代际交接、上下文耗尽、人为中断，走的是同一条恢复路径。
