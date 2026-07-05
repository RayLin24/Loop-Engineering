// 温度换算核心模块：摄氏与华氏互转的纯函数
// 公式: F = C * 9/5 + 32; C = (F - 32) * 5/9

/**
 * 摄氏转华氏
 * @param {number} c 摄氏温度
 * @returns {number} 华氏温度
 */
function c2f(c) {
  return c * 9 / 5 + 32;
}

/**
 * 华氏转摄氏
 * @param {number} f 华氏温度
 * @returns {number} 摄氏温度
 */
function f2c(f) {
  return (f - 32) * 5 / 9;
}

module.exports = { c2f, f2c };
