/// 发布包配置检查。
///
/// 为什么需要：有些缺陷**只在 release 包上出现**，本地调试完全正常 ——
/// 靠跑应用是发现不了的，只有发布后用户反馈才知道。
///
/// 已发生的真实问题：
///   Flutter 模板只在 debug/profile 的 AndroidManifest 里声明 INTERNET，
///   **main 里没有**。于是 release APK 完全没有网络权限，
///   装到手机上后 AI 字幕、翻译、更新检查等所有联网功能静默失败
///   （用户看到的是「翻译服务不可用」，很难定位到是权限问题）。
///
/// 本文件把这类「发布配置」断言下来，避免再次漏掉。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android 发布配置', () {
    final File manifest = File('android/app/src/main/AndroidManifest.xml');

    test('main manifest 声明 INTERNET 权限', () {
      expect(
        manifest.existsSync(),
        isTrue,
        reason: '找不到 main AndroidManifest.xml',
      );
      final String source = manifest.readAsStringSync();
      expect(
        source.contains('android.permission.INTERNET'),
        isTrue,
        reason:
            'main manifest 必须声明 INTERNET —— Flutter 模板只在 '
            'debug/profile 里加它，若 main 缺失，release 包将没有任何网络权限。',
      );
    });

    test('main manifest 声明录音权限（口播/跟读需要）', () {
      final String source = manifest.readAsStringSync();
      expect(
        source.contains('android.permission.RECORD_AUDIO'),
        isTrue,
        reason: '跟读录音依赖该权限',
      );
    });

    test('存在 release 密钥库配置时可正式签名', () {
      // 密钥库本身不入库（.gitignore），因此这里只检查「配置是否成对存在」：
      // 有 key.properties 就应有对应的 jks，避免只有其一导致构建失败。
      final File props = File('android/key.properties');
      if (!props.existsSync()) {
        return; // 没有正式密钥时构建会回退 debug 签名，这是已知且允许的。
      }
      final String content = props.readAsStringSync();
      final RegExp storeFile = RegExp(r'^storeFile=(.+)$', multiLine: true);
      final Match? match = storeFile.firstMatch(content);
      expect(match, isNotNull, reason: 'key.properties 缺少 storeFile');
      final String rel = match!.group(1)!.trim();
      // Gradle 的 file() 相对 android/app 解析。
      final File jks = File('android/app/$rel');
      expect(
        jks.existsSync(),
        isTrue,
        reason:
            'key.properties 指向的密钥库不存在：android/app/$rel —— '
            '注意 storeFile 由 Gradle 相对 android/app 解析。',
      );
    });
  });

  group('iOS 发布配置', () {
    test('声明文件共享，导出的字幕用户可见', () {
      final File plist = File('ios/Runner/Info.plist');
      expect(plist.existsSync(), isTrue);
      final String source = plist.readAsStringSync();
      expect(
        source.contains('UIFileSharingEnabled'),
        isTrue,
        reason:
            'AI 字幕导出会写入文档目录；未声明 UIFileSharingEnabled 时 '
            '用户无法通过系统「文件」App 看到导出结果。',
      );
    });
  });
}
