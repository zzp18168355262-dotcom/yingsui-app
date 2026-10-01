import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/settings_provider.dart';
import '../domain/word_lookup_entry.dart';

typedef WordLookupRemoteLookup =
    Future<WordLookupEntry> Function({
      required String rawWord,
      String? contextSentence,
      required LearningSettingsState settings,
    });

typedef WordLookupHttpRequest =
    Future<Response<dynamic>> Function({
      required BaseOptions options,
      required String method,
      required String path,
      Map<String, dynamic>? queryParameters,
      Object? data,
    });

final Provider<WordLookupService> wordLookupServiceProvider =
    Provider<WordLookupService>((Ref ref) => const WordLookupService());

class WordLookupService {
  const WordLookupService({
    this.remoteLookupOverride,
    this.httpRequestOverride,
  });

  final WordLookupRemoteLookup? remoteLookupOverride;
  final WordLookupHttpRequest? httpRequestOverride;

  /// 网络超时。
  ///
  /// Dio 默认**不设超时**，单个请求可能永久挂起。字幕翻译会发起数百次请求，
  /// 只要少数几次挂住，连接与 socket 就会持续堆积，
  /// 用户看到的现象就是「一直卡在生成中」。
  /// 因此所有外发请求都必须显式带上超时。
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _receiveTimeout = Duration(seconds: 30);
  static const Duration _sendTimeout = Duration(seconds: 15);

  Future<WordLookupEntry> lookupWord({
    required String rawWord,
    String? contextSentence,
    required LearningSettingsState settings,
  }) async {
    final String normalizedWord = _normalizeWord(rawWord);
    if (!_canUseRemoteProvider(settings)) {
      return _buildUnavailableEntry(
        rawWord: normalizedWord,
        messageCn: '请先在设置中配置可用的翻译 API。',
        messageEn: 'Set up a translation API in Settings first.',
      );
    }
    try {
      return remoteLookupOverride != null
          ? await remoteLookupOverride!(
              rawWord: normalizedWord,
              contextSentence: contextSentence,
              settings: settings,
            )
          : await _lookupRemote(
              rawWord: normalizedWord,
              contextSentence: contextSentence,
              settings: settings,
            );
    } catch (_) {
      return _buildUnavailableEntry(
        rawWord: normalizedWord,
        messageCn: '翻译服务当前不可用，请检查 API 配置后重试。',
        messageEn:
            'Translation API is unavailable. Check your API settings and try again.',
      );
    }
  }

  /// 翻译整句。
  ///
  /// 返回 null 表示「未能翻译」（不是异常）。调用方若需要知道原因
  /// （例如把原因展示给用户），可传入 [onError]。
  ///
  /// 之所以用 onError 而不是直接抛异常：本方法有多个调用方（查词、全文阅读、
  /// 字幕生成等），它们大多只需要「拿到译文或没有」，不应被迫处理异常。
  /// 字幕生成这类需要诊断的场景再通过 onError 取回细节。
  Future<String?> translateSentence({
    required String sentence,
    required LearningSettingsState settings,
    ValueChanged<Object>? onError,
  }) async {
    final String text = sentence.trim();
    if (text.isEmpty || !_canUseRemoteProvider(settings)) return null;
    try {
      if (_isDirectProvider(settings.translationProvider)) {
        return (await _lookupDirectProvider(
          rawWord: text,
          settings: settings,
        )).definitionCn;
      }
      final Response<dynamic> response = await _sendRequest(
            options: BaseOptions(
              baseUrl: settings.translationBaseUrl,
              headers: <String, String>{
                'Authorization': 'Bearer ${settings.translationApiKey}',
                'Content-Type': 'application/json',
              },
            ),
            method: 'POST',
            path: '/chat/completions',
            data: <String, dynamic>{
              'model': settings.translationModel,
              'temperature': 0.1,
              'messages': <Map<String, String>>[
                <String, String>{
                  'role': 'system',
                  'content':
                      'Translate the English sentence into concise Simplified Chinese. Return only the translation.',
                },
                <String, String>{'role': 'user', 'content': text},
              ],
            },
          );
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      final List<dynamic> choices = data['choices'] as List<dynamic>;
      final Map<String, dynamic> first = choices.first as Map<String, dynamic>;
      final Map<String, dynamic> message =
          first['message'] as Map<String, dynamic>;
      final String translation = (message['content'] as String? ?? '').trim();
      if (translation.isEmpty) {
        onError?.call(
          StateError('翻译接口返回了空内容（响应片段：${_snippet(data)}）'),
        );
        return null;
      }
      return translation;
    } catch (error) {
      onError?.call(error);
      return null;
    }
  }

  /// 批量翻译多句（仅适用于 AI 类接口）。
  ///
  /// 为什么需要它：逐句翻译对长字幕意味着数百次 HTTP 请求，
  /// 又慢又容易触发限流，还会因个别请求挂起而拖住整个任务。
  /// 打包成一次请求后，500 句大约只需 25 次调用。
  ///
  /// 返回与入参等长的列表；某句未翻译出来对应位置为 null。
  /// 只要整体请求失败或无法解析，就整体返回 null，由调用方回退到逐句模式。
  Future<List<String?>?> translateSentences({
    required List<String> sentences,
    required LearningSettingsState settings,
    ValueChanged<Object>? onError,
  }) async {
    if (sentences.isEmpty) return const <String?>[];
    // 直连类服务（阿里云/百度/Google）单次只翻一句，不适用批量。
    if (_isDirectProvider(settings.translationProvider)) return null;
    if (!_canUseRemoteProvider(settings)) return null;

    final String numbered = <String>[
      for (int i = 0; i < sentences.length; i += 1)
        '${i + 1}. ${sentences[i]}',
    ].join('\n');

    try {
      final Response<dynamic> response = await _sendRequest(
            options: BaseOptions(
              baseUrl: settings.translationBaseUrl,
              headers: <String, String>{
                'Authorization': 'Bearer ${settings.translationApiKey}',
                'Content-Type': 'application/json',
              },
            ),
            method: 'POST',
            path: '/chat/completions',
            data: <String, dynamic>{
              'model': settings.translationModel,
              'temperature': 0.1,
              'messages': <Map<String, String>>[
                <String, String>{
                  'role': 'system',
                  'content':
                      'You translate English subtitle lines into concise Simplified Chinese. '
                      'The user sends numbered lines. Reply with exactly the same numbering, '
                      'one translation per line, in the form "1. 译文". '
                      'Do not merge lines, do not add notes, do not output the English.',
                },
                <String, String>{'role': 'user', 'content': numbered},
              ],
            },
          );
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      final List<dynamic> choices = data['choices'] as List<dynamic>;
      final Map<String, dynamic> first = choices.first as Map<String, dynamic>;
      final Map<String, dynamic> message =
          first['message'] as Map<String, dynamic>;
      final String content = (message['content'] as String? ?? '').trim();
      if (content.isEmpty) {
        onError?.call(
          StateError('批量翻译返回空内容（响应片段：${_snippet(data)}）'),
        );
        return null;
      }
      return _parseNumberedTranslations(content, sentences.length);
    } catch (error) {
      onError?.call(error);
      return null;
    }
  }

  /// 解析形如「1. 译文」的编号结果。
  ///
  /// 容错处理：模型有时会写成「1) 译文」「1、译文」或省略编号，
  /// 因此优先按编号匹配，匹配不到再按行顺序兜底；
  /// 行数明显不足时返回 null，让调用方回退到逐句翻译（宁可慢，不能错位）。
  static List<String?>? _parseNumberedTranslations(
    String content,
    int expected,
  ) {
    final List<String> rawLines = content
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
    if (rawLines.isEmpty) return null;

    final List<String?> result = List<String?>.filled(expected, null);
    final RegExp numbered = RegExp(r'^(\d+)\s*[.、)\]:：]\s*(.+)$');
    int matched = 0;
    for (final String line in rawLines) {
      final RegExpMatch? match = numbered.firstMatch(line);
      if (match == null) continue;
      final int index = int.tryParse(match.group(1) ?? '') ?? -1;
      final String text = (match.group(2) ?? '').trim();
      if (index < 1 || index > expected || text.isEmpty) continue;
      result[index - 1] = text;
      matched += 1;
    }

    if (matched == expected) return result;

    // 没有编号（或编号不全）时按顺序兜底，但要求行数与句数一致，
    // 否则会张冠李戴，不如回退逐句。
    if (matched == 0 && rawLines.length == expected) {
      return rawLines.cast<String?>().toList(growable: false);
    }
    return null;
  }

  /// 截断响应内容，避免把超长响应塞进错误提示。
  static String _snippet(Object? value) {
    final String text = value?.toString() ?? '';
    return text.length <= 200 ? text : '${text.substring(0, 200)}…';
  }

  Future<WordLookupEntry> _lookupRemote({
    required String rawWord,
    String? contextSentence,
    required LearningSettingsState settings,
  }) async {
    if (_isDirectProvider(settings.translationProvider)) {
      return _lookupDirectProvider(
        rawWord: rawWord,
        contextSentence: contextSentence,
        settings: settings,
      );
    }

    final Dio dio = Dio(
      BaseOptions(
        baseUrl: settings.translationBaseUrl,
        headers: <String, String>{
          'Authorization': 'Bearer ${settings.translationApiKey}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        // 同 translateSentence：必须显式设超时，否则请求可能永久挂起。
        connectTimeout: _connectTimeout,
        receiveTimeout: _receiveTimeout,
        sendTimeout: _sendTimeout,
      ),
    );
    final Response<dynamic> response = await dio.post<dynamic>(
      '/chat/completions',
      data: <String, dynamic>{
        'model': settings.translationModel,
        'temperature': 0.2,
        'response_format': const <String, String>{'type': 'json_object'},
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'system',
            'content':
                'You are a concise English word lookup assistant. Return strict JSON with keys '
                'word, phonetic, type, definitionEn, usageEn, exampleSentenceEn, definitionCn. '
                'definitionEn must explain the meaning in simple English. '
                'usageEn must explain when or where the word is commonly used in English. '
                'exampleSentenceEn must be a new short sentence using the word naturally. '
                'Keep answers short and clear.',
          },
          <String, String>{
            'role': 'user',
            'content': contextSentence == null || contextSentence.trim().isEmpty
                ? 'Explain the English word "$rawWord".'
                : 'Explain the English word "$rawWord" in the sentence: "$contextSentence".',
          },
        ],
      },
    );

    final Map<String, dynamic> responseData =
        response.data as Map<String, dynamic>;
    final List<dynamic> choices = responseData['choices'] as List<dynamic>;
    final Map<String, dynamic> firstChoice =
        choices.first as Map<String, dynamic>;
    final Map<String, dynamic> message =
        firstChoice['message'] as Map<String, dynamic>;
    final String content = message['content'] as String;
    final Map<String, dynamic> decoded =
        jsonDecode(content) as Map<String, dynamic>;

    return WordLookupEntry(
      word: (decoded['word'] as String? ?? rawWord).trim(),
      phonetic: (decoded['phonetic'] as String? ?? '').trim(),
      type: (decoded['type'] as String? ?? '英文单词').trim(),
      definitionEn: (decoded['definitionEn'] as String? ?? '').trim(),
      usageEn: (decoded['usageEn'] as String? ?? '').trim(),
      exampleSentenceEn: (decoded['exampleSentenceEn'] as String? ?? '').trim(),
      definitionCn: (decoded['definitionCn'] as String? ?? '').trim(),
      sourceLabel: 'API',
    );
  }

  Future<WordLookupEntry> _lookupDirectProvider({
    required String rawWord,
    String? contextSentence,
    required LearningSettingsState settings,
  }) async {
    switch (settings.translationProvider) {
      case 'Google 翻译':
        return _lookupGoogleTranslate(
          rawWord: rawWord,
          contextSentence: contextSentence,
          settings: settings,
        );
      case '百度翻译':
        return _lookupBaiduTranslate(
          rawWord: rawWord,
          contextSentence: contextSentence,
          settings: settings,
        );
      case '阿里云翻译':
        return _lookupAliyunTranslate(
          rawWord: rawWord,
          contextSentence: contextSentence,
          settings: settings,
        );
      default:
        throw UnsupportedError(
          'Unsupported direct provider: ${settings.translationProvider}',
        );
    }
  }

  Future<WordLookupEntry> _lookupGoogleTranslate({
    required String rawWord,
    String? contextSentence,
    required LearningSettingsState settings,
  }) async {
    final Response<dynamic> response = await _sendRequest(
      options: BaseOptions(
        baseUrl: settings.translationBaseUrl,
        connectTimeout: _connectTimeout,
        receiveTimeout: _receiveTimeout,
        sendTimeout: _sendTimeout,
      ),
      method: 'POST',
      path: '/language/translate/v2',
      queryParameters: <String, dynamic>{
        'key': settings.translationApiKey,
        'q': rawWord,
        'source': 'en',
        'target': 'zh-CN',
        'format': 'text',
      },
    );
    final Map<String, dynamic> responseData =
        response.data as Map<String, dynamic>;
    final Map<String, dynamic> data =
        responseData['data'] as Map<String, dynamic>;
    final List<dynamic> translations = data['translations'] as List<dynamic>;
    final Map<String, dynamic> first =
        translations.first as Map<String, dynamic>;
    return _buildDirectLookupEntry(
      rawWord: rawWord,
      contextSentence: contextSentence,
      translatedText: (first['translatedText'] as String? ?? '').trim(),
      providerLabel: 'Google 翻译',
    );
  }

  Future<WordLookupEntry> _lookupBaiduTranslate({
    required String rawWord,
    String? contextSentence,
    required LearningSettingsState settings,
  }) async {
    final String salt = DateTime.now().microsecondsSinceEpoch.toString();
    final String sign = md5
        .convert(
          utf8.encode(
            '${settings.translationApiKey}$rawWord$salt${settings.translationApiSecret}',
          ),
        )
        .toString();
    final Response<dynamic> response = await _sendRequest(
      options: BaseOptions(
        baseUrl: settings.translationBaseUrl,
        connectTimeout: _connectTimeout,
        receiveTimeout: _receiveTimeout,
        sendTimeout: _sendTimeout,
      ),
      method: 'POST',
      path: '/api/trans/vip/translate',
      queryParameters: <String, dynamic>{
        'q': rawWord,
        'from': 'en',
        'to': 'zh',
        'appid': settings.translationApiKey,
        'salt': salt,
        'sign': sign,
      },
    );
    final Map<String, dynamic> responseData =
        response.data as Map<String, dynamic>;
    final List<dynamic> results = responseData['trans_result'] as List<dynamic>;
    final Map<String, dynamic> first = results.first as Map<String, dynamic>;
    return _buildDirectLookupEntry(
      rawWord: rawWord,
      contextSentence: contextSentence,
      translatedText: (first['dst'] as String? ?? '').trim(),
      providerLabel: '百度翻译',
    );
  }

  Future<WordLookupEntry> _lookupAliyunTranslate({
    required String rawWord,
    String? contextSentence,
    required LearningSettingsState settings,
  }) async {
    final Map<String, dynamic> params = <String, dynamic>{
      'Action': 'TranslateGeneral',
      'Version': '2018-10-12',
      'Format': 'JSON',
      'AccessKeyId': settings.translationApiKey,
      'SignatureMethod': 'HMAC-SHA1',
      'Timestamp': _buildAliyunTimestamp(),
      'SignatureVersion': '1.0',
      'SignatureNonce': DateTime.now().microsecondsSinceEpoch.toString(),
      'FormatType': 'text',
      'SourceLanguage': 'en',
      'TargetLanguage': 'zh',
      'SourceText': rawWord,
      'Scene': settings.translationModel.isEmpty
          ? 'general'
          : settings.translationModel,
    };
    params['Signature'] = _buildAliyunSignature(
      params: params,
      accessKeySecret: settings.translationApiSecret,
    );

    final Response<dynamic> response = await _sendRequest(
      options: BaseOptions(
        baseUrl: settings.translationBaseUrl,
        connectTimeout: _connectTimeout,
        receiveTimeout: _receiveTimeout,
        sendTimeout: _sendTimeout,
      ),
      method: 'GET',
      path: '/',
      queryParameters: params,
    );
    final Map<String, dynamic> responseData =
        response.data as Map<String, dynamic>;

    // 阿里云在配额用尽、欠费、签名错误等情况下不会返回 Data，
    // 而是返回 Code + Message。原先直接取 Data 会在这些情况下抛出
    // 难以理解的类型错误，且被上层 catch 吞掉，表现为「翻译突然全部失效」。
    // 这里显式识别并把服务端返回的原因抛出来，便于诊断与提示用户。
    final Object? dataField = responseData['Data'];
    if (dataField is! Map<String, dynamic>) {
      final String code = (responseData['Code'] as String? ?? '').trim();
      final String message = (responseData['Message'] as String? ?? '').trim();
      if (code.isNotEmpty || message.isNotEmpty) {
        throw StateError(
          '阿里云翻译返回错误${code.isEmpty ? '' : '（$code）'}'
          '${message.isEmpty ? '' : '：$message'}',
        );
      }
      throw StateError('阿里云翻译响应缺少 Data 字段：${_snippet(responseData)}');
    }
    final Map<String, dynamic> data = dataField;
    final String translated = (data['Translated'] as String? ?? '').trim();
    if (translated.isEmpty) {
      throw StateError('阿里云翻译未返回译文：${_snippet(responseData)}');
    }
    return _buildDirectLookupEntry(
      rawWord: rawWord,
      contextSentence: contextSentence,
      translatedText: translated,
      providerLabel: '阿里云翻译',
    );
  }

  WordLookupEntry _buildDirectLookupEntry({
    required String rawWord,
    required String? contextSentence,
    required String translatedText,
    required String providerLabel,
  }) {
    return WordLookupEntry(
      word: _displayWord(rawWord),
      phonetic: '',
      type: '英文单词',
      definitionEn: '',
      usageEn: contextSentence == null || contextSentence.trim().isEmpty
          ? ''
          : 'Context: ${contextSentence.trim()}',
      exampleSentenceEn: '',
      definitionCn: translatedText,
      sourceLabel: providerLabel,
      contextMeaningCn:
          contextSentence == null || contextSentence.trim().isEmpty
          ? null
          : translatedText,
    );
  }

  WordLookupEntry _buildUnavailableEntry({
    required String rawWord,
    required String messageCn,
    required String messageEn,
  }) {
    return WordLookupEntry(
      word: rawWord.isEmpty ? 'Word' : _displayWord(rawWord),
      phonetic: '',
      type: '英文单词',
      definitionEn: messageEn,
      usageEn: '',
      exampleSentenceEn: '',
      definitionCn: messageCn,
      sourceLabel: '未配置',
    );
  }

  String _normalizeWord(String rawWord) {
    return rawWord.toLowerCase().replaceAll(RegExp(r'[^\w]'), '').trim();
  }

  bool _canUseRemoteProvider(LearningSettingsState settings) {
    if (settings.translationApiKey.isEmpty) {
      return false;
    }
    if (settings.translationProvider == '百度翻译' ||
        settings.translationProvider == '阿里云翻译') {
      return settings.translationApiSecret.isNotEmpty;
    }
    return true;
  }

  bool _isDirectProvider(String provider) {
    return provider == 'Google 翻译' || provider == '百度翻译' || provider == '阿里云翻译';
  }

  String _displayWord(String rawWord) {
    if (rawWord.isEmpty) {
      return 'Word';
    }
    return rawWord[0].toUpperCase() + rawWord.substring(1);
  }

  Future<Response<dynamic>> _sendRequest({
    required BaseOptions options,
    required String method,
    required String path,
    Map<String, dynamic>? queryParameters,
    Object? data,
  }) async {
    if (httpRequestOverride != null) {
      return httpRequestOverride!(
        options: options,
        method: method,
        path: path,
        queryParameters: queryParameters,
        data: data,
      );
    }

    final Dio dio = Dio(options);
    return dio.request<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: Options(method: method),
    );
  }

  String _buildAliyunTimestamp() {
    return '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
  }

  String _buildAliyunSignature({
    required Map<String, dynamic> params,
    required String accessKeySecret,
  }) {
    final List<MapEntry<String, String>> sortedEntries =
        params.entries
            .map((MapEntry<String, dynamic> entry) {
              return MapEntry<String, String>(entry.key, '${entry.value}');
            })
            .toList(growable: false)
          ..sort(
            (MapEntry<String, String> a, MapEntry<String, String> b) =>
                a.key.compareTo(b.key),
          );
    final String canonicalizedQuery = sortedEntries
        .map((MapEntry<String, String> entry) {
          return '${_percentEncode(entry.key)}=${_percentEncode(entry.value)}';
        })
        .join('&');
    final String stringToSign =
        'GET&${_percentEncode('/')}&${_percentEncode(canonicalizedQuery)}';
    final Hmac hmac = Hmac(sha1, utf8.encode('$accessKeySecret&'));
    return base64Encode(hmac.convert(utf8.encode(stringToSign)).bytes);
  }

  String _percentEncode(String value) {
    return Uri.encodeQueryComponent(
      value,
    ).replaceAll('+', '%20').replaceAll('*', '%2A').replaceAll('%7E', '~');
  }
}
