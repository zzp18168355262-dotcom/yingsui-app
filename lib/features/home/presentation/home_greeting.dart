/// 首页问候语。
///
/// 独立成文件是为了可测试：原先写死在界面里，且硬编码了示例人名
/// 「Mark」与固定时段「晚上好」，早上打开也显示晚上好。
library;

/// 根据当前小时（0–23）返回问候语。
String greetingForHour(int hour) {
  if (hour < 5) return '夜深了';
  if (hour < 11) return '早上好';
  if (hour < 13) return '中午好';
  if (hour < 18) return '下午好';
  return '晚上好';
}
