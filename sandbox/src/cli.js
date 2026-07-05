// CLI 入口：温度换算命令行工具
// 用法: node src/cli.js <温度><单位>  例如 100C 或 32F

const { c2f, f2c } = require('./convert.js');

// 打印中文用法提示（输出到 stderr）
function printUsage() {
  console.error('用法: node src/cli.js <温度><单位>');
  console.error('  单位为 C（摄氏）或 F（华氏），例如:');
  console.error('    node src/cli.js 100C   -> 换算为华氏');
  console.error('    node src/cli.js 32F    -> 换算为摄氏');
}

const arg = process.argv[2];

// 参数缺失
if (!arg) {
  printUsage();
  process.exit(1);
}

// 匹配形如 100C / -40f / 36.6C 的输入（单位大小写均可）
const match = /^(-?\d+(?:\.\d+)?)([cCfF])$/.exec(arg.trim());

// 格式非法
if (!match) {
  printUsage();
  process.exit(1);
}

const value = parseFloat(match[1]);
const unit = match[2].toUpperCase();

// 根据单位选择换算方向，结果保留两位小数（上游约定：精度处理由 CLI 负责）
if (unit === 'C') {
  console.log(`${value}°C = ${parseFloat(c2f(value).toFixed(2))}°F`);
} else {
  console.log(`${value}°F = ${parseFloat(f2c(value).toFixed(2))}°C`);
}
