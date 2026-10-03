/// 手机窄屏下的课程概览卡与剧集条目。
///
/// 为什么单独写：用户实测安卓机（1080×2400 @3x → 360×800 逻辑像素）
/// 反馈「UI 全部挤在一起」。真实原因不是溢出异常，而是**文字被压成竖排**：
///   · 课程概览卡的统计区把三个 _StatBlock 并排塞进 ~140dp，
///     每块仅约 38dp 宽，「词汇储备」逐字换行；
///   · 剧集编号是导入 ID（如 1791012859374，13 位），
///     固定 24px 字号塞进 64×64 方框后溢出。
/// 这两类问题都不会抛异常，`takeException()` 抓不到，
/// 因此必须直接断言**换行行数**与**无溢出**。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/library/presentation/library_mock_data.dart';
import 'package:yingsui/features/library/presentation/widgets/course_overview_card.dart';
import 'package:yingsui/features/library/presentation/widgets/episode_list_item.dart';

/// 用户遇到的真实数据形态：微信导出的超长编号。
const String _longNumber = '1791012859374';

LibraryCourseData _course() {
  return const LibraryCourseData(
    id: 'course-1',
    title: 'WeiXin',
    description: '日常口语精听，来自本机导入的剧集。',
    level: '自定义',
    category: '自选课程',
    sourceLabel: '本地资源',
    coverImage: '',
    lastStudiedStr: '刚刚',
    totalEpisodes: 1,
    completedEpisodes: 0,
    progressPercent: 0,
    totalWords: 0,
    rating: 4.7,
    episodes: <LibraryEpisodeItem>[],
  );
}

LibraryEpisodeItem _episode() {
  return const LibraryEpisodeItem(
    id: 'ep-1',
    numberStr: _longNumber,
    title: '第 $_longNumber 集',
    durationMinutes: 30,
    coverImage: '',
    hasChineseSubtitles: false,
    hasEnglishSubtitles: true,
    completed: false,
    progressPercent: 0,
  );
}

/// 把被测组件放进与真机一致的窄屏里。
Future<void> _pumpAtPhone(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    ),
  );
  // 固定次数 pump：部分子组件有持续动画，pumpAndSettle 不会返回。
  for (int i = 0; i < 4; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 统计某个 Text 实际占用的高度对应几行。
double _renderedHeight(WidgetTester tester, String text) {
  final Finder finder = find.text(text);
  expect(finder, findsOneWidget, reason: '应能找到文本「$text」');
  final RenderBox box = tester.renderObject<RenderBox>(finder);
  return box.size.height;
}

void main() {
  group('课程概览卡在 360dp 手机上', () {
    testWidgets('不出现布局溢出', (WidgetTester tester) async {
      await _pumpAtPhone(
        tester,
        CourseOverviewCard(
          course: _course(),
          activeEpisode: _episode(),
          onPlayTap: () {},
        ),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '窄屏渲染课程概览卡不应抛布局异常',
      );
    });

    testWidgets('统计项标签不逐字竖排', (WidgetTester tester) async {
      await _pumpAtPhone(
        tester,
        CourseOverviewCard(
          course: _course(),
          activeEpisode: _episode(),
          onPlayTap: () {},
        ),
      );

      // 「词汇储备」在竖排时高度会暴涨到单字×4 行。
      // 正常横排一行的高度应在 40 逻辑像素以内。
      final double labelHeight = _renderedHeight(tester, '词汇储备');
      expect(
        labelHeight,
        lessThan(40),
        reason: '「词汇储备」高度 $labelHeight 过大，说明又被压成竖排了。',
      );
    });

    testWidgets('进度百分比完整可见', (WidgetTester tester) async {
      await _pumpAtPhone(
        tester,
        CourseOverviewCard(
          course: _course(),
          activeEpisode: _episode(),
          onPlayTap: () {},
        ),
      );
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('学习进度'), findsOneWidget);
    });
  });

  group('剧集条目在 360dp 手机上', () {
    testWidgets('超长编号不溢出也不竖排', (WidgetTester tester) async {
      await _pumpAtPhone(
        tester,
        EpisodeListItem(
          item: _episode(),
          selected: false,
          onTap: () {},
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: '13 位编号不应导致溢出异常',
      );

      // 编号方框是 64×64；竖排时会远超这个高度。
      final double numberHeight = _renderedHeight(tester, _longNumber);
      expect(
        numberHeight,
        lessThan(40),
        reason: '编号高度 $numberHeight 过大，长编号被压成竖排了。',
      );
    });

    testWidgets('无中文字幕提示不被压成竖排', (WidgetTester tester) async {
      await _pumpAtPhone(
        tester,
        EpisodeListItem(
          item: _episode(),
          selected: false,
          onTap: () {},
        ),
      );
      final double chipHeight = _renderedHeight(tester, '无中文字幕');
      expect(
        chipHeight,
        lessThan(40),
        reason: '字幕状态标签高度 $chipHeight 过大，右侧控件挤压了内容区',
      );
    });
  });
}
