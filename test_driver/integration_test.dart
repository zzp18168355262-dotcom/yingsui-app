/// integration_test 的 driver：把测试里的截图落盘。
///
/// 运行方式见 integration_test/ui_tour_test.dart 顶部注释。
library;

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final Directory dir = Directory('build/ui-tour');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final String path = '${dir.path}/$name.png';
      File(path).writeAsBytesSync(bytes);
      // ignore: avoid_print
      print('截图已保存: $path');
      return true;
    },
  );
}
