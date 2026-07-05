# 循环演练：一轮完整的调度过程

以 `TASKS.example.md`（书签管理网站）为例，展示框架从启动到第 2 轮结束的真实流转。所有文件内容均为示意节选。

## 第 1 轮：初始化 + 首批派发

主控读 TASKS.md，校验通过（6 任务，依赖无环）。`loop/state.md` 不存在 → 首次启动，初始化后分析就绪任务：

- T1、T2 无依赖且 `touches` 无重叠（`src/js/storage.js`+`docs/` vs `src/index.html`+`src/css/`）→ **同批并行派发**。

主控生成两份简报。以 `loop/briefs/T1.md` 为例：

```markdown
# 任务简报: T1 设计数据模型与存储层
- 尝试次数: 1

## 全局上下文
构建一个纯前端的个人书签管理网站，无需后端。
- 技术栈：原生 HTML/CSS/JavaScript（ES6+）...（原样复制）

## 任务目标
设计书签的数据结构，并实现基于 localStorage 的存储模块。...

## 开工前必读
无

## 上游交接
无

## 允许写入的路径
- src/js/storage.js
- docs/data-model.md

## 验收标准
- src/js/storage.js 导出 addBookmark / removeBookmark / listBookmarks / updateBookmark 四个函数
- 书签字段至少包含 id、标题、URL、标签数组、创建时间
- docs/data-model.md 用表格记录字段定义与每个函数的签名和行为

## 约束
- 存储键名统一以 "bm:" 为前缀
```

派发前落盘（先写后做），state.md 状态表变为：T1 `dispatched`、T2 `dispatched`、其余 `pending`。随后在同一消息中派发两个子代理，指令均为：

> 读 prompts/worker.md 并遵守其中规则，然后执行 loop/briefs/T1.md 描述的任务

**Worker T1 执行**（ReAct 流程）：理解简报 → 勘察（目录为空，无半成品）→ 计划（先定字段，再写函数，最后写文档）→ 执行 → 自查 → 写回执 `loop/reports/T1.md`：

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

**主控验收**：读两份回执 → 自查全 ✅ → 为 T1、T2 各生成验证简报（`loop/briefs/T1.verify.md`、`T2.verify.md`），派发 Verifier 独立核查（grep storage.js 确认四个 export 存在；确认 index.html、style.css 存在且结构符合验收标准）→ 读回两份裁决（`loop/verdicts/T1.md`、`T2.md`），总裁决均为"通过"。

第 1 轮落盘，state.md 更新：

```markdown
| T1 | done | 0 | loop/reports/T1.md |
| T2 | done | 0 | loop/reports/T2.md |
| T3 | pending | 0 | - |
...
## 日志
- [轮1] 初始化(6任务,依赖无环)。并行派发 T1、T2, 均验收通过。
```

## 第 2 轮：依赖注入 + 一次失败重试

就绪扫描：T3 的依赖 T1、T2 均 done → 就绪；T4、T5 依赖 T3，未就绪。本批只有 T3。

主控生成 `loop/briefs/T3.md`，其中「上游交接」一节由 T1、T2 回执**自动组装**——这就是任务间传递信息的唯一通道：

```markdown
## 上游交接
[来自 T1] 关键决策: id 用 crypto.randomUUID(); 全部书签存于单一键 "bm:bookmarks"; ...
[来自 T1] 对下游的提醒: 函数签名 addBookmark({title,url,tags}) → bookmark; ...
          storage.js 是 ES Module, script 标签需 type="module"
[来自 T2] 对下游的提醒: 三个容器 id 为 #add-form/#bookmark-list/#tag-filter;
          卡片样式类名 .bookmark-card 已在 CSS 中定义, 直接使用
```

Worker T3 执行后回执自查报了一个 ❌：「URL 非法时给出提示且不保存 — ❌ 仅校验了非空，未校验格式」。

**主控处理失败**：标记 T3 `failed`（重试 0→记录原因），生成第 2 份简报 `loop/briefs/T3.md`（尝试次数: 2），末尾追加：

```markdown
## 上次失败的反思
- 未通过标准: "URL 为空或格式非法时给出提示且不保存"
- 原因: 上次实现只做了非空校验, 缺少格式校验
- 本次做法: 用 new URL() 构造做格式校验, 捕获异常时在表单下方显示中文错误提示;
  其余已通过的部分保留, 检查现有 app.js 后增量修改即可
```

重试的 Worker 读到反思，勘察发现 app.js 已有上次的产出，增量补上 URL 校验 → 自查全 ✅ → 回执「结果: 完成」。主控派 Verifier 核查，裁决"通过"，标记 `done`。

（注意第一次失败没有派 Verifier——Worker 自查已报 ❌，直接判 failed，省一次验证调用。）

第 2 轮落盘：

```markdown
## 日志
- [轮1] 初始化(6任务,依赖无环)。并行派发 T1、T2, 均验收通过。
- [轮2] 派发 T3, 首次验收失败(URL格式校验缺失), 带反思重试后通过。
```

## 第 3 轮起（略）

T4、T5 就绪且 touches 无重叠 → 并行派发；随后 T6；全部 done 后主控汇总各回执生成 `loop/FINAL.md`，循环结束。

## 中断恢复插曲（假设）

若在第 2 轮 Worker T3 执行中途会话被杀：state.md 里 T3 是 `dispatched`（先写后做保证了这一点）。新会话说「按 LOOP.md 继续」→ 冷启动对账：发现 T3 无回执 → 判定执行中断 → 简报追加「此前有一次被中断的尝试，请先检查现有产出」→ 重新派发。其余状态不受影响。
