/// 英语角 / English Corner —— 对外地址统一配置。
///
/// 品牌与分发信息集中在这里，改名或换域名时只改这一个文件。
class AppLinks {
  AppLinks._();

  /// 官网地址（用于关于页、分享、下载引导）。
  /// TODO: 换成你自己的域名。
  static const String website = '';

  /// 更新接口 / 发布源地址。
  ///
  /// 留空表示「关闭自动更新检查」——App 不会发起任何更新请求，
  /// 用户只会看到关于页里的官网地址，不会出现升级提示。
  ///
  /// 将来接入自己的发布接口时，把地址填在这里即可恢复自动更新。
  static const String releasesUrl = '';

  /// 是否启用自动更新检查。
  static bool get isUpdateCheckEnabled => releasesUrl.trim().isNotEmpty;

  /// 是否已配置官网。
  static bool get hasWebsite => website.trim().isNotEmpty;
}
