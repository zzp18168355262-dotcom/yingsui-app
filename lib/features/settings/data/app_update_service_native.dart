import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../config/app_links.dart';

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.assetName,
    required this.downloadUrl,
    required this.checksumUrl,
  });

  final String version;
  final String assetName;
  final String downloadUrl;
  final String checksumUrl;
}

/// 更新检查用的 Dio 客户端。
///
/// 更新检查是后台行为，不能无限等待（Dio 默认不超时）。
Dio _defaultUpdateDio() => Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 15),
  ),
);

class AppUpdateService {
  AppUpdateService({
    Dio? dio,
    String? releasesUrl,
    List<String>? assetSuffixes,
    String? currentVersion,
  }) : _dio = dio ?? _defaultUpdateDio(),
       _releasesUrlOverride = releasesUrl,
       _assetSuffixesOverride = assetSuffixes,
       _currentVersionOverride = currentVersion;

  final Dio _dio;

  /// 测试注入用；为空时读取 [AppLinks.releasesUrl]。
  final String? _releasesUrlOverride;

  /// 测试注入用；为空时按当前运行平台推断。
  final List<String>? _assetSuffixesOverride;

  /// 测试注入用；为空时通过 PackageInfo 读取当前安装版本。
  ///
  /// PackageInfo 是带缓存的全局单例，测试之间无法可靠地改变它，
  /// 因此版本同样需要可注入。
  final String? _currentVersionOverride;

  String get _releasesUrl => _releasesUrlOverride ?? AppLinks.releasesUrl;

  Future<AppUpdate?> checkForUpdate() async {
    // 未配置发布源时直接跳过，不发起任何网络请求。
    if (_releasesUrl.trim().isEmpty) {
      return null;
    }

    final String currentVersion =
        _currentVersionOverride ?? (await PackageInfo.fromPlatform()).version;
    // 用 dynamic 解析：发布源可能是两种格式之一。
    //   1) 自建 manifest（/downloads/manifest.json）—— 本项目使用
    //   2) GitHub Releases API 数组 —— 早期方案，保留兼容
    final Response<dynamic> response = await _dio.get<dynamic>(
      _releasesUrl,
      options: Options(headers: <String, String>{'Accept': 'application/json'}),
    );

    final _ReleaseInfo release = _parseRelease(response.data);
    if (_compareVersions(release.version, currentVersion) <= 0) {
      return null;
    }

    final List<String> suffixes =
        _assetSuffixesOverride ?? _assetSuffixesForCurrentPlatform();
    if (suffixes.isEmpty) {
      // 例如 iOS：IPA 需重新签名，无法自行覆盖更新。
      return null;
    }
    _AssetRef? package;
    for (final String suffix in suffixes) {
      package = _assetEndingWith(release.assets, suffix);
      if (package != null) break;
    }
    final _AssetRef? checksum = _assetEndingWith(
      release.assets,
      'SHA256SUMS.txt',
    );
    if (package == null || checksum == null) {
      throw StateError(
        '该发布源未提供当前平台（${suffixes.join(' 或 ')}）的更新包。',
      );
    }

    return AppUpdate(
      version: release.version,
      assetName: package.name,
      downloadUrl: _absoluteUrl(package.url),
      checksumUrl: _absoluteUrl(checksum.url),
    );
  }

  /// 把相对地址补全为绝对地址。
  ///
  /// 自建 manifest 里是 `/downloads/xxx.apk` 这样的相对路径，
  /// 需要基于 releasesUrl 的站点根拼成完整地址才能下载。
  String _absoluteUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final Uri? base = Uri.tryParse(_releasesUrl);
    if (base == null || !base.hasScheme) return url;
    // 用 replace 会补上空 query/fragment，产生 "...zip?#" 这样的地址，
    // 因此只取 scheme + host + port，再手工拼上路径。
    final String origin =
        '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
    final String path = url.startsWith('/') ? url : '/$url';
    return '$origin$path';
  }

  /// 解析发布源响应，兼容自建 manifest 与 GitHub Releases 两种格式。
  _ReleaseInfo _parseRelease(dynamic data) {
    // 自建 manifest：单个对象，含 version / assets。
    if (data is Map<String, dynamic>) {
      final Object? assetsField = data['assets'];
      if (assetsField is List) {
        return _ReleaseInfo(
          version: _versionFromTag(
            (data['version'] as String? ?? data['tag_name'] as String?) ?? '',
          ),
          assets: assetsField
              .whereType<Map<Object?, Object?>>()
              .map(_AssetRef.fromJson)
              .whereType<_AssetRef>()
              .toList(growable: false),
        );
      }
    }

    // GitHub Releases API：数组，取最新稳定版。
    if (data is List) {
      final Map<String, dynamic> release = _highestStableRelease(data);
      return _ReleaseInfo(
        version: _versionFromTag(release['tag_name']),
        assets: (release['assets'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<Object?, Object?>>()
            .map(_AssetRef.fromJson)
            .whereType<_AssetRef>()
            .toList(growable: false),
      );
    }

    throw StateError('无法识别的发布源格式，请检查「发布源地址」配置。');
  }

  Future<String> download(
    AppUpdate update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final Directory root =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final Directory destination = Directory(
      '${root.path}${Platform.pathSeparator}English Corner',
    );
    await destination.create(recursive: true);
    final File file = File(
      '${destination.path}${Platform.pathSeparator}${update.assetName}',
    );

    await _dio.download(
      update.downloadUrl,
      file.path,
      onReceiveProgress: onProgress,
    );
    final String expectedChecksum = await _checksumFor(
      update.assetName,
      update.checksumUrl,
    );
    final String actualChecksum = (await sha256.bind(file.openRead()).first)
        .toString();
    if (actualChecksum.toLowerCase() != expectedChecksum.toLowerCase()) {
      await file.delete();
      throw StateError('安装包校验失败，已删除下载文件。');
    }
    return file.path;
  }

  Future<void> install(String path) async {
    final OpenResult result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  Future<String> _checksumFor(String assetName, String checksumUrl) async {
    final Response<String> response = await _dio.get<String>(checksumUrl);
    for (final String rawLine in response.data?.split('\n') ?? <String>[]) {
      final String line = rawLine.trim();
      if (line.endsWith('  $assetName')) {
        return line.split(RegExp(r'\s+')).first;
      }
    }
    throw StateError('SHA256SUMS.txt 中未找到 $assetName。');
  }

  _AssetRef? _assetEndingWith(List<_AssetRef> assets, String suffix) {
    for (final _AssetRef asset in assets) {
      if (asset.name.endsWith(suffix)) {
        return asset;
      }
    }
    return null;
  }
}

/// 发布源中的一个更新包。
///
/// url 字段兼容两种命名：
///   - 自建 manifest 用 `downloadUrl` / `checksumUrl`
///   - GitHub Releases 用 `browser_download_url`
class _AssetRef {
  const _AssetRef({required this.name, required this.url});

  final String name;
  final String url;

  static _AssetRef? fromJson(Map<Object?, Object?> json) {
    final Object? name = json['name'];
    final Object? url =
        json['downloadUrl'] ?? json['browser_download_url'] ?? json['url'];
    if (name is! String || name.isEmpty || url is! String || url.isEmpty) {
      return null;
    }
    return _AssetRef(name: name, url: url);
  }
}

/// 从发布源解析出的版本与包列表。
class _ReleaseInfo {
  const _ReleaseInfo({required this.version, required this.assets});

  final String version;
  final List<_AssetRef> assets;
}

Map<String, dynamic> _highestStableRelease(List<dynamic> releases) {
  Map<String, dynamic>? newestRelease;
  String? newestVersion;
  for (final dynamic release in releases) {
    if (release is! Map<String, dynamic> ||
        release['draft'] == true ||
        release['prerelease'] == true) {
      continue;
    }
    final String? version = _tryVersionFromTag(release['tag_name']);
    if (version == null) {
      continue;
    }
    if (newestVersion == null || _compareVersions(version, newestVersion) > 0) {
      newestRelease = release;
      newestVersion = version;
    }
  }
  if (newestRelease == null) {
    throw const FormatException('GitHub 未返回可用的正式 Release。');
  }
  return newestRelease;
}

/// 当前平台可能对应的更新包后缀（按优先级排列）。
///
/// macOS 同时列出 .zip 与 .dmg：本项目当前发的是 zip
/// （DMG 在受限环境下无法生成），但保留 dmg 以便将来切换。
/// iOS 不提供：IPA 必须重新签名才能安装，无法自行覆盖更新。
List<String> _assetSuffixesForCurrentPlatform() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return const <String>['-android.apk'];
    case TargetPlatform.linux:
      return const <String>['-linux-x64.tar.gz'];
    case TargetPlatform.macOS:
      return const <String>['-macos.zip', '-macos.dmg'];
    case TargetPlatform.windows:
      return const <String>['-windows-x64.zip'];
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return const <String>[];
  }
}

String _versionFromTag(Object? tag) {
  final String? version = _tryVersionFromTag(tag);
  if (version == null) {
    throw const FormatException('GitHub Release 缺少版本标签。');
  }
  return version;
}

String? _tryVersionFromTag(Object? tag) {
  if (tag is! String) {
    return null;
  }
  final String version = tag.replaceFirst(RegExp('^v'), '');
  return RegExp(r'^\d+(?:\.\d+){2}$').hasMatch(version) ? version : null;
}

int _compareVersions(String left, String right) {
  final List<int> leftParts = left
      .split('+')
      .first
      .split('.')
      .map(int.parse)
      .toList();
  final List<int> rightParts = right
      .split('+')
      .first
      .split('.')
      .map(int.parse)
      .toList();
  final int length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (int index = 0; index < length; index++) {
    final int difference =
        (index < leftParts.length ? leftParts[index] : 0) -
        (index < rightParts.length ? rightParts[index] : 0);
    if (difference != 0) {
      return difference;
    }
  }
  return 0;
}
