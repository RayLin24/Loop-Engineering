# task-list-spec 使用示例

本文件是 [task-list-spec.md](task-list-spec.md) 的**配套编写指南**，不是协议规范本身（规范以 spec 为准）。spec 讲"规则是什么"，[examples/TASKS.example.md](../examples/TASKS.example.md) 给了一份前端项目的完整成品，本文档补中间那一环：**用一个贯穿全文的小项目，逐步演示怎么从零写出一份合格的 `TASKS.md`**，并配大量正/反对比。

> 阅读前提：已读过 [task-list-spec.md](task-list-spec.md) 的字段定义与编写规则。

---

## 贯穿示例：blog-ssg

一个 Node.js + TypeScript 的迷你 Markdown 博客静态站点生成器。扫描 `posts/` 下的 `.md` 文章，渲染成 HTML，套上模板，输出到 `dist/`。

选这个项目做演示是因为它天然适合本框架：

- 任务拆分自然（解析、渲染、模板、构建、测试、文档各自内聚）
- 依赖图有线性链也有可并行分支，能演示 `depends_on` 和 `touches` 的配合
- 验收标准几乎都能机械验证（`node --test`、文件存在、grep 关键内容、构建产物检查）

---

## 第一步：写「全局上下文」

**规则**（spec 第 11-12 行）：所有任务都需要知道的信息，原样注入每份简报，**控制在 30 行以内**。

只写"每个 Worker 都必须知道的"。任何只属于单个任务的细节，留到该任务的正文或 `constraints` 里。

### ✅ 好例子

```markdown
## 全局上下文
构建 blog-ssg：一个把 posts/*.md 编译成静态 HTML 博客的 CLI。
- 技术栈：Node.js 20 + TypeScript 5（严格模式），通过 tsx 直接运行 TS
- 入口：src/index.ts，CLI 用 process.argv 解析（不引 commander/yargs）
- 目录约定：源码在 src/，文章在 posts/，产物在 dist/（.gitignore 忽略）
- 不引入构建打包工具（无 webpack/vite/esbuild），仅 tsc 做类型检查
- 代码与注释统一中文，日志输出用英文
- 外部依赖白名单：marked（Markdown 解析）、gray-matter（frontmatter）、zod（校验）
```

### ❌ 坏例子

```markdown
## 全局上下文
本项目目标是做一个博客系统。技术栈用 Node.js。
我会用 TypeScript 写，因为类型安全很重要。代码要写好注释。
posts 文件夹放 Markdown 文章，每篇文章有 frontmatter。
（问题：含糊、缺关键约定；"类型安全很重要"是空话；没说目录/依赖边界，
 Worker 会反复猜测，要么写歪要么把疑问写进回执污染下游。）
```

**自检**：全局上下文写完后，遮住它，问自己"一个对项目一无所知的 Worker，凭这段话能不能避开 90% 的低级误会（命名、路径、依赖、语言）？" 不能就补，超过 30 行就删非共性的内容下沉到任务级。

---

## 第二步：拆任务（粒度）

**规则**（spec 编写规则 4）：一个任务 = 一个 Worker 一次上下文内可完成的工作量，经验值 1–5 个文件或一个内聚模块。**太大的任务在编写清单时拆开，不指望 Worker 自己拆。**

blog-ssg 的拆分思路（先列骨架，再填字段）：

| 任务 | 职责 | 为什么独立 |
|---|---|---|
| T1 配置加载与校验 | 读 `blog.config.ts`、zod schema 校验 | 单一职责，下游都要用配置 |
| T2 文章解析 | 扫描 `posts/*.md`、提取 frontmatter | 独立的 I/O + 解析层 |
| T3 Markdown 渲染 | markdown → HTML，含代码高亮 | 纯转换函数，可单测 |
| T4 模板引擎 | 布局 + 文章页 + 列表页 | 独立的字符串/视图层 |
| T5 构建主流程 | 编排：配置→扫描→解析→渲染→套模板→写出 dist/ | 集成层 |
| T6 单元测试 | 覆盖解析与渲染 | 独立产物（tests/） |
| T7 使用文档 | README + 操作说明 | 纯文档 |

### ❌ 坏例子（粒度过大）

```yaml
id: T1
# "实现整个博客生成器" —— 产物 15+ 文件、跨 5 个模块,
# 单 Worker 一次上下文塞不下，验收也写不细。
```

粒度过大时，验收标准只能写得空泛（"功能正常"），验收就失守了。**遇到"我写不出 5 条以内具体验收标准"的任务，就是它该被拆开的信号。**

---

## 第三步：定 `depends_on`（依赖图）

**规则**（spec 依赖语义 + 编写规则 3）：`depends_on` 列出的任务全部 `done` 后本任务才就绪；**依赖必须无环**，主控启动时做环检测。

先把依赖图画出来，确认无环：

```
T1 ──────────────┐
                 │
T2 ──┬── T3 ─────┤
     │           ├── T5 ── T7
     ├── T4 ─────┤
     │           │
     └── T6 ─────┘  (T6 还依赖 T3)
```

读法：

- T1、T2 无依赖 → 项目启动时就可派发
- T3、T4、T6 都依赖 T2，但 T6 还要等 T3
- T5 依赖 T1/T3/T4，是集成点
- T7 依赖 T5（文档要描述真实的构建流程）

### ❌ 坏例子（隐式依赖）

```yaml
# T5 构建主流程，depends_on 只写了 T1
id: T5
depends_on: [T1]
```

T5 显然还要调用 T3 的渲染和 T4 的模板，但没写进 `depends_on`。后果：主控可能 T1 完成后就派发 T5，此时 T3/T4 还没产出，Worker 在简报的「上游交接」里也拿不到它们的接口，只能盲写。**记住：用了谁的产出，就必须 depends_on 谁。**

---

## 第四步：划 `touches`（并行安全的根基）

**规则**（spec 编写规则 2）：`touches` 是允许**写入**的路径。两个就绪任务的 `touches` 互不重叠且无依赖时，主控可并行派发。写得越精确并行度越高；不确定就写宽一点（牺牲并行换安全）。**范围之外只读。**

关键认知：`touches` 不是"我会用到的文件"，而是"我**会创建或修改**的文件"。读取不算。

### ✅ 好例子

```yaml
# T3 Markdown 渲染
touches:
  - src/renderer/
```

T3 只在 `src/renderer/` 下产出文件。它会 `import` T2 的解析结果（读 `src/parser/`），但不写那里——所以 `src/parser/` **不能**出现在 T3 的 `touches` 里。

### 并行判定实例

第 1 轮就绪任务是 T1、T2：

| 任务 | touches |
|---|---|
| T1 | `src/config/`, `blog.config.ts` |
| T2 | `src/parser/`, `posts/` |

两者无交集 → **可同批并行派发**。

如果 T1 也写 `src/parser/`（比如想顺手把类型定义放那），就要么改路径让两者分开，要么放弃并行、写成 `T2 depends_on T1`。

### ❌ 坏例子（touches 写漏导致踩踏）

```yaml
# T3
touches: [src/]          # 太宽：和 T4(src/templates/) 重叠，被迫串行
# T5
touches: [src/, dist/]   # 太宽：构建脚本会和任何 src/ 任务冲突
```

**经验**：按"模块子目录"粒度划 touches 最舒服（`src/renderer/`、`src/templates/`、`src/build/`）。整目录 `src/` 只给唯一的集成任务（如 T5），并让它 `depends_on` 所有写 `src/` 的任务。

---

## 第五步：写 `acceptance`（最重要的一步）

**规则**（spec 编写规则 1）：验收标准**必须可验证**。主控据此验收，Worker 据此自查。坏例："代码质量良好"；好例："`node --test` 全部通过"。

这是清单质量的命门。验收写不清，整条"验收→反思→重试"的闭环就失效。

### 可验证等级（从强到弱）

| 等级 | 写法 | 例子 |
|---|---|---|
| 🟢 命令可跑 | 跑测试/lint/构建 | `npx tsc --noEmit` 无报错 |
| 🟢 文件可查 | 文件存在 / 路径 / 数量 | `dist/index.html` 生成且非空 |
| 🟢 内容可 grep | 关键串/结构存在 | `src/parser.ts` 中能 grep 到 `export function parsePost` |
| 🟡 行为可演示 | 给定输入→给定输出 | 输入 `# hi` 的 `.md`，输出 `<h1>hi</h1>` |
| 🔴 不可验证 | 主观判断 | "结构清晰"、"代码规范"、"体验良好" |

🔴 一律改写成 🟢/🟡，否则不要写进 acceptance。

### ✅ 好例子（T3 Markdown 渲染）

```yaml
acceptance:
  - npx tsc --noEmit 通过（src/renderer/ 下无类型错误）
  - src/renderer/index.ts 导出 renderMarkdown(md: string): string
  - 输入 "# 标题" 返回的字符串以 <h1> 标题</h1> 为子串
  - 输入含 ``` 围栏代码块的文本，返回 HTML 含 <pre><code> 元素
  - node --test tests/renderer.test.ts 全部通过
```

每条都能在 30 秒内由主控机械验证。

### ❌ 坏例子（同一个任务）

```yaml
acceptance:
  - 正确渲染 Markdown
  - 支持代码高亮
  - 代码质量良好，结构清晰
```

三条全部 🔴：什么叫"正确"、什么叫"支持"、什么叫"良好"都无法判定。Worker 自查会全打 ✅，主控验收却无从下手，最后只能"读产出物全文自己判断"——而这正是框架禁止的（主控不读产出物全文）。

### 把 🔴 改成 🟢 的思路

| 主观愿望 | 改写为可验证 |
|---|---|
| "代码规范" | "`npx tsc --noEmit` 通过 + 无 `any` 类型（grep 不到 `: any`）" |
| "错误处理完善" | "传入不存在的路径，函数抛出含 `config not found` 的 Error" |
| "界面好看" | "三个容器 id 存在；CSS 全部在 `src/css/style.css`（无内联样式）" |
| "性能不错" | "100 篇文章构建耗时 < 3s（构建脚本末尾打印耗时）" |

---

## 第六步：可选字段 `context_files` 与 `constraints`

### context_files（开工前必读）

只在"存在 Worker 必须读、但不在 `touches` 范围里、也不在上游产出中"的**已有文件**时填。

```yaml
# T7 使用文档
context_files:
  - docs/style-guide.md   # 团队既有文案风格指南，写文档前必须读
```

### ❌ 不要这样用

```yaml
context_files:
  - src/renderer/index.ts   # 这是 T3 的产出，应在 T3 回执的「对下游的提醒」里传递,
                            # 不靠 Worker 自己去读源码推断
```

跨任务信息**唯一通道是上游回执**（spec 依赖语义末段）。让下游读上游源码 = 破坏信息漏斗。

### constraints（任务级硬约束）

写本任务特有的禁区、风格、行为要求。全局约束放「全局上下文」。

```yaml
# T3 的 constraints
constraints:
  - 代码高亮不引入 highlight.js / shiki，用轻量正则方案即可
  - 渲染函数不得做文件 I/O（纯字符串函数，便于测试）

# T5 的 constraints
constraints:
  - 每次构建前清空 dist/（rm -rf dist 后再生成），避免残留旧文件
  - 跳过 draft: true 的文章
```

**高危操作（删除、部署、花钱）一定要在 constraints 里显式禁止**，并依赖宿主权限系统兜底——框架靠提示词约束，不是硬沙箱。

---

## 第七步：写正文（自包含）

**规则**（spec 编写规则 5）：Worker 看不到其他任务的正文，只能看到依赖任务回执中的摘要。所以**每个任务正文要独立可读**——写给一个"对项目一无所知、只能看到本简报"的执行者。

### ✅ 好例子（T5 正文）

```markdown
基于 T1 的配置、T3 的渲染、T4 的模板，编排完整构建流程。
启动时读 blog.config.ts（T1 校验过），扫描 posts/（T2 的扫描器），
逐篇解析→渲染→套文章模板，汇总生成首页列表（套列表模板），
全部写到 dist/。dist/ 构建前清空。具体接口签名以 T2/T3/T4 回执为准。
```

### ❌ 坏例子

```markdown
把前面的模块串起来，按之前讨论的流程跑通就行。
（问题："前面"、"之前讨论的"——Worker 看不到其他正文，也不知道任何"讨论"。
 这种话对 Worker 等于没说。）
```

---

## 完整成果：可直接复制的 TASKS.md

把上面七步合起来，blog-ssg 的清单如下。可直接 `cp` 改用。

```markdown
# 任务清单：blog-ssg

## 全局上下文
构建 blog-ssg：一个把 posts/*.md 编译成静态 HTML 博客的 CLI。
- 技术栈：Node.js 20 + TypeScript 5（严格模式），通过 tsx 直接运行 TS
- 入口：src/index.ts，CLI 用 process.argv 解析（不引 commander/yargs）
- 目录约定：源码在 src/，文章在 posts/，产物在 dist/（.gitignore 忽略）
- 不引入构建打包工具（无 webpack/vite/esbuild），仅 tsc 做类型检查
- 代码与注释统一中文，日志输出用英文
- 外部依赖白名单：marked、gray-matter、zod

## 任务

### [T1] 配置加载与校验
```yaml
id: T1
depends_on: []
touches:
  - src/config/
  - blog.config.ts
acceptance:
  - src/config/index.ts 导出 loadConfig(path: string): BlogConfig
  - 用 zod 定义 schema，缺 title/baseUrl 字段时抛错且消息含字段名
  - blog.config.ts 提供一份合法示例配置
  - npx tsc --noEmit 通过
constraints:
  - 配置读取不得有网络/文件系统以外的副作用
```
读 blog.config.ts（ES Module 默认导出一个对象），用 zod 校验其结构与类型。
字段至少含 title、baseUrl、postsDir(默认 posts)、outputDir(默认 dist)、drafts(布尔)。
校验失败时的错误信息要让用户能定位到字段。

### [T2] 文章解析
```yaml
id: T2
depends_on: []
touches:
  - src/parser/
  - posts/
acceptance:
  - src/parser/index.ts 导出 scanPosts(dir: string): Post[] 和 parsePost(file: string): Post
  - Post 类型含 slug、title、date(ISO 字符串)、draft(布尔)、content(原文 markdown)
  - posts/ 下放至少 3 篇示例 .md（含 1 篇 draft: true）
  - npx tsc --noEmit 通过
constraints:
  - 仅扫描 .md 文件；非 .md 静默跳过
  - slug 取文件名（去扩展名），不做额外转换
```
扫描 posts/ 下全部 .md，逐篇用 gray-matter 提取 frontmatter 与正文。
frontmatter 字段：title、date、draft(可选)。回执务必给出 Post 的精确类型定义。

### [T3] Markdown 渲染
```yaml
id: T3
depends_on: [T2]
touches:
  - src/renderer/
acceptance:
  - src/renderer/index.ts 导出 renderMarkdown(md: string): string
  - 输入 "# 标题" 返回值以 <h1>标题</h1> 或 <h1> 标题</h1> 为子串
  - 输入围栏代码块返回值含 <pre><code>
  - npx tsc --noEmit 通过
constraints:
  - 代码高亮不引入 highlight.js/shiki，用 marked 内建或轻量正则
  - 渲染函数纯字符串 I/O，不读文件系统
```
基于 marked 把 markdown 原文转 HTML。Post 类型以 T2 回执为准。

### [T4] 模板引擎
```yaml
id: T4
depends_on: [T2]
touches:
  - src/templates/
acceptance:
  - src/templates/index.ts 导出 renderPostPage(post, html): string 和 renderIndex(posts): string
  - 文章页 HTML 含 <article> 与 <h1>{{title}}</h1> 的替换结果
  - 列表页 HTML 含 <ul class="post-list">，每篇文章一个 <li>
  - npx tsc --noEmit 通过
constraints:
  - 不引入 handlebars/ejs，用模板字符串字面量自行实现占位替换
```
实现文章详情页与首页列表两套布局，占位符用 {{key}} 语法。
Post 类型以 T2 回执为准。

### [T5] 构建主流程
```yaml
id: T5
depends_on: [T1, T3, T4]
touches:
  - src/build/
  - src/index.ts
  - dist/
acceptance:
  - 运行 npx tsx src/index.ts build 后 dist/index.html 与 dist/posts/<slug>.html 全部生成且非空
  - draft: true 的文章不出现在 dist/ 中
  - 重复构建不报错（幂等：先清空 dist/ 再生成）
  - 构建末尾打印 "Built N posts in Xms"
constraints:
  - 每次构建前清空 dist/（避免残留旧文件）
  - 跳过 draft: true 的文章
```
编排完整流程：loadConfig → scanPosts → 逐篇 renderMarkdown + renderPostPage →
renderIndex(全部文章) → 写 dist/ 与 dist/posts/。接口签名以 T1/T2/T3/T4 回执为准。

### [T6] 单元测试
```yaml
id: T6
depends_on: [T2, T3]
touches:
  - tests/
acceptance:
  - node --test 跑通 tests/ 下全部 *.test.ts，无失败用例
  - 至少覆盖：frontmatter 解析、draft 过滤、markdown 渲染（标题与代码块）
  - 测试不得写真实文件系统（用内存中的字符串或临时目录）
context_files:
  - docs/style-guide.md
constraints:
  - 测试框架用 node:test + assert，不引 jest/vitest
```
为解析层与渲染层写单测。被测模块的接口以 T2/T3 回执为准。

### [T7] 使用文档
```yaml
id: T7
depends_on: [T5]
touches:
  - README.md
  - docs/usage.md
acceptance:
  - README.md 含"安装/构建/新增文章"三节操作说明
  - 含一个可复制即跑的构建命令示例
  - docs/usage.md 含 frontmatter 字段表（title/date/draft 及类型）
  - 文档无死链（所有引用路径在仓库内实际存在）
context_files:
  - docs/style-guide.md
constraints:
  - 文案遵循 docs/style-guide.md，语气直接，避免营销腔
```
面向最终用户写文档。构建流程以 T5 实际行为为准（不要凭想象写）。
```

---

## 常见错误速查

| 症状 | 根因 | 修法 |
|---|---|---|
| Worker 总在回执里问基础问题 | 全局上下文缺关键约定 | 补足目录/命名/依赖/语言约束 |
| 验收总过不了但说不清 | acceptance 有 🔴 主观项 | 改写成命令/文件/grep 可验 |
| 主控把任务串行派发 | `touches` 写太宽（如整 `src/`） | 按模块子目录细分 |
| 下游用错上游接口 | 隐式依赖 / 上游回执没写接口 | `depends_on` 补全；上游正文里点名要求回执写接口 |
| 任务反复重试同一原因 | 反思没落到具体标准 | 主控写反思时引用具体 acceptance 条目 |
| 拆不下去的巨型任务 | 粒度失控 | 沿模块边界切，每个子任务控制在 1-5 文件 |

## 写完对照检查清单

- [ ] 全局上下文 ≤ 30 行，只含共性信息
- [ ] 每个任务的 `id` 与标题 `[T1]` 一致
- [ ] 每条 acceptance 都是 🟢/🟡（命令/文件/grep/输入输出），无 🔴 主观项
- [ ] `touches` 只列本任务**写入**的路径，按模块子目录粒度，无重叠隐患
- [ ] 用了谁的产出就 `depends_on` 谁，全图无环
- [ ] `context_files` 只指已有文件，不让 Worker 去读上游源码
- [ ] 高危操作在 `constraints` 显式禁止
- [ ] 每个任务正文自包含，不依赖"前面讨论过"

```
