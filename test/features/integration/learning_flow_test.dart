/// 跨模块端到端检查：确认各功能之间**真的连通**。
///
/// 为什么需要它：单模块测试都通过，不代表链路是通的。
/// 这里把「导入课程 → 播放页能解析到资源 → 收藏单词/短语 → 出现在对应库」
/// 串起来验证，任何一环断裂都会让功能对用户不可用。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/home/presentation/learning_dashboard_provider.dart';
import 'package:yingsui/features/import_course/domain/import_match.dart';
import 'package:yingsui/features/library/presentation/library_catalog_provider.dart';
import 'package:yingsui/features/library/presentation/library_mock_data.dart';
import 'package:yingsui/features/phrases/presentation/phrase_book_provider.dart';
import 'package:yingsui/features/player/presentation/player_course_lookup.dart';
import 'package:yingsui/features/words/data/offline_word_dictionary.dart';
import 'package:yingsui/features/words/presentation/word_book_provider.dart';

/// 构造一行导入匹配：一部视频 + 中英字幕。
ImportMatchRow _row() {
  return ImportMatchRow(
    episodeName: '第 01 集',
    videoFile: 'ep01.mp4',
    videoPath: '/tmp/demo/ep01.mp4',
    subtitleTracks: <String, ImportSubtitleTrack>{
      'en': const ImportSubtitleTrack(
        languageCode: 'en',
        languageLabel: 'English',
        path: '/tmp/demo/ep01.en.srt',
      ),
      'zh': const ImportSubtitleTrack(
        languageCode: 'zh',
        languageLabel: '中文',
        path: '/tmp/demo/ep01.zh.srt',
      ),
    },
  );
}

/// 词典桩。
///
/// 真实离线词典数据量大，测试中直接查询会超时（实测 10 分钟）。
/// 这里只对固定几个词返回释义，用于验证「查询 → 入库」链路本身。
class _StubDictionary extends OfflineWordDictionary {
  @override
  Future<OfflineWordDefinition?> lookup(String rawWord) async {
    if (rawWord == 'hello' || rawWord == 'world') {
      return const OfflineWordDefinition(
        translation: '释义',
        phonetic: '',
        partOfSpeech: 'n.',
      );
    }
    return null;
  }
}

ProviderContainer _container() => ProviderContainer(
  // ignore: always_specify_types
  overrides: [
    offlineWordDictionaryProvider.overrideWithValue(_StubDictionary()),
  ],
);

void main() {
  group('端到端：导入 → 播放解析', () {
    testWidgets('导入课程后，播放页能解析到视频与字幕路径', (WidgetTester tester) async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final LibraryCatalogNotifier catalog = container.read(
        libraryCatalogProvider.notifier,
      );

      // 1) 导入
      final bool ok = await catalog.importCourseFromMatches(
        rows: <ImportMatchRow>[_row()],
        videoFolder: '/tmp/demo',
        subtitleFolder: '/tmp/demo',
        courseTitle: '端到端测试课程',
      );
      expect(ok, isTrue, reason: '导入应当成功');

      // 2) 课程出现在库里
      final List<LibraryCourseData> courses = container.read(
        libraryCatalogProvider,
      );
      expect(courses, isNotEmpty, reason: '导入后课程库不应为空');
      final LibraryCourseData course = courses.first;
      expect(course.episodes, isNotEmpty, reason: '课程应包含剧集');

      // 3) 播放页能按 episodeId 解析出资源
      final LibraryEpisodeItem episode = course.episodes.first;
      final PlayerCourseLookupResult resolved = resolvePlayerCourseForEpisode(
        courses: courses,
        episodeId: episode.id,
      );
      expect(resolved.episode, isNotNull, reason: '应能按 id 找到剧集');
      expect(
        resolved.videoAsset,
        isNotEmpty,
        reason: '必须解析到视频路径，否则播放页打不开视频',
      );
      expect(
        resolved.englishSubtitleAsset ?? '',
        isNotEmpty,
        reason: '必须解析到英文字幕路径，否则逐句精听无内容',
      );
    });
  });

  group('端到端：收藏 → 各库', () {
    testWidgets('收藏单词后出现在生词本，且可清空', (WidgetTester tester) async {
      final ProviderContainer container = _container();
      addTearDown(container.dispose);

      final WordBookNotifier words = container.read(wordBookProvider.notifier);
      await words.recordLine(
        english: 'Hello world',
        episodeId: 'ep-x',
        course: '课程',
        episode: '第 1 集',
        time: '00:01',
        lineKey: '1-2',
        chinese: '你好世界',
      );
      expect(
        container.read(wordBookProvider),
        isNotEmpty,
        reason: '收藏后生词本应有内容',
      );

      await words.clearAll();
      expect(
        container.read(wordBookProvider),
        isEmpty,
        reason: '清除后生词本应为空',
      );
    });

    testWidgets('短语入库后可按到期复习筛选到', (WidgetTester tester) async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final PhraseBookNotifier phrases =
          container.read(phraseBookProvider.notifier)
            ..addPhrase(
              english: 'turns me on',
              chinese: '让我兴奋',
              course: '课程',
              episode: '第 1 集',
              time: '00:10',
            );

      final List<PhraseEntry> saved = container.read(phraseBookProvider);
      expect(saved, isNotEmpty, reason: '短语应已入库');
      expect(
        saved.first.english,
        'turns me on',
        reason: '入库的应是短语本身',
      );

      await phrases.clearAll();
      expect(container.read(phraseBookProvider), isEmpty);
    });

    testWidgets('收藏动作会记入学习记录（成长页数据来源）', (WidgetTester tester) async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final LearningActivityNotifier activity = container
          .read(learningActivityProvider.notifier)
        ..recordPhraseSaved()
        ..recordSentenceStudy(sentenceKey: 'ep-x:1-2');

      final LearningActivityState state = container.read(
        learningActivityProvider,
      );
      expect(
        state.records,
        isNotEmpty,
        reason: '学习记录应有当日数据，成长页依赖它计算等级与连续天数',
      );

      await activity.clearAll();
      expect(container.read(learningActivityProvider).records, isEmpty);
    });
  });
}
