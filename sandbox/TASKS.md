# 任务清单：CLI 温度换算工具

## 全局上下文
用 Node.js 编写一个命令行温度换算小工具，纯标准库，无任何 npm 依赖。
- 源码放在 src/ 下
- 代码注释使用中文

## 任务

### [T1] 换算核心模块
```yaml
id: T1
depends_on: []
touches:
  - src/convert.js
acceptance:
  - src/convert.js 导出 c2f 和 f2c 两个函数（摄氏↔华氏）
  - "node -e \"const{c2f,f2c}=require('./src/convert.js');console.log(c2f(100),f2c(32))\" 输出 212 0"
constraints:
  - 使用 CommonJS 模块（module.exports）
```
实现摄氏与华氏互转的纯函数模块。函数签名是下游 CLI 的依赖，请写进回执的下游提醒。

### [T2] CLI 入口
```yaml
id: T2
depends_on: [T1]
touches:
  - src/cli.js
acceptance:
  - "node src/cli.js 100C 输出包含 212"
  - "node src/cli.js 32F 输出包含 0"
  - 参数缺失或格式非法时输出中文用法提示, 退出码为 1
```
基于 T1 的换算模块实现 CLI：接受一个形如 `100C` 或 `32F` 的参数，输出换算结果。
