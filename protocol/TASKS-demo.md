# 任务清单：程序员宝盒 — Prompt 库 / i18n / 主题市场 三联升级

## 全局上下文
开发环境数据库信息：
帐号：root 密码：123456
redis: 127.0.0.1 端口6379 无密码
web端管理员帐号：admin  密码： admin123
普通用户帐号：llp 密码：123456

## 任务
### [T1] Prompt模板库
```yaml
id: T1
depends_on: []
touches:
  - D:\study\baoboxs
acceptance:
  - 后端 mvn clean package -DskipTests 通过；前端 npm run build 通过，浏览器无 console error
  - AI 板块（/ai）改造为 Tab 布局，包含两个 Tab：「AI 工具」（保留现有 AI 模型聚合卡片）与「Prompt 库」（新增）。默认进入「AI 工具」Tab
  - Prompt 库 Tab 使用独立全屏布局：不显示 MainLayout 的左侧分类导航栏，但保留顶部导航；移动端布局正常、可滚动
  - 后端新增 prompt_template 表（含字段：id、name、content、purpose、remark、tags、category、is_public、status、creator_id、creator_name、reviewer_id、review_remark、review_time、create_time、update_time），并完成对应 Entity / Repository / Service / Controller / DTO
  - status 枚举：PENDING（待审核）/ APPROVED（已通过）/ REJECTED（已驳回）；is_public：true / false
  - API 端点齐全（统一前缀 /api/v1/prompts）：公开列表（仅 APPROVED 且 is_public=true）、我的列表、创建、更新、删除、详情、收藏 / 取消收藏、我收藏的列表、管理员列表（全部）、审核（通过 / 驳回 + 备注）、批量导入初始化数据
  - 可见性规则正确实现：
    · 未登录用户：仅可见 APPROVED 且 is_public=true 的模板
    · 普通登录用户：可见 APPROVED 且 is_public=true 的 + 自己创建的全部（无论状态）
    · 管理员：可见全部模板
  - 创建提示词表单字段完整：提示词名称、提示词内容、作用 / 用途、备注说明、标签（可选）、是否公开（默认公开）。提交后默认 status=PENDING，前端给出「已提交，等待管理员审核」提示
  - 管理员创建的提示词默认 status=APPROVED 且所有人可见；管理员可在「审核」操作中通过 / 驳回普通用户的提交，并填写审核备注
  - 已登录用户可对任意可见模板执行：收藏 / 取消收藏、复制内容到剪贴板、分享（生成短链接或分享卡片，至少实现复制链接）
  - Prompt 库支持关键词搜索（匹配名称、内容、标签、用途）与标签 / 分类筛选；前端搜索带防抖
  - 初始化数据：参考 https://www.aishort.top/?tags=code 导入至少 30 条优质中文 Prompt 模板（通过 data.sql 或 migration 脚本，或通过批量导入接口），覆盖编码、写作、辅助、生活等常用分类
  - 在后台管理（/admin）新增「Prompt 审核」子菜单，管理员可分页查看全部模板、按状态过滤、执行审核操作
  - 移动端：Prompt 卡片自适应宽度、搜索框可达、分享与收藏按钮可点；Tab 切换流畅
constraints:
  - 复用现有 JWT 鉴权与 RBAC 体系（USER / ADMIN），不引入新的鉴权机制
  - 后端遵循现有 Controller → Service → Repository 三层架构与 DTO 风格（MapStruct 映射）
  - 高频查询接口（公开列表、我的列表）需要加缓存（Redis 或 Caffeine），TTL ≤ 10 分钟；审核 / 创建 / 更新 / 删除操作必须失效缓存
  - Prompt 内容字段允许较长文本（TEXT 类型），前端展示需支持换行与一键复制
  - 前端不引入新的 UI 库；继续使用 Element Plus
  - 不破坏现有 AI 工作台（/ai）的拖拽排序与布局记忆功能
context_files:
  - D:\study\baoboxs\REQUIREMENTS.md
  - D:\study\baoboxs\baoboxs-web\src\views\ai\
  - D:\study\baoboxs\baoboxs-web\src\layouts\MainLayout.vue
  - D:\study\baoboxs\baoboxs-web\src\router\index.ts
  - D:\study\baoboxs\baoboxs-server\src\main\java\com\baoboxs\controller\
  - D:\study\baoboxs\baoboxs-server\src\main\java\com\baoboxs\entity\
  - D:\study\baoboxs\baoboxs-server\src\main\java\com\baoboxs\config\SecurityConfig.java
```
> **目标**：将现有 AI 板块（/ai）升级为 Tab 化布局，新增「Prompt 模板库」作为第二个 Tab。Prompt 库支持用户创建、提交审核、收藏、分享、搜索；管理员负责审核与初始化优质内容，沉淀社区 Prompt 资产。

**一、产品形态**

```
顶部导航栏
└─ AI（菜单项）→ 进入 /ai
        ┌─────────────────────────────────┐
        │  [ AI 工具 ] [ Prompt 库 ]      │  ← Tab 切换条
        ├─────────────────────────────────┤
        │ Tab1：现有 AI 模型聚合卡片（保留）│
        │ Tab2：Prompt 模板库（新增）      │
        └─────────────────────────────────┘

Prompt 库 Tab 进入后：
  - 隐藏 MainLayout 左侧分类导航
  - 顶部导航保留（含语言/主题/用户菜单等）
  - 整页全屏布局
```

**二、数据模型（prompt_template 表）**

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | BIGINT PK | 主键 |
| `name` | VARCHAR(100) NOT NULL | 提示词名称 |
| `content` | TEXT NOT NULL | 提示词正文（支持变量占位符 `{{xxx}}`） |
| `purpose` | VARCHAR(255) | 作用 / 用途 |
| `remark` | VARCHAR(500) | 备注说明 |
| `tags` | VARCHAR(255) | 标签，逗号分隔（如 `code,review`） |
| `category` | VARCHAR(50) | 分类（编码 / 写作 / 生活 / 辅助 / 等） |
| `is_public` | BOOLEAN DEFAULT true | 是否愿意公开 |
| `status` | VARCHAR(20) DEFAULT 'PENDING' | PENDING / APPROVED / REJECTED |
| `creator_id` | BIGINT | 创建者 ID（管理员初始化数据可为空） |
| `creator_name` | VARCHAR(50) | 冗余创建者用户名 |
| `reviewer_id` | BIGINT | 审核人 ID |
| `review_remark` | VARCHAR(500) | 审核备注（驳回原因） |
| `review_time` | DATETIME | 审核时间 |
| `create_time` / `update_time` | DATETIME | 时间戳 |

> 索引建议：`(status, is_public)`、`(creator_id)`、`(category)`；标签搜索可用 `LIKE` 或全文索引。

**三、API 设计**

| 方法 | 路径 | 权限 | 说明 |
|---|---|---|---|
| GET | `/prompts/public` | 公开 | 公开列表（APPROVED + is_public），支持 search / category / tag / 分页 |
| GET | `/prompts/{id}` | 公开（公开的）/ 登录（自己的）/ 管理员（任意） | 详情（按可见性规则） |
| GET | `/prompts/mine` | 登录 | 我创建的全部（含未审核） |
| POST | `/prompts` | 登录 | 创建（普通用户 status=PENDING；管理员 status=APPROVED） |
| PUT | `/prompts/{id}` | 登录（仅自己的，状态为 PENDING 或 REJECTED 时可编辑） | 编辑 |
| DELETE | `/prompts/{id}` | 登录（自己的）/ 管理员（任意） | 删除 |
| POST | `/prompts/{id}/favorite` | 登录 | 收藏 |
| DELETE | `/prompts/{id}/favorite` | 登录 | 取消收藏 |
| GET | `/prompts/favorites` | 登录 | 我收藏的列表 |
| GET | `/prompts/admin` | 管理员 | 后台列表（全部，支持按状态过滤） |
| PUT | `/prompts/{id}/review` | 管理员 | 审核：通过 / 驳回 + 备注 |
| POST | `/prompts/seed` | 管理员 | 初始化导入（一次性，导入内置优质 Prompt） |

**四、前端实现要点**

1. **路由与布局**
   - `/ai` 改造为 Tab 容器，沿用现有 AI 模型聚合（移到 Tab1），新增 Prompt 库（Tab2）
   - Prompt 库使用独立 layout（或在 MainLayout 内根据 route meta 隐藏左侧栏，参考 `meta.hideSidebar: true`）
   - Tab 状态写入 URL query（如 `/ai?tab=prompts`），便于分享与直达

2. **Prompt 库页面结构**
   ```
   ┌─ 顶部：搜索框 + 分类/标签筛选 + [我的/公开/收藏] 切换 + [新建] 按钮 ─┐
   ├─ 卡片网格：Prompt 卡片（名称、用途、标签、收藏/复制/分享按钮）          │
   └─ 分页 + 空状态                                                        │
   ```

3. **新建 / 编辑弹窗**
   - 表单字段：名称、内容（多行文本，支持变量 `{{变量名}}` 高亮）、用途、备注、标签、分类、是否公开
   - 提交后 Toast 提示审核状态

4. **卡片交互**
   - 一键复制内容到剪贴板（用 `navigator.clipboard.writeText`）
   - 收藏 / 取消收藏（图标态切换）
   - 分享：生成分享短链（`/ai?tab=prompts&id=xxx`）+ 弹出 ShareDialog（复用现有组件）

5. **管理员审核页**
   - `/admin/prompts` 路由，分页表格：名称、创建人、状态、分类、提交时间、操作
   - 操作：查看详情 → 通过 / 驳回（驳回必填原因）

**五、初始化数据**

- 采集 https://www.aishort.top/?tags=code 上至少 30 条中文优质 Prompt
- 通过 `data.sql` 或应用启动后的 `@PostConstruct` 一次性导入（避免重复执行）
- 字段要求：内容完整、分类合理、标签清晰、`is_public=true`、`status=APPROVED`、`creator_name='系统'`
- 分类建议覆盖：代码生成、Code Review、文档注释、SQL 优化、正则辅助、写作润色、翻译、生活效率

**六、自检清单（Worker 完成前必跑）**

- [ ] 未登录访问 Prompt 库 → 仅看到 APPROVED 公开模板
- [ ] 普通用户 llp 创建一条 → 提示已提交等待审核 → 在「我的」可见（PENDING）→ 公开列表不可见
- [ ] 管理员 admin 登录 → 后台可见该条 → 点驳回填备注 → llp 看到驳回原因
- [ ] 管理员再创建一条 → 自动 APPROVED → 公开列表立即可见
- [ ] 收藏 / 取消收藏 / 复制内容 / 分享链接 → 均工作正常
- [ ] 搜索关键词、按标签筛选 → 结果正确
- [ ] 移动端横竖屏切换 → Tab 与卡片正常
- [ ] 进入 Prompt 库后左侧分类导航消失，切回 AI 工具 Tab 恢复
- [ ] `mvn clean package -DskipTests` 通过
- [ ] `npm run build` 通过

**七、回执要求**

- 「关键决策」写明：表结构最终字段、缓存策略（哪些 key、TTL）、初始化数据导入方式
- 「对下游的提醒」提醒：
  - 新增的 `prompt_template` 表与未来 T2（i18n）的协作：Prompt 内容字段不强求 i18n（中文为主），但前端管理页 UI 文案要使用 `t()`
  - T3（主题市场）的卡片样式 token 需应用到 Prompt 卡片上

### [T2] 国际化（i18n 英文版）
```yaml
id: T2
depends_on: []
touches:
  - D:\study\baoboxs\baoboxs-web
acceptance:
  - baoboxs-web 引入 vue-i18n 并在 main.ts 正确注册；locales 目录包含 zh-CN.ts 与 en-US.ts 两个文件，key 结构完全一致
  - Header 导航区域出现语言切换器（中文 / English 下拉），切换后页面所有面向用户的文案随之变化
  - 用户选择持久化到 localStorage（key 如 baoboxs_lang），刷新及跳转后保持；首次访问时根据 navigator.language 自动判定（zh 开头→中文，其他→英文），默认兜底为中文
  - Element Plus 的 locale 跟随切换（分页、表单校验、日期选择器等组件内置文案随之切换），Day.js 也切换对应 locale
  - 以下核心页面完成中英双语：首页、分类页、搜索页（含搜索建议/热搜词区块）、热点页、AI 工作台 Tab 标题、登录/注册/找回密码页、个人中心（收藏/书签/快捷工具/账号设置）、用户公开主页、移动端底部 Tab 栏、404 页
  - 工具箱(/devtools) 至少完成: 页面标题、搜索占位符、分类筛选条、工具卡片名称与描述的英文版；工具内部详细说明字段允许保留中文(在文件头注释中标注 TODO)
  - 路由 meta.title 与浏览器标签页标题跟随语言切换
  - 后台管理(/admin/*) 暂不要求翻译，但需在 AdminLayout 顶部保留语言切换器，不得因切换语言产生 console 报错
  - 切换语言不破坏现有功能: 暗色模式、PWA、Ctrl+K 命令面板、工具收藏、登录态等行为保持正常
  - npm run build 成功，无 TypeScript 类型错误；浏览器控制台无新增 error
constraints:
  - 后端（baoboxs-server）不在本任务范围内，后端返回的错误 message、邮件正文保持中文
  - 工具箱 60+ 工具的「工具内详细说明」如全量翻译工作量过大，允许保留中文但需统一在源文件顶部加 `// TODO: i18n` 注释
  - 不得直接删除现有中文文案；中文必须迁移到 zh-CN.ts，不得硬编码
  - 切换语言时不得整页刷新（必须使用 vue-i18n 响应式切换）
context_files:
  - D:\study\baoboxs\REQUIREMENTS.md
  - D:\study\baoboxs\baoboxs-web\src\main.ts
  - D:\study\baoboxs\baoboxs-web\src\App.vue
  - D:\study\baoboxs\baoboxs-web\src\layouts\MainLayout.vue
  - D:\study\baoboxs\baoboxs-web\src\layouts\AdminLayout.vue
```
> **目标**：为前端项目（baoboxs-web）接入国际化框架，支持中文（默认）与英文切换，拓宽海外用户群。后端不在本任务范围内。

**技术选型**
- 使用 `vue-i18n@9`（Composition API 风格，与 Vue 3 配套）
- Locale 文件按模块拆分到 `src/locales/zh-CN/` 与 `src/locales/en-US/` 目录下（如 `common.ts`、`home.ts`、`auth.ts`、`user.ts`、`tools.ts`、`hot.ts`、`devtools.ts`、`errors.ts`），再由 `index.ts` 聚合导出
- 通过 `unplugin-auto-import` 自动导入 `useI18n` 需在 vite.config 中配置

**实现要点**
1. **基础设施**
   - 安装依赖：`vue-i18n`
   - 在 `src/locales/index.ts` 创建 i18n 实例，`legacy: false`、`fallbackLocale: 'zh-CN'`
   - 在 `main.ts` 中 `app.use(i18n)`
   - 创建 `src/composables/useLocale.ts`，封装切换语言 + 持久化 + 同步 Element Plus / Day.js locale 的逻辑

2. **语言检测与持久化**
   - 优先级：localStorage(`baoboxs_lang`) > `navigator.language` > `zh-CN`
   - 切换时同步写入 localStorage，并设置 `<html lang="...">`

3. **切换器 UI**
   - MainLayout 顶部导航与 AdminLayout 顶部都放置语言切换器（推荐 Element Plus `el-dropdown`）
   - 移动端在汉堡菜单内或底部 Tab 更多里露出
   - 图标 + 文字（🌐 中文 / English）

4. **Element Plus 与 Day.js 联动**
   - App.vue 根组件 `provide` 全局 `ElConfigProvider`，`:locale` 绑定到当前语言的 Element Plus locale 包
   - Day.js 使用 `dayjs.locale()` 切换

5. **路由标题 i18n**
   - 路由守卫中根据当前语言读取 `meta.titleKey`（i18n key），动态设置 `document.title`

6. **翻译范围（必须完成）**
   - 全局：导航菜单项、按钮（登录/注册/登出/搜索/收藏/分享/反馈/投递）、空状态文案、分页「共 X 条」、表单校验提示
   - 各业务页面（见 acceptance 列表）
   - 工具箱的页面级文案 + 工具卡片名称/描述；工具内部细节允许保留中文（加 TODO 注释）

7. **避免遗漏的工具**
   - 启动 dev 后用 grep 扫描 `src/` 下仍硬编码的中文（如 `<template>` 中直接写的中文字面量），逐一迁移
   - 注意 `placeholder`、`title`、`message`、`ElMessage.success/error`、`confirm` 等位置

8. **公共组件影响**
   - 修改 `SearchBar`、`ToolCard`、`WeatherWidget`、`CommandPalette`、`MobileTabBar`、`ShareDialog`、`FeedbackButton` 等公共组件时，所有可见文案改为 `t('xxx')`

**自检清单（Worker 完成前必跑）**
- [ ] 切换到英文后，逐页目视检查：首页 / 分类 / 搜索 / 热点 / 工具箱列表 / 登录 / 注册 / 个人中心
- [ ] 切回中文，确认无未翻译回的占位符（如 `home.title`）
- [ ] 刷新页面语言保持
- [ ] 浏览器控制台无报错
- [ ] `npm run build` 通过

**回执要求**
- 在「关键决策」中写明：locale 文件目录结构、key 命名规范（如 `module.submodule.key`）、未翻译遗留清单
- 在「对下游的提醒」中提醒：后续新增前端页面/组件必须使用 `t()`，否则会被 T3 及后续任务打回


### [T3] 主题市场（自定义配色 / 布局密度 / 卡片样式）
```yaml
id: T3
depends_on: []
touches:
  - D:\study\baoboxs\baoboxs-web\src\styles
  - D:\study\baoboxs\baoboxs-web\src\composables
  - D:\study\baoboxs\baoboxs-web\src\stores
  - D:\study\baoboxs\baoboxs-web\src\components
  - D:\study\baoboxs\baoboxs-web\src\layouts
  - D:\study\baoboxs\baoboxs-web\src\views\ProfileView.vue
  - D:\study\baoboxs\baoboxs-web\src\main.ts
  - D:\study\baoboxs\baoboxs-web\package.json
acceptance:
  - 在「账号设置」页新增「主题市场」入口，弹出/跳转后可看到至少 5 个预设主题（如 默认蓝、极夜紫、莫兰迪、护眼绿、暖橙），点击即可一键切换
  - 主题切换实时生效，无需刷新；用户选择持久化到 localStorage（key 如 baoboxs_theme），刷新及重新打开后保持
  - 提供自定义主色调色板（el-color-picker），自定义主色后所有依赖主色的元素（按钮、链接、激活态标签、focus 描边、Chart 主色）随之变化
  - 提供「布局密度」三档切换：紧凑 / 标准 / 宽松，影响列表/卡片的 padding、gap、行高；切换后肉眼可观察到差异
  - 提供「卡片样式」可选项：圆角（直角 / 小圆角 / 大圆角）、阴影（无 / 轻 / 明显），影响 ToolCard、分类卡、统计卡等卡片组件
  - 主题与「明暗模式」正交：任意预设主题都能搭配亮色或暗色，组合后无文字与背景对比度过低（WCAG AA 起步，正文 ≥ 4.5:1）
  - 所有颜色、圆角、间距、阴影值通过 CSS 变量（如 --bb-color-primary、--bb-radius-card、--bb-spacing-md、--bb-shadow-card）定义；源码中不得再硬编码新的 #颜色 / px 间距
  - 暗色模式下每个预设主题都有对应配色（不能出现暗色下文字看不见、按钮不可识别等问题）
  - 后台管理界面也跟随主题变化（至少主色、圆角生效）
  - 移动端主题市场面板布局正常，可滚动、可点击
  - 提供「恢复默认」按钮，一键回到默认蓝 + 标准 + 大圆角 + 轻阴影
  - npm run build 成功；浏览器无 console 报错；无样式错乱（卡片溢出、按钮变形等）
constraints:
  - 必须基于 CSS 变量实现，不得使用 CSS-in-JS 或运行时大量动态生成样式表
  - 不得移除或破坏现有的「亮色/暗色」切换功能（FR-2.12.1），需在之上叠加
  - ECharts 图表主色需在主题切换时同步更新（通过 provide/inject 或 watch 主题变量重新设置 chart option）
  - 颜色变化不得触发整页刷新
  - 不得引入体积过大的主题库（如自研实现，避免引入 tailwind 主题包等额外依赖）
context_files:
  - D:\study\baoboxs\REQUIREMENTS.md
  - D:\study\baoboxs\baoboxs-web\src\styles\
  - D:\study\baoboxs\baoboxs-web\src\App.vue
  - D:\study\baoboxs\baoboxs-web\src\stores\user.ts
```
> **目标**：在现有亮/暗主题基础上，新增「主题市场」能力，让用户可挑选预设主题、自定义主色、调整布局密度与卡片样式，提升个性化体验与产品辨识度。

**设计原则**
1. **CSS 变量驱动**：所有视觉令牌（token）以 `--bb-*` 前缀定义为 CSS 变量，挂在 `:root` 与 `[data-theme="xxx"]` 上；JS 只负责切换 `data-theme` / `data-density` / `data-card-style` 等 `<html>` 属性
2. **主题 = 主色 + 中性色偏移 + 暗色映射**：每个预设主题定义亮/暗两套 token，避免单独维护 5×2=10 套

**实现要点**

1. **Token 体系（src/styles/tokens.scss）**
   ```scss
   :root {
     // 主色系（每个主题 override 这一组）
     --bb-color-primary: #409eff;
     --bb-color-primary-hover: #66b1ff;
     --bb-color-primary-active: #3a8ee6;
     // 中性色
     --bb-color-bg: #ffffff;
     --bb-color-bg-soft: #f5f7fa;
     --bb-color-text: #303133;
     --bb-color-text-secondary: #606266;
     --bb-color-border: #dcdfe6;
     // 间距（密度档位 override）
     --bb-spacing-xs: 4px;
     --bb-spacing-sm: 8px;
     --bb-spacing-md: 16px;
     --bb-spacing-lg: 24px;
     // 圆角与阴影（卡片样式 override）
     --bb-radius-card: 12px;
     --bb-radius-btn: 6px;
     --bb-shadow-card: 0 2px 8px rgba(0,0,0,.08);
   }
   [data-theme="violet"] { --bb-color-primary: #7c5cff; /* ... */ }
   [data-density="compact"] { --bb-spacing-md: 8px; /* ... */ }
   [data-card-style="rounded"] { --bb-radius-card: 18px; }
   ```

2. **预设主题清单**（至少 5 个，命名 + 主色建议）
   | id | 名称 | 主色 | 备注 |
   |---|---|---|---|
   | `blue` | 默认蓝 | `#409eff` | 与 Element Plus 默认对齐 |
   | `violet` | 极夜紫 | `#7c5cff` | 现代感 |
   | `morandi` | 莫兰迪 | `#9aa5b1` | 低饱和 |
   | `green` | 护眼绿 | `#3aa675` | 长时间使用友好 |
   | `orange` | 暖橙 | `#ff7d00` | 活泼 |

3. **Pinia store（src/stores/theme.ts）**
   - state: `themeId`、`customPrimary`（可空）、`density`、`cardRadius`、`cardShadow`、`darkMode`
   - actions: `setTheme(id)`、`setCustomPrimary(color)`、`setDensity(level)`、`setCardStyle(...)`、`reset()`
   - 持久化：watch 全部 state → 写入 localStorage；初始化时从 localStorage 恢复
   - 副作用：每次变更调用 `applyTheme()`，把对应属性写到 `document.documentElement.dataset.*`

4. **自定义主色**
   - 用户选了自定义色后，按主色派生 hover / active / disabled（用 HSL 计算或用 color-mix）
   - 覆盖 `--bb-color-primary*` 变量

5. **明暗模式适配**
   - 现有的「暗色模式」开关切换 `data-mode="dark"`
   - 每个 token 提供 `.dark` 或 `[data-mode="dark"]` 下的覆盖值
   - 自定义主色在暗色下若对比不足，自动调亮（用 JS 简单判断）

6. **ECharts 联动**
   - 封装 `useChartTheme()` composable，从 theme store 取主色，作为图表默认 color 数组首位
   - 切换主题时通过 `chart.setOption({ color })` 更新

7. **主题市场 UI**
   - 入口位置：`ProfileView`（账号设置）新增「主题市场」卡片，点击打开 `el-drawer`
   - 抽屉分三块：① 预设主题网格（5 个色卡，hover 预览，点击应用）② 自定义主色 colorpicker ③ 布局密度（单选）+ 卡片样式（圆角/阴影单选）+ 明暗切换（沿用现有）
   - 每个预设主题卡片用主题色作为背景预览

8. **改造范围**
   - 全局搜索 `#409eff`、`#fff`、`padding: 12px` 等硬编码，逐步替换为 CSS 变量
   - 重点文件：`ToolCard.vue`、`CategoryNav.vue`、`SearchBar.vue`、`WeatherWidget.vue`、各 `*Manage.vue` 后台卡片

**自检清单**
- [ ] 切换 5 个主题，每个主题下首屏目视无违和
- [ ] 同一主题切到暗色，文字清晰可读
- [ ] 切换布局密度三档，能肉眼看出列表/卡片间距变化
- [ ] 切换卡片圆角/阴影，ToolCard 视觉变化明显
- [ ] 自定义主色后，「登录」「搜索」「收藏」按钮颜色都跟随
- [ ] ECharts 图表主色跟随主题（在 StatisticsView 验证）
- [ ] 移动端主题市场抽屉可滚动、不溢出
- [ ] 刷新后主题保持
- [ ] `npm run build` 通过

**回执要求**
- 「关键决策」写明：token 命名规范（`--bb-*` 前缀的完整清单）、5 个主题的色板表、密度/卡片样式各档对应的具体数值
- 「对下游的提醒」提醒：后续所有新组件必须使用 `--bb-*` CSS 变量，禁止硬编码颜色/间距；新图表必须通过 `useChartTheme()` 取色
