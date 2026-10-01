import 'package:yingsui/features/player/presentation/desktop_ffmpeg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS checks the app bundle before system ffmpeg', () {
    final List<String> candidates = desktopFfmpegCandidates(
      operatingSystem: 'macos',
      resolvedExecutable:
          '/Applications/YingSui.app/Contents/MacOS/app',
    );

    expect(
      candidates.first,
      '/Applications/YingSui.app/Contents/Resources/ffmpeg/ffmpeg',
    );
    expect(candidates, contains('ffmpeg'));
  });

  test('Windows checks the packaged executable next to the app', () {
    final List<String> candidates = desktopFfmpegCandidates(
      operatingSystem: 'windows',
      resolvedExecutable: r'C:\YingSui\yingsui.exe',
    );

    expect(candidates.first, r'C:\YingSui\ffmpeg\ffmpeg.exe');
  });

  test('Linux checks the relocatable bundle library directory', () {
    final List<String> candidates = desktopFfmpegCandidates(
      operatingSystem: 'linux',
      resolvedExecutable: '/opt/yingsui-app/yingsui',
    );

    expect(candidates.first, '/opt/yingsui-app/lib/ffmpeg/ffmpeg');
  });
}
