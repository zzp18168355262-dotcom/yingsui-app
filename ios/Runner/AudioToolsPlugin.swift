import AVFoundation
import Flutter

/// iOS 侧音频工具通道：`com.yingsui.app/audio_tools`
///
/// 为什么需要它：AI 生成字幕要先把视频里的音频切成若干片段再送给 ASR 服务。
/// 各平台的分段方式不同：
///   · Android：MediaExtractor + MediaCodec（已实现）
///   · macOS：内置 ffmpeg 二进制 + Process.run
///   · **iOS：两者都用不了** —— iOS 沙盒禁止启动子进程（Process.run 会被拒），
///     所以此前 iOS 上「AI 生成字幕」必然失败。
/// 这里用 AVFoundation 的 AVAssetExportSession 按时间分段导出音频，
/// 对应 Android 的 `splitAudio`：入参 sourcePath / chunkMs，
/// 返回 [{path, offsetMs}, ...]。
///
/// 输出格式为 m4a（AAC）：AVAssetExportSession 的
/// `AVAssetExportPresetAppleM4A` 预设即可直接产出，主流 ASR 服务均接受。
final class AudioToolsPlugin {
  static let channelName = "com.yingsui.app/audio_tools"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "splitAudio":
      guard
        let args = call.arguments as? [String: Any],
        let sourcePath = args["sourcePath"] as? String,
        !sourcePath.isEmpty
      else {
        result(FlutterError(code: "bad_args", message: "sourcePath is required.", details: nil))
        return
      }
      let chunkMs = (args["chunkMs"] as? Int) ?? 58000
      // 导出可能耗时，放到后台队列，完成后回主线程回调。
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let chunks = try self.splitAudio(sourcePath: sourcePath, chunkMs: chunkMs)
          DispatchQueue.main.async { result(chunks) }
        } catch {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "split_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func splitAudio(sourcePath: String, chunkMs: Int) throws -> [[String: Any]] {
    let sourceURL = URL(fileURLWithPath: sourcePath)
    guard FileManager.default.fileExists(atPath: sourcePath) else {
      throw NSError(
        domain: Self.channelName,
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "源文件不存在：\(sourcePath)"]
      )
    }

    let asset = AVURLAsset(url: sourceURL)
    let duration = CMTimeGetSeconds(asset.duration)
    guard duration.isFinite, duration > 0 else {
      throw NSError(
        domain: Self.channelName,
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "无法读取视频时长"]
      )
    }

    // 只保留音频轨道：没有音频轨道时后续导出会失败，提前给出明确原因。
    let audioTracks = asset.tracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else {
      throw NSError(
        domain: Self.channelName,
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "该视频没有音频轨道"]
      )
    }

    let outputDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("cle_asr_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: outputDir,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let chunkSeconds = max(Double(chunkMs) / 1000.0, 1.0)
    var chunks: [[String: Any]] = []
    var startSeconds = 0.0
    var index = 0

    while startSeconds < duration {
      let endSeconds = min(startSeconds + chunkSeconds, duration)
      let chunkURL = outputDir.appendingPathComponent(
        String(format: "chunk_%05d.m4a", index)
      )
      try exportChunk(
        asset: asset,
        audioTracks: audioTracks,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        to: chunkURL
      )
      chunks.append([
        "path": chunkURL.path,
        "offsetMs": Int((startSeconds * 1000).rounded()),
      ])
      index += 1
      startSeconds = endSeconds
    }

    guard !chunks.isEmpty else {
      throw NSError(
        domain: Self.channelName,
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "音频分段结果为空"]
      )
    }
    return chunks
  }

  /// 导出一段音频到指定文件。
  ///
  /// 用 AVMutableComposition 拼出时间区间再导出：
  /// 直接对 AVAsset 设置 timeRange 需要配合 AVAssetExportSession，
  /// 而 composition 方式对「只取音频」的表达更直接、也更容易去掉视频轨。
  private func exportChunk(
    asset: AVURLAsset,
    audioTracks: [AVAssetTrack],
    startSeconds: Double,
    endSeconds: Double,
    to outputURL: URL
  ) throws {
    let composition = AVMutableComposition()
    guard
      let compositionTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      throw NSError(
        domain: Self.channelName,
        code: 5,
        userInfo: [NSLocalizedDescriptionKey: "无法创建音频合成轨道"]
      )
    }

    let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
    let duration = CMTime(
      seconds: max(endSeconds - startSeconds, 0.05),
      preferredTimescale: 600
    )
    // 逐个音频轨道尝试插入；任一轨道成功即可（通常只有一个）。
    var inserted = false
    for track in audioTracks {
      do {
        try compositionTrack.insertTimeRange(
          CMTimeRange(start: start, duration: duration),
          of: track,
          at: .zero
        )
        inserted = true
        break
      } catch {
        continue
      }
    }
    guard inserted else {
      throw NSError(
        domain: Self.channelName,
        code: 6,
        userInfo: [NSLocalizedDescriptionKey: "无法读取该时间段的音频"]
      )
    }

    guard
      let export = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPresetAppleM4A
      )
    else {
      throw NSError(
        domain: Self.channelName,
        code: 7,
        userInfo: [NSLocalizedDescriptionKey: "无法创建音频导出会话"]
      )
    }
    export.outputURL = outputURL
    export.outputFileType = .m4a

    // AVAssetExportSession 的导出是异步的，用信号量同步等待，便于顺序产出分片。
    let semaphore = DispatchSemaphore(value: 0)
    export.exportAsynchronously { semaphore.signal() }
    semaphore.wait()

    if export.status != .completed {
      let reason = export.error?.localizedDescription ?? "未知原因"
      throw NSError(
        domain: Self.channelName,
        code: 8,
        userInfo: [NSLocalizedDescriptionKey: "音频导出失败：\(reason)"]
      )
    }
  }
}
