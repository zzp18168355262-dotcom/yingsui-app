import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yingsui/features/growth/presentation/growth_screen.dart';
import 'package:yingsui/features/home/presentation/pad_home_screen.dart';
import 'package:yingsui/features/import_course/presentation/import_course_screen.dart';
import 'package:yingsui/features/library/presentation/library_screen.dart';
import 'package:yingsui/features/phrases/presentation/phrases_screen.dart';
import 'package:yingsui/features/player/presentation/player_screen.dart';
import 'package:yingsui/router/app_router.dart';

void main() {
  _narrowWidthLayoutTests();

  testWidgets('home quick entries and hero navigate to prototype targets', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = buildAppTestRouter();

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    // 问候语按时段变化，且不再包含硬编码人名。
    expect(find.textContaining('👋'), findsOneWidget);
    expect(find.textContaining('Mark'), findsNothing);
    expect(find.text('继续你的英语成长旅程'), findsOneWidget);
    expect(find.text('今日挑战'), findsOneWidget);
    expect(find.text('英语成长'), findsWidgets);
    await tester.tap(find.text('英语成长').last);
    await tester.pumpAndSettle();
    expect(find.text('英语成长之旅'), findsOneWidget);

    router.go(SGRoute.home.route);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('复习我的短语'),
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('home-page-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('复习我的短语'), findsOneWidget);
    await tester.ensureVisible(find.text('复习我的短语'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复习我的短语'));
    await tester.pumpAndSettle();

    expect(find.text('新增短语'), findsOneWidget);

    router.go(SGRoute.home.route);
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入你的第一套英语视频课程'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, SGRoute.home.route);
    expect(find.text('导入影视'), findsOneWidget);
    expect(find.text('选择视频文件夹'), findsWidgets);
  });
}

/// 构造一个覆盖主要界面的测试路由，供多个用例复用。
GoRouter buildAppTestRouter() {
  return GoRouter(
    initialLocation: SGRoute.home.route,
    routes: <GoRoute>[
      GoRoute(
        path: SGRoute.home.route,
        builder: (BuildContext context, GoRouterState state) =>
            const PadHomeScreen(),
      ),
      GoRoute(
        path: SGRoute.phrases.route,
        builder: (BuildContext context, GoRouterState state) =>
            const PhrasesScreen(),
      ),
      GoRoute(
        path: SGRoute.library.route,
        builder: (BuildContext context, GoRouterState state) =>
            const LibraryScreen(),
      ),
      GoRoute(
        path: SGRoute.growth.route,
        builder: (BuildContext context, GoRouterState state) =>
            const GrowthScreen(),
      ),
      GoRoute(
        path: SGRoute.importCourse.route,
        builder: (BuildContext context, GoRouterState state) =>
            const ImportCourseScreen(),
      ),
      GoRoute(
        path: '/episodes/:episodeId',
        name: SGRoute.player.name,
        builder: (BuildContext context, GoRouterState state) =>
            PlayerScreen(episodeId: state.pathParameters['episodeId']!),
      ),
    ],
  );
}

/// 主要界面在手机竖屏宽度下的布局检查。
///
/// 实测驱动的回归检查：此前逐词全文头部与 PadTopBar 分别在
/// 390 与 320 宽度下出现溢出（真机上是黄黑条纹警告）。
/// 这里把常用宽度都跑一遍，避免再靠肉眼发现。
void _narrowWidthLayoutTests() {
  for (final double width in <double>[320, 390, 430]) {
    testWidgets('主要界面在宽度 $width 下不溢出', (WidgetTester tester) async {
      tester.view.physicalSize = Size(width * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: buildAppTestRouter()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$width 宽度首页出现布局异常');

      // 逐页滚动，触达需要滚动才参与布局的内容。
      for (int i = 0; i < 6; i += 1) {
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -320),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$width 宽度首页滚动中出现异常',
        );
      }
    });
  }
}
