enum AppFlavor { dev, staging, prod }

class FlavorConfig {
  static AppFlavor _flavor = AppFlavor.prod;

  static void setFlavor(AppFlavor flavor) {
    _flavor = flavor;
  }

  static AppFlavor get flavor => _flavor;

  static String get flavorName => _flavor.name;

  static bool get isDev => _flavor == AppFlavor.dev;
  static bool get isStaging => _flavor == AppFlavor.staging;
  static bool get isProd => _flavor == AppFlavor.prod;

  /// 应用显示名。开发/预发渠道带后缀，正式版中英并置便于出海识别。
  static String get appName {
    switch (_flavor) {
      case AppFlavor.dev:
        return '英语角 Dev';
      case AppFlavor.staging:
        return '英语角 Staging';
      case AppFlavor.prod:
        return '英语角 English Corner';
    }
  }

  static String get bundleId {
    switch (_flavor) {
      case AppFlavor.dev:
        return 'com.yingsui.app.dev';
      case AppFlavor.staging:
        return 'com.yingsui.app.staging';
      case AppFlavor.prod:
        return 'com.yingsui.app';
    }
  }
}
