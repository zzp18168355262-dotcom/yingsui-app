/// UI 巡检：在真实设备/模拟器上渲染应用并逐屏截图。
///
/// 用官方 driver 方式运行（截图由 driver 落盘）：
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/ui_tour_test.dart \
///     -d <deviceId>
///
/// 截图保存到 build/ui-tour/ 下（相对于运行命令时的工作目录）。
///
/// 为什么直接渲染 MyApp 而不是 app.main()：
///   main() 里的 bootstrap 是异步的（初始化 Hive、本地化、视频后端等），
///   pumpAndSettle 不等这些 Future，导致界面根本没渲染出来
///   （实测连「首页」都找不到）。这里改为自己包好 ProviderScope +
///   EasyLocalization 后直接渲染 MyApp，渲染立即可用。
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yingsui/constants/strings.dart';
import 'package:yingsui/my_app.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 推进若干帧。
  ///
  /// 不用 pumpAndSettle：页面里有持续动画（加载指示、渐变呼吸），
  /// 会让它一直不返回（实测卡死）。
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('UI 巡检：遍历主要页面', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: EasyLocalization(
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          path: Strings.localizationsPath,
          fallbackLocale: const Locale('zh'),
          child: const MyApp(),
        ),
      ),
    );
    await settle(tester);

    // 底部导航上的页面。名称与 AppNavDestination.label 一致。
    for (final (String navLabel, String shot) in <(String, String)>[
      ('首页', '01-首页'),
      ('学习', '02-学习'),
      ('成长', '03-成长'),
      ('更多', '04-更多菜单'),
    ]) {
      final Finder item = find.text(navLabel);
      if (item.evaluate().isEmpty) {
        // ignore: avoid_print
        print('巡检：未找到「$navLabel」');
        continue;
      }
      await tester.tap(item.first);
      await settle(tester);
      await binding.takeScreenshot(shot);
    }
  });
}
