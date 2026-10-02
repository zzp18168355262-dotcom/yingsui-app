import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/home/presentation/home_greeting.dart';

/// 首页问候语。
///
/// 回归背景：原先界面上写死「晚上好 Mark 👋」，
///   1) 早上打开也显示「晚上好」
///   2) 「Mark」是硬编码示例人名，所有用户都会看到别人的名字
void main() {
  test('按时段返回对应问候语', () {
    expect(greetingForHour(0), '夜深了');
    expect(greetingForHour(4), '夜深了');
    expect(greetingForHour(5), '早上好');
    expect(greetingForHour(8), '早上好');
    expect(greetingForHour(10), '早上好');
    expect(greetingForHour(11), '中午好');
    expect(greetingForHour(12), '中午好');
    expect(greetingForHour(13), '下午好');
    expect(greetingForHour(17), '下午好');
    expect(greetingForHour(18), '晚上好');
    expect(greetingForHour(23), '晚上好');
  });

  test('覆盖 0–23 全部小时且不含人名', () {
    for (int hour = 0; hour < 24; hour += 1) {
      final String greeting = greetingForHour(hour);
      expect(greeting, isNotEmpty);
      expect(
        greeting.contains('Mark'),
        isFalse,
        reason: '问候语不应包含任何硬编码人名',
      );
    }
  });
}
