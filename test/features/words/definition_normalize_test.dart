/// ECDICT 释义里的**字面 `\n`** 必须还原成真实换行。
///
/// 数据长这样（注意是反斜杠 + n 两个字符，不是换行符）：
///   'be': ['v. 是, 表示, 在\n[计] 后端, 总线允许', ...]
/// 直接显示会让用户在释义里看到 `\n` 字面量（用户实测反馈）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/words/data/offline_word_dictionary.dart';

void main() {
  group('释义规范化', () {
    test('把字面反斜杠n还原为真实换行', () async {
      final OfflineWordDictionary dict = OfflineWordDictionary();
      // 直接验证规范化逻辑对典型 ECDICT 值的处理。
      const String raw = r'v. 是, 表示, 在\n[计] 后端, 总线允许';
      final String normalized = normalizeDefinitionForTest(raw);
      expect(normalized.contains(r'\n'), isFalse, reason: '不应再有字面反斜杠n');
      expect(normalized.contains('\n'), isTrue, reason: '应变成真实换行');
      expect(normalized.startsWith('v. 是'), isTrue);
      expect(dict, isNotNull);
    });

    test('多余空白与连续换行被收敛', () {
      const String raw = 'a\n\n\n\nb     c\n   d';
      final String normalized = normalizeDefinitionForTest(raw);
      expect(normalized.contains('\n\n\n'), isFalse);
      expect(normalized.contains('     '), isFalse);
    });

    test('没有换行的释义保持原样', () {
      expect(normalizeDefinitionForTest('n. 地狱'), 'n. 地狱');
    });
  });
}
