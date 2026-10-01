import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/desktop_ffmpeg.dart';

void main() {
  test('macOS checks the app bundle before system ffmpeg', () {
    final List<String> candidates = desktopFfmpegCandidates(
      operatingSystem: 'macos',
      resolvedExecutable:
          '/Applications/EnglishCorner.app/Contents/MacOS/app',
    );

    expect(
      candidates.first,
      '/Applications/EnglishCorner.app/Contents/Resources/ffmpeg/ffmpeg',
    );
    expect(candidates, contains('ffmpeg'));
  });

  test('Windows checks the packaged executable next to the app', () {
    final List<String> candidates = desktopFfmpegCandidates(
      operatingSystem: 'windows',
      resolvedExecutable: r'C:\EnglishCorner\yingsui.exe',
    );

    expect(candidates.first, r'C:\EnglishCorner\ffmpeg\ffmpeg.exe');
  });

  test('Linux checks the relocatable bundle library directory', () {
    final List<String> candidates = desktopFfmpegCandidates(
      operatingSystem: 'linux',
      resolvedExecutable: '/opt/yingsui-app/yingsui',
    );

    expect(candidates.first, '/opt/yingsui-app/lib/ffmpeg/ffmpeg');
  });
}
