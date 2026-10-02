import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/settings/data/app_update_service_native.dart';

/// 更新源解析。
///
/// 背景：原先只支持 GitHub Releases 的响应格式（browser_download_url），
/// 但本项目走自建分发，发布源是 scripts/package-release.sh 生成的
/// manifest.json。若不兼容，用户填好域名后更新检查会直接解析失败。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppUpdateService serviceReturning(
    Object payload, {
    String? url,
    String currentVersion = '0.2.0',
  }) {
    final Dio dio = Dio()
      ..httpClientAdapter = _StubAdapter(payload);
    return AppUpdateService(
      dio: dio,
      releasesUrl: url ?? 'https://example.com/downloads/manifest.json',
      // 固定为 macOS 后缀列表，让断言与运行测试的机器平台无关。
      assetSuffixes: const <String>['-macos.zip', '-macos.dmg'],
      currentVersion: currentVersion,
    );
  }

  test('解析自建 manifest，并识别当前平台对应的包', () async {
    // 与 scripts/package-release.sh 生成的 manifest.json 结构一致。
    final Map<String, dynamic> manifest = <String, dynamic>{
      'version': '0.2.7',
      'buildNumber': 17,
      'assets': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'EnglishCorner-0.2.7-android.apk',
          'platform': 'android',
          'downloadUrl': '/downloads/EnglishCorner-0.2.7-android.apk',
        },
        <String, dynamic>{
          'name': 'EnglishCorner-0.2.7-ios-unsigned.ipa',
          'platform': 'ios',
          'downloadUrl': '/downloads/EnglishCorner-0.2.7-ios-unsigned.ipa',
        },
        <String, dynamic>{
          'name': 'EnglishCorner-0.2.7-macos.zip',
          'platform': 'macos',
          'downloadUrl': '/downloads/EnglishCorner-0.2.7-macos.zip',
        },
        <String, dynamic>{
          'name': 'SHA256SUMS.txt',
          'platform': 'any',
          'downloadUrl': '/downloads/SHA256SUMS.txt',
        },
      ],
      'checksumUrl': '/downloads/SHA256SUMS.txt',
    };

    final AppUpdate? update = await serviceReturning(manifest).checkForUpdate();

    expect(update, isNotNull);
    expect(update!.version, '0.2.7');
    // 测试跑在 macOS 上，应选中 macos.zip（而不是 android.apk）。
    expect(update.assetName, endsWith('.zip'));
    expect(
      update.downloadUrl,
      'https://example.com/downloads/EnglishCorner-0.2.7-macos.zip',
      reason: '相对路径应基于发布源域名补全为绝对地址',
    );
    expect(
      update.checksumUrl,
      'https://example.com/downloads/SHA256SUMS.txt',
    );
  });

  test('发布源版本不高于当前版本时不提示更新', () async {
    final AppUpdate? update = await serviceReturning(
      <String, dynamic>{
        'version': '0.2.7',
        'assets': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'EnglishCorner-0.2.7-macos.zip',
            'downloadUrl': '/downloads/EnglishCorner-0.2.7-macos.zip',
          },
          <String, dynamic>{
            'name': 'SHA256SUMS.txt',
            'downloadUrl': '/downloads/SHA256SUMS.txt',
          },
        ],
      },
      // 当前已是同一版本。
      currentVersion: '0.2.7',
    ).checkForUpdate();

    expect(update, isNull);
  });

  test('未配置发布源时完全不发请求', () async {
    bool requested = false;
    final Dio dio = Dio()
      ..httpClientAdapter = _StubAdapter(
        <String, dynamic>{},
        onRequest: () => requested = true,
      );

    final AppUpdate? update = await AppUpdateService(
      dio: dio,
      releasesUrl: '',
    ).checkForUpdate();

    expect(update, isNull);
    expect(requested, isFalse, reason: '未配置地址时不应发起任何网络请求');
  });

  test('仍兼容 GitHub Releases 数组格式', () async {
    final List<Map<String, dynamic>> releases = <Map<String, dynamic>>[
      <String, dynamic>{
        'tag_name': 'v0.2.7',
        'prerelease': false,
        'assets': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'EnglishCorner-0.2.7-macos.zip',
            'browser_download_url':
                'https://github.com/example/repo/releases/download/v0.2.7/EnglishCorner-0.2.7-macos.zip',
          },
          <String, dynamic>{
            'name': 'SHA256SUMS.txt',
            'browser_download_url':
                'https://github.com/example/repo/releases/download/v0.2.7/SHA256SUMS.txt',
          },
        ],
      },
    ];

    final AppUpdate? update = await serviceReturning(releases).checkForUpdate();

    expect(update, isNotNull);
    expect(update!.version, '0.2.7');
    expect(update.assetName, endsWith('.zip'));
    expect(update.downloadUrl, startsWith('https://github.com/'));
  });
}

/// 用桩适配器替代真实网络，避免测试依赖外网。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.payload, {this.onRequest});

  final Object payload;
  final VoidCallback? onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onRequest?.call();
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
