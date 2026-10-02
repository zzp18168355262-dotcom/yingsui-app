/// UI 巡检：在真实设备/模拟器上启动应用，逐屏截图。
///
/// 用官方 driver 方式运行（截图由 driver 落盘）：
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/ui_tour_test.dart \
///     -d <deviceId>
///
/// 截图保存到 build/ui-tour/ 下。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yingsui/main.dart' as app;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 点击底部导航项（贴近平板/手机上的真实操作路径）。
  ///
  /// 不用 GoRouter.of(context)：该 context 位于 MaterialApp.router 之上，
  /// 取不到路由（会报 "No GoRouter found in context"）。
  Future<bool> tapNav(WidgetTester tester, String label) async {
    final Finder item = find.text(label);
    if (item.evaluate().isEmpty) {
      return false;
    }
    await tester.tap(item.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    return true;
  }

  testWidgets('UI 巡检：遍历主要页面', (WidgetTester tester) async {
    unawaited(app.main(<String>[]));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 底部导航上的主要页面。名称与 AppNavDestination.label 对应。
    for (final (String navLabel, String shot) in <(String, String)>[
      ('首页', '01-首页'),
      ('学习', '02-学习'),
      ('成长', '03-成长'),
      ('短语', '04-短语库'),
      ('单词', '05-单词库'),
      ('设置', '06-设置'),
    ]) {
      final bool ok = await tapNav(tester, navLabel);
      if (!ok) {
        // 记录缺失项，便于判断是「导航项不存在」还是「渲染出错」。
        // ignore: avoid_print
        print('巡检：未找到导航项「$navLabel」');
        continue;
      }
      await binding.takeScreenshot(shot);
    }
  });
}
