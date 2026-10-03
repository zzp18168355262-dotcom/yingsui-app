import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 音频工具通道（AI 字幕的音频分段）。
  ///
  /// iOS 无法像 macOS 那样用 ffmpeg 子进程（沙盒禁止 Process.run），
  /// 因此改用 AVFoundation 原生实现，详见 AudioToolsPlugin.swift。
  private var audioToolsPlugin: AudioToolsPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 注册自定义音频工具通道：AI 生成字幕需要把视频音频分段后送 ASR。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioToolsPlugin") {
      audioToolsPlugin = AudioToolsPlugin(messenger: registrar.messenger())
    }
  }
}
