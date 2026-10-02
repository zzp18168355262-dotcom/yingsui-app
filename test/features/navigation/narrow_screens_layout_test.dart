/// 主要界面在手机/iPad 尺寸下的布局回归检查。
///
/// 实测驱动：此前已发现多处只在特定宽度出现的溢出
///   1) 逐词全文头部（390 宽度，横向 25px）
///   2) PadTopBar（320–600 宽度，纵向 1px）
///   3) 首页收藏统计（320 宽度，横向 25px）
/// 这些在截图上不易察觉，真机上却会出现黄黑溢出条纹。
/// 本文件把各主要界面在常用手机与 iPad 尺寸下都渲染一遍，
/// 并在滚动过程中持续检查，避免再靠肉眼发现问题。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yingsui/features/growth/presentation/growth_screen.dart';
import 'package:yingsui/features/guide/presentation/guide_screen.dart';
import 'package:yingsui/features/home/presentation/pad_home_screen.dart';
import 'package:yingsui/features/import_course/presentation/import_course_screen.dart';
import 'package:yingsui/features/library/presentation/library_screen.dart';
import 'package:yingsui/features/phrases/presentation/phrase_review_screen.dart';
import 'package:yingsui/features/phrases/presentation/phrases_screen.dart';
import 'package:yingsui/features/settings/presentation/settings_screen.dart';
import 'package:yingsui/features/words/presentation/words_screen.dart';

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
      GoRoute(
        path: '/words',
        builder: (BuildContext context, GoRouterState state) =>
            const WordsScreen(),
      ),
      GoRoute(
        path: '/guide',
        builder: (BuildContext context, GoRouterState state) =>
            const GuideScreen(),
      ),
      GoRoute(
        path: '/phrases/review',
        builder: (BuildContext context, GoRouterState state) =>
            const PhraseReviewScreen(),
      ),
      GoRoute(
        path: '/importCourse',
        builder: (BuildContext context, GoRouterState state) =>
            const ImportCourseScreen(),
      ),
    ],
  );
}

void main() {
  const Map<String, String> screens = <String, String>{
    '首页': '/home',
    '资源库': '/library',
    '短语本': '/phrases',
    '短语复习': '/phrases/review',
    '单词库': '/words',
    '成长': '/growth',
    '怎么学': '/guide',
    '设置': '/settings',
    '导入课程': '/importCourse',
  };

  // 宽度 → 高度：覆盖小屏手机、常见手机、大屏手机、iPad 竖屏与横屏。
  // 高度按各设备真实比例给，避免拿手机高度去测 iPad 宽度（比例失真）。
  const List<(double, double)> viewports = <(double, double)>[
    (320, 568), // iPhone SE（小屏极限）
    (390, 844), // iPhone 标准
    (430, 932), // iPhone Pro Max
    (820, 1180), // iPad 竖屏
    (1180, 820), // iPad 横屏
  ];

  for (final (double width, double height) in viewports) {
    for (final MapEntry<String, String> entry in screens.entries) {
      testWidgets('${entry.key} 在 ${width}x$height 下不溢出', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = Size(width * 2, height * 2);
        tester.view.devicePixelRatio = 2;
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
          reason: '${entry.key} ${width}x$height 加载时出现布局异常',
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
              reason: '${entry.key} ${width}x$height 滚动中出现布局异常',
            );
          }
        }
      });
    }
  }
}
