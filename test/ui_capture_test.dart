/// 把主要页面渲染成 PNG，供人工核对 UI。
///
/// 用途：这套 Xcode 环境里没有 Simulator.app（无法打开模拟器界面），
/// 因此改为在测试环境把每个页面画出来并导出图片。
///
/// 关键点：导出必须包在 `tester.runAsync()` 里。
/// `RepaintBoundary.toImage()` 需要真实的异步渲染，直接 await 会挂起。
///
/// 产物：build/ui-shots/<序号>-<页面名>.png
///
/// 运行：
///   flutter test test/ui_capture_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yingsui/features/growth/presentation/growth_screen.dart';
import 'package:yingsui/features/guide/presentation/guide_screen.dart';
import 'package:yingsui/features/home/presentation/pad_home_screen.dart';
import 'package:yingsui/features/import_course/presentation/import_course_screen.dart';
import 'package:yingsui/features/library/presentation/library_catalog_provider.dart';
import 'package:yingsui/features/library/presentation/library_mock_data.dart';
import 'package:yingsui/features/library/presentation/library_screen.dart';
import 'package:yingsui/features/phrases/presentation/phrase_review_screen.dart';
import 'package:yingsui/features/phrases/presentation/phrases_screen.dart';
import 'package:yingsui/features/settings/presentation/settings_screen.dart';
import 'package:yingsui/features/words/presentation/words_screen.dart';

/// 演示用课程数据：让列表/卡片有真实内容可展示（否则多为空状态）。
const LibraryCourseData _demoCourse = LibraryCourseData(
  id: 'ui-demo',
  title: '老友记 · 精听训练',
  description: '日常口语精听',
  sourceLabel: '本地资源',
  coverImage: '',
  level: 'B1',
  category: '美剧',
  progressPercent: 40,
  totalWords: 12,
  completedEpisodes: 2,
  totalEpisodes: 5,
  lastStudiedStr: '2 小时前',
  rating: 4.5,
  episodes: <LibraryEpisodeItem>[
    LibraryEpisodeItem(
      id: 'ui-ep1',
      numberStr: '01',
      title: '初见 · 咖啡店',
      durationMinutes: 22,
      hasChineseSubtitles: true,
      hasEnglishSubtitles: true,
      completed: true,
      progressPercent: 100,
      coverImage: '',
      enSubtitleAsset: 'assets/test/player/en.srt',
      cnSubtitleAsset: 'assets/test/player/zh.srt',
    ),
    LibraryEpisodeItem(
      id: 'ui-ep2',
      numberStr: '02',
      title: '重逢 · 洗衣房',
      durationMinutes: 21,
      hasChineseSubtitles: true,
      hasEnglishSubtitles: true,
      completed: false,
      progressPercent: 35,
      coverImage: '',
      enSubtitleAsset: 'assets/test/player/en.srt',
      cnSubtitleAsset: 'assets/test/player/zh.srt',
    ),
  ],
);

class _DemoCatalog extends LibraryCatalogNotifier {
  @override
  List<LibraryCourseData> build() => const <LibraryCourseData>[_demoCourse];
}

final GlobalKey _rootKey = GlobalKey(debugLabel: 'ui-capture-root');

GoRouter _routerFor(String location) {
  return GoRouter(
    initialLocation: location,
    routes: <GoRoute>[
      GoRoute(
        path: '/home',
        builder: (BuildContext c, GoRouterState s) => const PadHomeScreen(),
      ),
      GoRoute(
        path: '/library',
        builder: (BuildContext c, GoRouterState s) => const LibraryScreen(),
      ),
      GoRoute(
        path: '/phrases',
        builder: (BuildContext c, GoRouterState s) => const PhrasesScreen(),
      ),
      GoRoute(
        path: '/phrases/review',
        builder: (BuildContext c, GoRouterState s) =>
            const PhraseReviewScreen(),
      ),
      GoRoute(
        path: '/words',
        builder: (BuildContext c, GoRouterState s) => const WordsScreen(),
      ),
      GoRoute(
        path: '/growth',
        builder: (BuildContext c, GoRouterState s) => const GrowthScreen(),
      ),
      GoRoute(
        path: '/guide',
        builder: (BuildContext c, GoRouterState s) => const GuideScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (BuildContext c, GoRouterState s) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/importCourse',
        builder: (BuildContext c, GoRouterState s) =>
            const ImportCourseScreen(),
      ),
    ],
  );
}

Widget _wrap(String route) {
  return ProviderScope(
    // ignore: always_specify_types
    overrides: [libraryCatalogProvider.overrideWith(_DemoCatalog.new)],
    child: RepaintBoundary(
      key: _rootKey,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        // 让中文用上面加载的字体渲染（否则是方框）。
        theme: ThemeData(
          fontFamily: 'Nunito',
          fontFamilyFallback: const <String>['CJK'],
        ),
        routerConfig: _routerFor(route),
      ),
    ),
  );
}

/// 导出当前界面为 PNG。
///
/// 必须放在 runAsync 里：toImage 依赖真实异步渲染管线，
/// 在测试的 fake async 环境下直接 await 会永久挂起（实测）。
Future<void> capture(WidgetTester tester, String fileName) async {
  await tester.runAsync(() async {
    final RenderRepaintBoundary boundary =
        _rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (bytes == null) {
      return;
    }
    final Directory dir = Directory('build/ui-shots');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final String path = '${dir.path}/$fileName.png';
    File(path).writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// 载入系统中文字体。
///
/// 测试环境默认不带中文字形，中文会渲染成方框（□），
/// 截出来的图看不出内容。这里从 /System/Library/Fonts 读一个中文字体
/// 注册为 fallback，使截图与真机观感一致。
Future<void> loadChineseFont() async {
  const List<String> candidates = <String>[
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
    '/System/Library/Fonts/STHeiti Medium.ttc',
    '/System/Library/Fonts/PingFang.ttc',
  ];
  for (final String path in candidates) {
    final File file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final ByteData data = ByteData.view(
      file.readAsBytesSync().buffer,
    );
    final FontLoader loader = FontLoader('CJK')
      ..addFont(Future<ByteData>.value(data));
    await loader.load();
    return;
  }
}

void main() {
  setUpAll(loadChineseFont);

  const List<(String, String)> pages = <(String, String)>[
    ('01-首页', '/home'),
    ('02-资源库', '/library'),
    ('03-短语本', '/phrases'),
    ('04-短语复习', '/phrases/review'),
    ('05-单词库', '/words'),
    ('06-成长', '/growth'),
    ('07-怎么学', '/guide'),
    ('08-设置', '/settings'),
    ('09-导入课程', '/importCourse'),
  ];

  for (final (String name, String route) in pages) {
    testWidgets('截取 $name', (WidgetTester tester) async {
      // 手机竖屏（iPhone 标准尺寸的 2 倍像素）。
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(route));
      // 不用 pumpAndSettle：部分页面有持续动画会使其不返回。
      for (int i = 0; i < 6; i += 1) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      await capture(tester, name);

      // 顺带断言加载过程没有布局异常。
      expect(
        tester.takeException(),
        isNull,
        reason: '$name 渲染时出现布局异常',
      );
    });
  }
}
