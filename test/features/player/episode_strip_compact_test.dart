/// 课程目录的占用高度。
///
/// 用户反馈：目录部分占空间太大。
/// 原先「标题行 + 108px 卡片列表」常驻约 150px，而切集是低频操作。
/// 现在默认收起，只保留一行标题（含剧集数与展开按钮）。
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/library/presentation/library_mock_data.dart';
import 'package:yingsui/features/player/presentation/widgets/player_episode_strip.dart';

void main() {
  LibraryEpisodeItem episode(int n) => LibraryEpisodeItem(
    id: 'ep$n',
    numberStr: n.toString().padLeft(2, '0'),
    title: '第 $n 集',
    durationMinutes: 20,
    hasChineseSubtitles: true,
    hasEnglishSubtitles: true,
    completed: false,
    progressPercent: 0,
    coverImage: '',
    enSubtitleAsset: '',
  );

  Widget wrap() => MaterialApp(
    home: Scaffold(
      // Center 让组件按内容高度布局，而不是被父级撑满。
      body: Center(
        child: SizedBox(
          width: 700,
          child: PlayerEpisodeStrip(
            episodes: <LibraryEpisodeItem>[episode(1), episode(2), episode(3)],
            activeEpisodeId: 'ep1',
            onOpenEpisode: (_) {},
          ),
        ),
      ),
    ),
  );

  testWidgets('默认收起：只占一行，明显小于展开时', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final double collapsedHeight = tester
        .getSize(find.byType(PlayerEpisodeStrip))
        .height;

    // 收起时应只剩标题行的高度。
    expect(collapsedHeight, lessThan(60), reason: '收起后不应超过 60px');
    expect(find.textContaining('共 3 集'), findsOneWidget);

    // 展开后出现剧集卡片，高度显著增加。
    await tester.tap(find.byTooltip('展开课程目录'));
    await tester.pumpAndSettle();

    final double expandedHeight = tester
        .getSize(find.byType(PlayerEpisodeStrip))
        .height;
    expect(
      expandedHeight,
      greaterThan(collapsedHeight + 60),
      reason: '展开后应出现剧集列表并明显变高',
    );
    expect(find.text('第 1 集'), findsWidgets);

    // 可再次收起。
    await tester.tap(find.byTooltip('收起课程目录'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(PlayerEpisodeStrip)).height,
      lessThan(60),
    );
  });
}
