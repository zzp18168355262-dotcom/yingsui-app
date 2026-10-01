import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

const String _dailyEnglishStorageKey = 'daily_english_v1';

final Provider<DailyEnglishService> dailyEnglishServiceProvider =
    Provider<DailyEnglishService>((Ref ref) => DailyEnglishService());

class DailyEnglishPhrase {
  const DailyEnglishPhrase({required this.english, required this.translation});

  factory DailyEnglishPhrase.fromJson(Map<String, dynamic> json) {
    return DailyEnglishPhrase(
      english: json['english'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
    );
  }

  final String english;
  final String translation;

  Map<String, String> toJson() => <String, String>{
    'english': english,
    'translation': translation,
  };
}

/// 每日短语。
///
/// 内容完全来自应用内置的精选短语池，**不请求任何网络服务**。
///
/// 为什么不用第三方接口：
/// 上游实现依赖 adviceslip.com（随机英文格言，并非英语学习内容）与
/// mymemory.translated.net（免费机翻，有配额与可用性风险）。
/// 对付费产品而言，这两个依赖会带来三类问题：
///   1. 服务不可用时功能直接失效，且无法自查
///   2. 内容不可控——名言警句不适合作为口语跟读素材
///   3. 把内容发给第三方，涉及隐私与合规
/// 内置短语池离线可用、瞬时返回、内容可审校，明显更适合本产品。
class DailyEnglishService {
  DailyEnglishService({DateTime Function()? now, this.loadOverride})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// 测试注入用。
  final Future<List<DailyEnglishPhrase>> Function()? loadOverride;

  /// 每天展示的短语条数。
  static const int phrasesPerDay = 3;

  Future<List<DailyEnglishPhrase>> loadToday() async {
    if (loadOverride != null) return loadOverride!();

    final String today = _dayKey(_now());
    final List<DailyEnglishPhrase>? cached = _readCache(today);
    if (cached != null) return cached;

    final List<DailyEnglishPhrase> phrases = _phrasesForDay(_now());
    _writeCache(today, phrases);
    return phrases;
  }

  /// 按日期确定性地挑选短语：同一天始终得到同一组，跨天自动轮换。
  /// 用「年内第几天」做起点并步进，避免连续两天出现重复内容。
  static List<DailyEnglishPhrase> _phrasesForDay(DateTime date) {
    final int dayOfYear = date.difference(DateTime(date.year)).inDays;
    final int total = _phrasePool.length;
    return List<DailyEnglishPhrase>.generate(phrasesPerDay, (int index) {
      // 步长与总数互质，保证 3 条不重复且能遍历整个池子。
      final int slot = (dayOfYear * phrasesPerDay + index * 5) % total;
      return _phrasePool[slot];
    });
  }

  List<DailyEnglishPhrase>? _readCache(String today) {
    if (!Hive.isBoxOpen('prefs')) return null;
    try {
      final Object? decoded = jsonDecode(
        Hive.box<String>('prefs').get(_dailyEnglishStorageKey) ?? '',
      );
      if (decoded is! Map<Object?, Object?> ||
          decoded['day'] != today ||
          decoded['phrases'] is! List) {
        return null;
      }
      final List<Object?> items = List<Object?>.from(
        decoded['phrases']! as List<Object?>,
      );
      final List<DailyEnglishPhrase> phrases = items
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) =>
                DailyEnglishPhrase.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((DailyEnglishPhrase phrase) => phrase.english.isNotEmpty)
          .toList(growable: false);
      return phrases.length == phrasesPerDay ? phrases : null;
    } catch (_) {
      return null;
    }
  }

  void _writeCache(String today, List<DailyEnglishPhrase> phrases) {
    if (!Hive.isBoxOpen('prefs')) return;
    Hive.box<String>('prefs').put(
      _dailyEnglishStorageKey,
      jsonEncode(<String, Object>{
        'day': today,
        'phrases': phrases
            .map((DailyEnglishPhrase item) => item.toJson())
            .toList(),
      }),
    );
  }
}

String _dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// 内置短语池。
///
/// 选取标准：日常口语高频、句子短、适合影子跟读（有连读与语调起伏）、
/// 场景贴合职场与生活（与应用的素材分类一致）。
const List<DailyEnglishPhrase> _phrasePool = <DailyEnglishPhrase>[
  // ── 职场沟通 ──
  DailyEnglishPhrase(
    english: "Let's circle back on this tomorrow.",
    translation: '我们明天再回头讨论这件事。',
  ),
  DailyEnglishPhrase(
    english: 'Could you walk me through it one more time?',
    translation: '你能再带我过一遍吗？',
  ),
  DailyEnglishPhrase(
    english: "I'll keep you posted as things move forward.",
    translation: '有进展我会随时同步给你。',
  ),
  DailyEnglishPhrase(
    english: 'Let me make sure I understand what you mean.',
    translation: '让我确认一下我理解得对不对。',
  ),
  DailyEnglishPhrase(
    english: 'We might need to push the deadline back a bit.',
    translation: '我们可能得把截止日期往后推一点。',
  ),
  DailyEnglishPhrase(
    english: 'That sounds like a solid plan to me.',
    translation: '我觉得这个方案很靠谱。',
  ),
  DailyEnglishPhrase(
    english: 'Can we set up a quick call to sort this out?',
    translation: '我们能约个短会把这个理清楚吗？',
  ),
  DailyEnglishPhrase(
    english: "I'd rather sleep on it before deciding.",
    translation: '我想先考虑一晚再决定。',
  ),

  // ── 日常交流 ──
  DailyEnglishPhrase(
    english: 'I was just about to head out for lunch.',
    translation: '我正打算出去吃午饭。',
  ),
  DailyEnglishPhrase(
    english: 'How did your weekend end up going?',
    translation: '你周末过得怎么样？',
  ),
  DailyEnglishPhrase(
    english: "It's been one of those weeks, honestly.",
    translation: '说实话，这周真是够呛。',
  ),
  DailyEnglishPhrase(
    english: "I couldn't have said it better myself.",
    translation: '我自己也说不出来更好的了。',
  ),
  DailyEnglishPhrase(
    english: 'Give me a second, I just need to grab my coat.',
    translation: '等我一下，我拿件外套。',
  ),
  DailyEnglishPhrase(
    english: 'That place is worth the wait, trust me.',
    translation: '相信我，那家店值得排队。',
  ),
  DailyEnglishPhrase(
    english: "I'm not really in the mood for anything heavy.",
    translation: '我不太想吃太油腻的东西。',
  ),
  DailyEnglishPhrase(
    english: 'Let me know if you need a hand with that.',
    translation: '需要帮忙的话跟我说。',
  ),

  // ── 表达观点 ──
  DailyEnglishPhrase(
    english: "I see where you're coming from, but I disagree.",
    translation: '我理解你的出发点，但我不同意。',
  ),
  DailyEnglishPhrase(
    english: 'To be honest, I have mixed feelings about it.',
    translation: '老实说，我对这件事感觉挺复杂。',
  ),
  DailyEnglishPhrase(
    english: "That's not quite what I had in mind.",
    translation: '这和我原本想的有点不一样。',
  ),
  DailyEnglishPhrase(
    english: 'The way I see it, we have two options here.',
    translation: '在我看来，我们有两条路可走。',
  ),
  DailyEnglishPhrase(
    english: "I'd say it's worth giving it a shot.",
    translation: '我觉得值得试一试。',
  ),
  DailyEnglishPhrase(
    english: 'Correct me if I am wrong, but that changed last year.',
    translation: '如果我记错了请纠正，但那是去年改的。',
  ),

  // ── 学习与成长 ──
  DailyEnglishPhrase(
    english: 'Little by little, it starts to feel natural.',
    translation: '一点一点地，它就开始变得自然了。',
  ),
  DailyEnglishPhrase(
    english: 'Say it out loud, even when it sounds off.',
    translation: '大声说出来，哪怕听着别扭。',
  ),
  DailyEnglishPhrase(
    english: 'The more you repeat it, the smoother it gets.',
    translation: '重复得越多，就越顺口。',
  ),
  DailyEnglishPhrase(
    english: "Don't worry about mistakes, just keep going.",
    translation: '别怕出错，继续往下说就行。',
  ),
];
