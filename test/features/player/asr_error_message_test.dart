/// ASR 错误提示的翻译。
///
/// 背景：用户遇到「AI 字幕识别一直失败」，界面显示的是服务商返回的英文原文：
///   `HTTP 400 {code: Arrearage, message: Access denied, please make sure
///    your account is in good standing. ...}`
/// 这是**阿里云账号欠费**，充值即可，但用户无法从这段英文里得知。
/// 这里把常见错误码映射成可照着做的中文提示，并锁定行为。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/asr_subtitle_job.dart';

void main() {
  group('friendlyAsrError', () {
    test('识别阿里云欠费（用户实际遇到的报错）', () {
      const String raw =
          'HTTP 400 {code: Arrearage, message: Access denied, please make '
          'sure your account is in good standing. For details, see: http...}';
      final String message = friendlyAsrError(raw);
      expect(message, contains('欠费'));
      expect(message, contains('充值'));
      // 原始信息要保留，便于用户/开发者核对真实原因。
      expect(message, contains('Arrearage'));
    });

    test('识别 API Key 无效', () {
      expect(friendlyAsrError('401 invalid_api_key'), contains('API Key'));
      expect(friendlyAsrError('Incorrect API key provided'), contains('API Key'));
    });

    test('识别模型不可用', () {
      expect(
        friendlyAsrError('model_not_found: qwen3-asr-flash-filetrans'),
        contains('模型'),
      );
    });

    test('识别限流与超时', () {
      expect(friendlyAsrError('429 Too Many Requests'), contains('限流'));
      expect(friendlyAsrError('request timed out'), contains('超时'));
    });

    test('识别手机上原生音频分段的错误', () {
      // 由 Android 的 splitAudio / iOS 的 AudioToolsPlugin 抛出。
      expect(friendlyAsrError('no audio track found'), contains('没有音频轨道'));
      expect(
        friendlyAsrError('source file does not exist: /x.mp4'),
        contains('找不到视频文件'),
      );
    });

    test('未识别的错误原样返回，不掩盖真实原因', () {
      const String raw = 'some brand new provider failure xyz';
      expect(friendlyAsrError(raw), raw);
    });
  });
}
