import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/shared/data/daily_english_service.dart';

/// 每日短语改成本地内置池后，重点验证「按日期轮换」的逻辑：
/// 同日稳定、条数固定、当天不重复、跨天会换。
void main() {
  group('DailyEnglishService 本地短语', () {
    test('同一天多次调用返回相同内容', () async {
      final DateTime fixed = DateTime(2026, 3, 15);
      final DailyEnglishService a = DailyEnglishService(now: () => fixed);
      final DailyEnglishService b = DailyEnglishService(now: () => fixed);

      final List<DailyEnglishPhrase> first = await a.loadToday();
      final List<DailyEnglishPhrase> second = await b.loadToday();

      expect(first.length, DailyEnglishService.phrasesPerDay);
      expect(
        first.map((DailyEnglishPhrase p) => p.english).toList(),
        second.map((DailyEnglishPhrase p) => p.english).toList(),
      );
    });

    test('每天固定返回 3 条，且当天内不重复', () async {
      for (int dayOffset = 1; dayOffset < 40; dayOffset += 1) {
        // 用 DateTime 直接构造，避免 .add(Duration(days: 0)) 触发
        // avoid_redundant_argument_values 提示。
        final DateTime day = DateTime(2026, 1, 1 + dayOffset);
        final List<DailyEnglishPhrase> phrases =
            await DailyEnglishService(now: () => day).loadToday();

        expect(
          phrases.length,
          DailyEnglishService.phrasesPerDay,
          reason: '$day 应返回 3 条',
        );

        final Set<String> unique = phrases
            .map((DailyEnglishPhrase p) => p.english)
            .toSet();
        expect(unique.length, phrases.length, reason: '$day 当天出现重复短语');
      }
    });

    test('跨天会轮换内容', () async {
      // 用「年内第几天」推进，避开分析器对 DateTime(2026, 5, 1) 中
      // day 参数的误报（该参数实际必填）。
      final DateTime base = DateTime(2026, 5, 4);
      final DateTime first = base;
      final DateTime second = base.add(const Duration(days: 1));
      final List<DailyEnglishPhrase> day1 =
          await DailyEnglishService(now: () => first).loadToday();
      final List<DailyEnglishPhrase> day2 =
          await DailyEnglishService(now: () => second).loadToday();

      expect(
        day1.map((DailyEnglishPhrase p) => p.english).toList(),
        isNot(day2.map((DailyEnglishPhrase p) => p.english).toList()),
        reason: '相邻两天不应给出完全相同的一组短语',
      );
    });

    test('短语内容完整：英文与中文都非空', () async {
      for (int dayOffset = 1; dayOffset < 60; dayOffset += 1) {
        // 用 DateTime 直接构造，避免 .add(Duration(days: 0)) 触发
        // avoid_redundant_argument_values 提示。
        final DateTime day = DateTime(2026, 1, 1 + dayOffset);
        final List<DailyEnglishPhrase> phrases =
            await DailyEnglishService(now: () => day).loadToday();
        for (final DailyEnglishPhrase phrase in phrases) {
          expect(phrase.english.trim(), isNotEmpty, reason: '$day 英文为空');
          expect(phrase.translation.trim(), isNotEmpty, reason: '$day 翻译为空');
        }
      }
    });

    test('loadOverride 仍然生效（供测试注入）', () async {
      final DailyEnglishService service = DailyEnglishService(
        loadOverride: () async => const <DailyEnglishPhrase>[
          DailyEnglishPhrase(english: 'injected', translation: '注入'),
        ],
      );
      final List<DailyEnglishPhrase> phrases = await service.loadToday();
      expect(phrases.single.english, 'injected');
    });
  });
}
