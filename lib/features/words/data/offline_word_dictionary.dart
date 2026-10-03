import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _dictionaryAsset = 'assets/dictionary/ecdict_core.json';

final Provider<OfflineWordDictionary> offlineWordDictionaryProvider =
    Provider<OfflineWordDictionary>((Ref ref) => OfflineWordDictionary());

class OfflineWordDefinition {
  const OfflineWordDefinition({
    required this.translation,
    required this.phonetic,
    required this.partOfSpeech,
  });

  final String translation;
  final String phonetic;
  final String partOfSpeech;
}

/// ECDICT 的释义里用**字面反斜杠 + n**（`\n`）分隔不同义项，
/// 而不是真正的换行符。直接显示会看到「…\n[计] …」这样的字符，
/// 用户反馈过「释义里出现 \n」。这里还原为真实换行，并把其余位置
/// 连续空白（含全角空格）收敛，避免排版出现空洞。
/// 供测试调用的包装（保持内部函数私有）。
String normalizeDefinitionForTest(String raw) => _normalizeTranslation(raw);

String _normalizeTranslation(String raw) {
  return raw
      .replaceAll(r'\n', '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .trim();
}

class OfflineWordDictionary {
  Future<Map<String, OfflineWordDefinition>>? _entriesFuture;

  Future<OfflineWordDefinition?> lookup(String rawWord) async {
    final String word = rawWord.trim().toLowerCase().replaceAll('’', "'");
    if (word.isEmpty) return null;
    return (await (_entriesFuture ??= _load()))
        .cast<String, OfflineWordDefinition>()[word];
  }

  Future<Map<String, OfflineWordDefinition>> _load() async {
    final Map<String, dynamic> decoded =
        jsonDecode(await rootBundle.loadString(_dictionaryAsset))
            as Map<String, dynamic>;
    final Map<String, dynamic> rawEntries =
        decoded['entries'] as Map<String, dynamic>;
    return rawEntries.map((String word, dynamic value) {
      final List<dynamic> fields = value as List<dynamic>;
      return MapEntry<String, OfflineWordDefinition>(
        word,
        OfflineWordDefinition(
          translation: _normalizeTranslation(fields[0] as String),
          phonetic: fields[1] as String,
          partOfSpeech: fields[2] as String,
        ),
      );
    });
  }
}
