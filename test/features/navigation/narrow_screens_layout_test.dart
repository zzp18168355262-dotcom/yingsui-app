/// 主要界面在手机竖屏宽度下的布局回归检查。
///
/// 实测驱动：此前已发现三处只在窄屏出现的溢出
///   1) 逐词全文头部（390 宽度，横向 25px）
///   2) PadTopBar（320–600 宽度，纵向 1px）
///   3) 首页收藏统计（320 宽度，横向 25px）
/// 这些在截图上看不出来，真机上却会出现黄黑溢出条纹。
/// 本文件把各主要界面在常用手机宽度下都渲染一遍，防止再靠肉眼发现。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yingsui/features/growth/presentation/growth_screen.dart';
import 'package:yingsui/features/home/presentation/pad_home_screen.dart';
import 'package:yingsui/features/library/presentation/library_screen.dart';
import 'package:yingsui/features/phrases/presentation/phrases_screen.dart';
import 'package:yingsui/features/settings/presentation/settings_screen.dart';

GoRouter _routerFor(String location) {
  return GoRouter(
    initialLocation: location,
    routes: <GoRoute>[
      GoRoute(
        path: '/home',
        builder: (BuildContext context, GoRouterState state) =>
            const PadHomeScreen(),
      ),
      GoRoute(
        path: '/library',
        builder: (BuildContext context, GoRouterState state) =>
            const LibraryScreen(),
      ),
      GoRoute(
        path: '/phrases',
        builder: (BuildContext context, GoRouterState state) =>
            const PhrasesScreen(),
      ),
      GoRoute(
        path: '/growth',
        builder: (BuildContext context, GoRouterState state) =>
            const GrowthScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
      ),
    ],
  );
}

void main() {
  const Map<String, String> screens = <String, String>{
    '首页': '/home',
    '资源库': '/library',
    '短语本': '/phrases',
    '成长': '/growth',
    '设置': '/settings',
  };

  for (final double width in <double>[320, 390, 430]) {
    for (final MapEntry<String, String> entry in screens.entries) {
      testWidgets('${entry.key}在宽度 $width 下不溢出', (WidgetTester tester) async {
        tester.view.physicalSize = Size(width * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(routerConfig: _routerFor(entry.value)),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} $width 宽度加载时出现布局异常',
        );

        // 滚动到底，让下半部分也参与布局。
        final Finder scrollable = find.byType(Scrollable);
        if (scrollable.evaluate().isNotEmpty) {
          for (int i = 0; i < 8; i += 1) {
            await tester.drag(scrollable.first, const Offset(0, -320));
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${entry.key} $width 宽度滚动中出现布局异常',
            );
          }
        }
      });
    }
  }
}
