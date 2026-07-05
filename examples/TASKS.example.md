# 任务清单：个人书签管理网站

## 全局上下文
构建一个纯前端的个人书签管理网站，无需后端。
- 技术栈：原生 HTML/CSS/JavaScript（ES6+），禁止引入框架和构建工具
- 数据持久化：浏览器 localStorage
- 目录结构：`src/` 下放源码，入口为 `src/index.html`
- 视觉风格：简洁明亮，圆角卡片式布局
- 所有代码注释与 UI 文案使用中文

## 任务

### [T1] 设计数据模型与存储层
```yaml
id: T1
depends_on: []
touches:
  - src/js/storage.js
  - docs/data-model.md
acceptance:
  - src/js/storage.js 导出 addBookmark / removeBookmark / listBookmarks / updateBookmark 四个函数
  - 书签字段至少包含 id、标题、URL、标签数组、创建时间
  - docs/data-model.md 用表格记录字段定义与每个函数的签名和行为
constraints:
  - 存储键名统一以 "bm:" 为前缀
```
设计书签的数据结构，并实现基于 localStorage 的存储模块。这是所有后续功能的地基，接口签名一旦确定下游都会依赖，请在回执的「对下游的提醒」中完整给出各函数签名。

### [T2] 页面骨架与样式
```yaml
id: T2
depends_on: []
touches:
  - src/index.html
  - src/css/
acceptance:
  - src/index.html 在浏览器打开无 console 报错
  - 页面包含三个具名容器：#add-form（添加表单区）、#bookmark-list（列表区）、#tag-filter（标签筛选区）
  - 样式独立于 src/css/style.css, 不使用内联样式
constraints:
  - 不写任何业务 JavaScript 逻辑, 只做结构与样式
```
搭建页面 HTML 骨架和 CSS 样式：顶部为添加书签的表单区，中部为标签筛选栏，下方为书签卡片列表。三个容器的 id 是与 T3/T4 的接口约定，不得更改。

### [T3] 添加与删除书签功能
```yaml
id: T3
depends_on: [T1, T2]
touches:
  - src/js/app.js
  - src/index.html
acceptance:
  - 在表单输入标题和 URL 后提交, 新书签卡片出现在列表区且刷新页面后仍存在
  - 每张卡片有删除按钮, 点击后卡片消失且 localStorage 中对应数据被删除
  - URL 为空或格式非法时给出提示且不保存
```
基于 T1 的存储层和 T2 的页面骨架，实现添加、删除书签的完整交互。修改 index.html 仅限于引入 script 标签。

### [T4] 标签筛选功能
```yaml
id: T4
depends_on: [T3]
touches:
  - src/js/filter.js
  - src/index.html
acceptance:
  - "#tag-filter 区域动态展示当前所有书签的标签去重集合"
  - 点击标签后列表只显示含该标签的书签, 再次点击取消筛选
  - 添加/删除书签后标签集合自动刷新
```
实现按标签筛选书签。注意与 T3 的 app.js 协作：筛选状态变化时的列表重绘应复用 T3 暴露的渲染函数（具体函数名以 T3 回执为准）。

### [T5] 导入导出功能
```yaml
id: T5
depends_on: [T3]
touches:
  - src/js/porter.js
  - src/index.html
acceptance:
  - 点击导出按钮下载包含全部书签的 JSON 文件
  - 通过文件选择器导入 JSON 后, 书签合并进现有数据（id 冲突时保留现有）
  - 导入非法 JSON 时提示错误且现有数据不受影响
```
实现书签数据的 JSON 导入导出，方便备份迁移。

### [T6] 使用文档
```yaml
id: T6
depends_on: [T4, T5]
touches:
  - docs/user-guide.md
context_files:
  - docs/data-model.md
acceptance:
  - 覆盖添加、删除、标签筛选、导入导出全部功能的操作说明
  - 包含一节"数据存储说明", 告知用户数据存在 localStorage 及清除浏览器数据的风险
```
面向最终用户编写使用文档，语言通俗，配合功能逐节说明。
