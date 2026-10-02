import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import 'asr_subtitle_cache.dart';
import 'asr_subtitle_service.dart';
import 'player_mock_state.dart';
import 'player_subtitle_loader.dart';
import 'subtitle_word_alignment.dart';

typedef AsrChunkTranscriber =
    Future<Map<String, Object?>> Function({
      required AsrAudioChunk chunk,
      required LearningSettingsState settings,
    });
typedef AsrSentenceTranslator =
    Future<String?> Function({
      required String sentence,
      required LearningSettingsState settings,
    });

class AsrSubtitleGenerationException implements Exception {
  const AsrSubtitleGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AsrSubtitleCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const AsrSubtitleGenerationException('AI 字幕生成已取消。');
    }
  }
}

class AsrSubtitleRepairSummary {
  const AsrSubtitleRepairSummary(this.itemCount);

  final int itemCount;

  String appendTo(String message) =>
      itemCount > 0 ? '$message，已自动修复 $itemCount 项时间轴数据' : message;
}

class AsrRegeneratedLineResult {
  const AsrRegeneratedLineResult({required this.line, required this.raw});

  final PlayerSubtitleLine line;
  final String raw;
}

String subtitleReferenceSignature(List<PlayerSubtitleLine> lines) {
  final List<PlayerSubtitleLine> usableLines = usableReferenceSubtitles(lines);
  if (usableLines.isEmpty) return '';
  final String value = usableLines
      .map(
        (PlayerSubtitleLine line) =>
            '${line.startMs}|${line.endMs}|${line.english}|${line.chinese}',
      )
      .join('\n');
  return sha1.convert(utf8.encode(value)).toString();
}

String? subtitleGenerationWarning(String raw) {
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final List<String> warnings = <String>[
      for (final String key in <String>['timingWarning', 'translationWarning'])
        if ((decoded[key] as String? ?? '').trim().isNotEmpty)
          (decoded[key] as String).trim(),
    ];
    return warnings.isEmpty ? null : warnings.join('；');
  } catch (_) {
    return null;
  }
}

class _SubtitleQualityReport {
  _SubtitleQualityReport(this.provider);

  final String provider;
  final List<Map<String, Object?>> anomalies = <Map<String, Object?>>[];
  final List<Map<String, Object?>> chunks = <Map<String, Object?>>[];
  int wordOverlap = 0;
  int sentenceOverlap = 0;
  int chunkBoundaryOverlap = 0;
  int wordFix = 0;
  int wordDeleted = 0;
  int chunkBoundaryFix = 0;
  int repairCount = 0;
  bool usedReferenceFallback = false;

  void addOverlap({
    required String kind,
    required String previousText,
    required int previousStart,
    required int previousEnd,
    required String currentText,
    required int currentStart,
    required int currentEnd,
    required int overlapMs,
    required int sourceChunk,
    required int previousSourceChunk,
  }) {
    if (kind == 'word') {
      wordOverlap += 1;
    } else if (kind == 'sentence') {
      sentenceOverlap += 1;
      if (sourceChunk != previousSourceChunk) {
        chunkBoundaryOverlap += 1;
      }
    } else if (kind == 'chunkBoundary') {
      chunkBoundaryOverlap += 1;
    }
    anomalies.add(<String, Object?>{
      'kind': kind,
      'previousText': previousText,
      'previousStart': previousStart,
      'previousEnd': previousEnd,
      'currentText': currentText,
      'currentStart': currentStart,
      'currentEnd': currentEnd,
      'overlapMs': overlapMs,
      'sourceChunk': sourceChunk,
      'previousSourceChunk': previousSourceChunk,
      'provider': provider,
    });
  }

  void addChunk({
    required int sourceChunk,
    required int startOffsetMs,
    required int endOffsetMs,
    required List<Map<String, Object?>> lines,
  }) {
    final List<Map<String, Object?>> words = lines
        .expand(
          (Map<String, Object?> line) =>
              (line['words'] as List<dynamic>? ?? const <dynamic>[])
                  .whereType<Map<String, dynamic>>()
                  .map(Map<String, Object?>.from),
        )
        .toList(growable: false);
    chunks.add(<String, Object?>{
      'sourceChunk': sourceChunk,
      'startOffsetMs': startOffsetMs,
      'endOffsetMs': endOffsetMs,
      'firstWord': words.isEmpty ? '' : words.first['text'],
      'actualStart': words.isEmpty ? null : words.first['startMs'],
      'lastWord': words.isEmpty ? '' : words.last['text'],
      'actualEnd': words.isEmpty ? null : words.last['endMs'],
    });
  }

  Future<void> write(Directory jobDir, String finalStatus) {
    return File(
      '${jobDir.path}${Platform.pathSeparator}subtitle_quality_report.json',
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'provider': provider,
        'wordOverlap': wordOverlap,
        'sentenceOverlap': sentenceOverlap,
        'chunkBoundaryOverlap': chunkBoundaryOverlap,
        'wordFix': wordFix,
        'wordDeleted': wordDeleted,
        'chunkBoundaryFix': chunkBoundaryFix,
        'repairCount': repairCount,
        'usedReferenceFallback': usedReferenceFallback,
        'chunks': chunks,
        'anomalies': anomalies,
        'finalStatus': finalStatus,
      }),
    );
  }
}

class AsrSubtitleJobRunner {
  const AsrSubtitleJobRunner({
    this.supportDirectory,
    this.cache = const AsrSubtitleCache(),
    this.service = const AsrSubtitleService(),
    this.cloudTranscribeChunk,
    this.translateSentence,
    this.wordLookupService = const WordLookupService(),
    this.translationRequestInterval = _translationRequestInterval,
    this.translationBatchSize = _translationBatchSize,
  });

  final Future<Directory> Function()? supportDirectory;
  final AsrSubtitleCache cache;
  final AsrSubtitleService service;
  final AsrChunkTranscriber? cloudTranscribeChunk;
  final AsrSentenceTranslator? translateSentence;

  /// 真实翻译服务。测试可注入带桩的实现，
  /// 用于验证「翻译彻底不可用时仍产出英文字幕」等降级行为。
  final WordLookupService wordLookupService;

  /// 逐句翻译之间的间隔。测试可传 Duration.zero 避免真实等待。
  final Duration translationRequestInterval;

  /// 批量翻译的批大小。测试可传 1 强制走逐句路径。
  final int translationBatchSize;

  static const int _repairableOverlapMs = 500;

  /// 逐句翻译之间的间隔。
  ///
  /// 第三方翻译接口（尤其大模型接口）在短时间内收到大量请求时会限流，
  /// 典型表现就是「翻了一阵之后突然全部失败」。留出间隔可显著降低触发概率。
  /// 取值权衡：200ms 约等于 5 句/秒，对多数接口是安全区间；
  /// 500 句的长字幕因此多花约 100 秒，可以接受。
  static const Duration _translationRequestInterval = Duration(
    milliseconds: 200,
  );

  /// 批量翻译的默认批大小。
  ///
  /// 取值权衡：过大时模型容易漏译或错位，过小时请求次数下降有限。
  /// 20 句一次可将 500 句的长字幕从约 500 次请求降到约 25 次。
  static const int _translationBatchSize = 20;

  static final Set<String> _activeJobs = <String>{};

  Future<AsrRegeneratedLineResult> regenerateLine({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    required List<PlayerSubtitleLine> currentLines,
    required int lineIndex,
    String? referenceSignature,
  }) async {
    if (lineIndex < 0 || lineIndex >= currentLines.length) {
      throw const AsrSubtitleGenerationException('当前句不存在，无法重新生成。');
    }
    final File video = File(videoPath);
    if (!video.existsSync()) {
      throw const AsrSubtitleGenerationException('当前视频不可用，无法重新生成这句话。');
    }
    final String jobKey = _jobKey(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    if (!_activeJobs.add(jobKey)) {
      throw const AsrSubtitleGenerationException('这个视频的 AI 字幕正在生成，请等待当前任务完成。');
    }

    List<AsrAudioChunk> chunks = const <AsrAudioChunk>[];
    try {
      chunks = await service.prepareAudioChunks(video);
      if (chunks.isEmpty) {
        throw const AsrSubtitleGenerationException('没有提取到可识别的音频，原句已保留。');
      }
      final PlayerSubtitleLine currentLine = currentLines[lineIndex];
      final List<Map<String, Object?>> recognizedLines =
          <Map<String, Object?>>[];
      final _SubtitleQualityReport report = _SubtitleQualityReport(
        settings.asrProvider,
      );

      for (int index = 0; index < chunks.length; index += 1) {
        final int chunkEndMs = index + 1 < chunks.length
            ? chunks[index + 1].offsetMs
            : chunks[index].offsetMs + 58000;
        if (chunks[index].offsetMs >= currentLine.endMs ||
            chunkEndMs <= currentLine.startMs) {
          continue;
        }
        Map<String, Object?>? normalized;
        Object? lastError;
        for (int attempt = 0; attempt < 2; attempt += 1) {
          try {
            final Map<String, Object?> response =
                await _transcribe(
                  chunk: chunks[index],
                  settings: settings,
                ).timeout(
                  const Duration(minutes: 20),
                  onTimeout: () =>
                      throw TimeoutException('AI 重新识别当前句超时，请稍后重试。'),
                );
            normalized = _normalizeChunkTimeline(
              response,
              chunkStartMs: chunks[index].offsetMs,
              chunkEndMs: chunkEndMs,
              sourceChunk: index,
              report: report,
            );
            break;
          } catch (error) {
            lastError = error;
          }
        }
        if (normalized == null) {
          throw AsrSubtitleGenerationException(
            '当前句重新识别失败，原句已保留：${_errorMessage(lastError ?? 'unknown-error')}',
          );
        }
        recognizedLines.addAll(
          (normalized['lines'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(Map<String, Object?>.from),
        );
      }

      final List<PlayerSubtitleWord> words = _wordsForCurrentLine(
        recognizedLines,
        currentLine,
      );
      if (words.isEmpty) {
        throw const AsrSubtitleGenerationException(
          'AI 没有在当前句时间范围内识别到有效英文，原句已保留。',
        );
      }
      final String english = words
          .map((PlayerSubtitleWord word) => word.text)
          .join(' ')
          .trim();
      if (english.isEmpty) {
        throw const AsrSubtitleGenerationException('AI 返回了空字幕，原句已保留。');
      }
      final String chinese = await _translateRegeneratedLine(
        english: english,
        settings: settings,
      );
      final PlayerSubtitleLine regenerated = PlayerSubtitleLine(
        startTime: currentLine.startTime,
        english: english,
        chinese: chinese,
        startMs: currentLine.startMs,
        endMs: currentLine.endMs,
        words: words,
      );
      _validateFinalResult(
        jsonEncode(<String, Object?>{
          'version': 1,
          'lines': <Object?>[_lineToJson(regenerated)],
        }),
      );

      final String? cached = await cache.read(
        episodeId: episodeId,
        videoPath: videoPath,
      );
      final Map<String, dynamic> decoded = cached == null
          ? <String, dynamic>{'version': 1, 'language': 'en'}
          : Map<String, dynamic>.from(
              jsonDecode(cached) as Map<String, dynamic>,
            );
      final List<PlayerSubtitleLine> updatedLines = List<PlayerSubtitleLine>.of(
        currentLines,
      )..[lineIndex] = regenerated;
      decoded['lines'] = updatedLines.map(_lineToJson).toList(growable: false);
      final String raw = const JsonEncoder.withIndent('  ').convert(decoded);
      await cache.write(
        episodeId: episodeId,
        videoPath: videoPath,
        content: raw,
        settings: settings,
        referenceSignature: referenceSignature,
      );
      return AsrRegeneratedLineResult(line: regenerated, raw: raw);
    } finally {
      service.deleteTemporaryAudioChunks(chunks);
      _activeJobs.remove(jobKey);
    }
  }

  Future<String> run({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    List<PlayerSubtitleLine> referenceSubtitleLines =
        const <PlayerSubtitleLine>[],
    String? referenceSignatureOverride,
    bool forceRegenerate = false,
    AsrProgressCallback? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final File video = File(videoPath);
    if (!video.existsSync()) {
      throw StateError('missing-video-file');
    }
    final List<PlayerSubtitleLine> usableReferenceLines =
        usableReferenceSubtitles(referenceSubtitleLines);

    final String jobKey = _jobKey(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    if (!_activeJobs.add(jobKey)) {
      throw const AsrSubtitleGenerationException('这个视频的 AI 字幕正在生成，请等待当前任务完成。');
    }
    List<AsrAudioChunk> chunks = const <AsrAudioChunk>[];
    try {
      cancellationToken?.throwIfCancelled();
      if (forceRegenerate) {
        final Directory previousJob = await jobDirectory(
          episodeId: episodeId,
          videoPath: videoPath,
          settings: settings,
        );
        if (previousJob.existsSync()) {
          await previousJob.delete(recursive: true);
        }
      }
      try {
        chunks = await service.prepareAudioChunks(video);
      } catch (_) {
        cancellationToken?.throwIfCancelled();
        if (usableReferenceLines.isEmpty) rethrow;
      }
      cancellationToken?.throwIfCancelled();
      return await _runPrepared(
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        chunks: chunks,
        referenceSubtitleLines: usableReferenceLines,
        referenceSignature: referenceSignatureOverride?.isNotEmpty ?? false
            ? referenceSignatureOverride!
            : subtitleReferenceSignature(usableReferenceLines),
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    } finally {
      service.deleteTemporaryAudioChunks(chunks);
      _activeJobs.remove(jobKey);
    }
  }

  Future<String> _runPrepared({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    required List<AsrAudioChunk> chunks,
    required List<PlayerSubtitleLine> referenceSubtitleLines,
    required String referenceSignature,
    AsrProgressCallback? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final Directory jobDir = await jobDirectory(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    final Directory chunksDir = Directory(
      '${jobDir.path}${Platform.pathSeparator}chunks',
    );
    await chunksDir.create(recursive: true);
    final _SubtitleQualityReport report = _SubtitleQualityReport(
      settings.asrProvider,
    );

    final int totalMs = _estimatedTotalMs(chunks);
    await _writeJob(
      jobDir: jobDir,
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
      totalChunks: chunks.length,
      status: 'running',
      error: '',
    );
    int completed = 0;
    onProgress?.call(
      AsrSubtitleProgress(
        completedChunks: completed,
        totalChunks: chunks.length,
        currentMs: 0,
        totalMs: totalMs,
      ),
    );

    try {
      for (int index = 0; index < chunks.length; index += 1) {
        cancellationToken?.throwIfCancelled();
        final File chunkFile = File(
          '${chunksDir.path}${Platform.pathSeparator}${index.toString().padLeft(5, '0')}.json',
        );
        await _loadOrTranscribeValidChunk(
          chunkFile: chunkFile,
          chunk: chunks[index],
          chunkEndMs: index + 1 < chunks.length
              ? chunks[index + 1].offsetMs
              : chunks[index].offsetMs + 58000,
          settings: settings,
          sourceChunk: index,
          report: report,
          allowReferenceFallback: referenceSubtitleLines.isNotEmpty,
          cancellationToken: cancellationToken,
        );
        final Object? decoded = jsonDecode(await chunkFile.readAsString());
        final List<Map<String, Object?>> chunkLines =
            decoded is Map<String, dynamic>
            ? (decoded['lines'] as List<dynamic>? ?? const <dynamic>[])
                  .whereType<Map<String, dynamic>>()
                  .map(Map<String, Object?>.from)
                  .toList(growable: false)
            : const <Map<String, Object?>>[];
        report.addChunk(
          sourceChunk: index,
          startOffsetMs: chunks[index].offsetMs,
          endOffsetMs: index + 1 < chunks.length
              ? chunks[index + 1].offsetMs
              : chunks[index].offsetMs + 58000,
          lines: chunkLines,
        );
        completed += 1;
        onProgress?.call(
          AsrSubtitleProgress(
            completedChunks: completed,
            totalChunks: chunks.length,
            currentMs: await _currentMs(chunkFile, chunks[index].offsetMs),
            totalMs: totalMs,
            previewText: await _previewText(chunkFile),
          ),
        );
      }
    } catch (error) {
      await report.write(jobDir, 'FAILED');
      await _writeJob(
        jobDir: jobDir,
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        totalChunks: chunks.length,
        status: 'failed',
        error: error.toString(),
      );
      rethrow;
    }

    String raw = await _mergeChunks(chunksDir, chunks.length, report: report);
    if (referenceSubtitleLines.isNotEmpty) {
      final bool hasRecognizedWords = parseSubtitleLines(
        raw,
      ).any((PlayerSubtitleLine line) => line.words.isNotEmpty);
      raw = _calibrateWithReference(raw, referenceSubtitleLines);
      if (report.usedReferenceFallback || !hasRecognizedWords) {
        raw = _addTimingWarning(raw);
      }
    }
    late final String completedRaw;
    try {
      final String translatedRaw = await _addChineseTranslations(
        raw: raw,
        settings: settings,
        jobDir: jobDir,
        cancellationToken: cancellationToken,
        onProgress: onProgress,
        totalMs: totalMs,
      );
      completedRaw = _repairFinalWordTimelines(translatedRaw, report: report);
    } catch (error) {
      // 取消失败要如实抛出，交回 UI 处理。
      cancellationToken?.throwIfCancelled();
      // 翻译阶段出问题不应让整个任务作废。
      //
      // 此时语音识别已经完成、英文词级字幕是完好的，属于「可用但缺中文」。
      // 原实现会直接 FAILED 并 rethrow，用户连英文字幕都拿不到，
      // 表现为「字幕一直生成不出来」—— 代价远大于少一层中文。
      // 因此降级：保留英文结果、附上警告，让用户先能用，之后再补翻译。
      // （重试成本也低：断点续传会复用已识别分片，只补缺的中文。）
      final String warning =
          '英文词级字幕已生成，但中文翻译阶段出错：${_errorMessage(error)}。'
          '可以先使用英文字幕；稍后重新生成即可补上中文，'
          '已识别的内容会被复用。';
      try {
        final Map<String, dynamic> decoded =
            jsonDecode(raw) as Map<String, dynamic>;
        decoded['translationWarning'] = warning;
        completedRaw = _repairFinalWordTimelines(
          const JsonEncoder.withIndent('  ').convert(decoded),
          report: report,
        );
      } catch (_) {
        // 连解析 raw 都失败才真正作废。
        await report.write(jobDir, 'FAILED');
        await _writeJob(
          jobDir: jobDir,
          episodeId: episodeId,
          videoPath: videoPath,
          settings: settings,
          totalChunks: chunks.length,
          status: 'failed',
          error: error.toString(),
        );
        rethrow;
      }
    }
    final File part = File(
      '${jobDir.path}${Platform.pathSeparator}final.words.json.part',
    );
    await part.writeAsString(completedRaw);
    try {
      _validateFinalResult(
        completedRaw,
        allowLineOverlap: referenceSubtitleLines.isNotEmpty,
      );
    } catch (error) {
      await report.write(jobDir, 'FAILED');
      await chunksDir.delete(recursive: true);
      await _writeJob(
        jobDir: jobDir,
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        totalChunks: chunks.length,
        status: 'failed',
        error: error.toString(),
      );
      rethrow;
    }
    await cache.write(
      episodeId: episodeId,
      videoPath: videoPath,
      content: completedRaw,
      settings: settings,
      referenceSignature: referenceSignature.isEmpty
          ? null
          : referenceSignature,
    );
    await _writeJob(
      jobDir: jobDir,
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
      totalChunks: chunks.length,
      status: 'completed',
      error: '',
    );
    await report.write(jobDir, 'PASS');
    return completedRaw;
  }

  String _calibrateWithReference(
    String raw,
    List<PlayerSubtitleLine> referenceSubtitleLines,
  ) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final SubtitleWordAlignmentResult aligned = alignReferenceSubtitles(
      reference: referenceSubtitleLines,
      recognition: parseSubtitleLines(raw),
    );
    decoded['referenceLines'] = usableReferenceSubtitles(
      referenceSubtitleLines,
    ).map(_lineToJson).toList(growable: false);
    decoded['lines'] = aligned.lines
        .map(
          (PlayerSubtitleLine line) => <String, Object?>{
            'startMs': line.startMs,
            'endMs': line.endMs,
            'english': line.english,
            'chinese': line.chinese,
            'words': line.words
                .map(
                  (PlayerSubtitleWord word) => <String, Object?>{
                    'text': word.text,
                    'startMs': word.startMs,
                    'endMs': word.endMs,
                    if (word.confidence != null) 'confidence': word.confidence,
                  },
                )
                .toList(growable: false),
          },
        )
        .toList(growable: false);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  String _addTimingWarning(String raw) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    decoded['timingWarning'] = '已使用原字幕保证正文完整；部分单词时间为本地估算，联网后重新生成可提高逐词同步精度。';
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  Future<String> _addChineseTranslations({
    required String raw,
    required LearningSettingsState settings,
    required Directory jobDir,
    AsrSubtitleCancellationToken? cancellationToken,
    AsrProgressCallback? onProgress,
    int? totalMs,
  }) async {
    if (!settings.generateBilingualAsrSubtitles) {
      return raw;
    }

    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    final bool needsTranslation = lines.whereType<Map<String, dynamic>>().any(
      (Map<String, dynamic> line) =>
          (line['chinese'] as String? ?? '').trim().isEmpty &&
          (line['english'] as String? ?? '').trim().isNotEmpty,
    );
    if (!needsTranslation) return raw;
    final String? configurationError = _bilingualConfigurationError(settings);
    if (configurationError != null) {
      decoded['translationWarning'] = configurationError;
      return const JsonEncoder.withIndent('  ').convert(decoded);
    }
    final File checkpoint = File(
      '${jobDir.path}${Platform.pathSeparator}translations.json',
    );
    final String signature = _translationSignature(settings);
    final Map<String, String> translations = await _loadTranslations(
      checkpoint,
      signature,
    );
    // 翻译流程。
    //
    // 历史问题（两个都已修）：
    //   1) 任何一句失败就 break，后续所有句子永远没有中文
    //      —— 表现为「前十几分钟正常，之后只有英文」
    //   2) 逐句各发一次请求，长字幕动辄数百次调用，又慢又容易触发限流，
    //      个别请求挂起还会拖住整个任务
    //
    // 现在的策略：
    //   1) 先按批次打包翻译（AI 类接口一次可翻多句），500 句约降到 25 次请求
    //   2) 某批失败则回退到逐句翻译，保证正确性
    //   3) 仍失败的句子跳过、继续后面的句子，不再整段放弃
    //   4) 成功的句子立即落盘缓存，重试时只补缺的部分
    int untranslated = 0;
    Object? lastTranslationError;

    // 收集待翻译的句子（跳过已缓存与已有中文的）。
    final List<Map<String, dynamic>> pending = <Map<String, dynamic>>[];
    final List<String> pendingEnglish = <String>[];
    for (final dynamic line in lines) {
      if (line is! Map<String, dynamic>) continue;
      if ((line['chinese'] as String? ?? '').trim().isNotEmpty) continue;
      final String english = (line['english'] as String? ?? '').trim();
      if (english.isEmpty) continue;
      final String key = _translationLineKey(line, english);
      final String? cached = translations[key];
      if (cached != null) {
        // 命中缓存：直接复用，不发请求。
        line['chinese'] = cached;
        continue;
      }
      pending.add(line);
      pendingEnglish.add(english);
    }

    for (int offset = 0; offset < pending.length; offset += translationBatchSize) {
      cancellationToken?.throwIfCancelled();
      final int end = offset + translationBatchSize < pending.length
          ? offset + translationBatchSize
          : pending.length;
      final List<Map<String, dynamic>> batchLines = pending.sublist(offset, end);
      final List<String> batchEnglish = pendingEnglish.sublist(offset, end);

      // 批量尝试。
      List<String?>? batchResult;
      if (batchEnglish.length > 1) {
        batchResult = await wordLookupService.translateSentences(
          sentences: batchEnglish,
          settings: settings,
          onError: (Object error) => lastTranslationError = error,
        );
        cancellationToken?.throwIfCancelled();
      }

      for (int i = 0; i < batchLines.length; i += 1) {
        cancellationToken?.throwIfCancelled();
        final Map<String, dynamic> line = batchLines[i];
        final String english = batchEnglish[i];
        final String key = _translationLineKey(line, english);

        String? chinese = batchResult != null && i < batchResult.length
            ? batchResult[i]
            : null;
        if (chinese == null || chinese.trim().isEmpty) {
          // 批量没给结果（或该句缺失）时回退到逐句。
          chinese = await _translateOnce(
            english: english,
            settings: settings,
            cancellationToken: cancellationToken,
            onError: (Object error) => lastTranslationError = error,
          );
        }

        if (chinese == null || chinese.trim().isEmpty) {
          untranslated += 1;
          continue;
        }
        line['chinese'] = chinese.trim();
        translations[key] = chinese.trim();
        await _writeJsonAtomically(checkpoint, <String, Object?>{
          'version': 1,
          'signature': signature,
          'translations': translations,
        });
      }

      // 上报翻译进度。
      //
      // 这一步很关键：转写结束后翻译可能还要跑数分钟，
      // 若不给任何反馈，用户会以为程序卡死了（进度停在转写的最后一帧）。
      onProgress?.call(
        AsrSubtitleProgress(
          completedChunks: end,
          totalChunks: pending.length,
          // 用预览文案区分「转写中」与「翻译中」。
          previewText: '正在翻译字幕 $end/${pending.length} 句',
        ),
      );

      // 批次之间留出间隔，避免把第三方接口打到限流。
      if (end < pending.length) {
        await Future<void>.delayed(translationRequestInterval);
      }
    }

    if (untranslated > 0) {
      final String reason = lastTranslationError == null
          ? '翻译服务未返回结果'
          : _errorMessage(lastTranslationError!);
      const String tail =
          '英文词级字幕已生成并可用。'
          '通常是翻译接口限流或余额不足，稍后重新生成即可补上，'
          '已翻译的部分会被复用。';
      decoded['translationWarning'] =
          '有 $untranslated 句中文翻译未完成（$reason）。 $tail';
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  /// 单句翻译（每次运行只尝试一次）。
  ///
  /// 刻意不做内部重试：第三方翻译接口在长字幕场景下失败多半是限流，
  /// 当场反复重试只会加重限流。失败交给「重新生成」时的断点续传处理 ——
  /// 已成功的句子走缓存，只有未完成的句子会被重新请求，
  /// 因此用户稍后重试的成本很低。
  Future<String?> _translateOnce({
    required String english,
    required LearningSettingsState settings,
    required void Function(Object error) onError,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    // 错误上报只用于诊断，绝不能因为回调本身出问题而让整个字幕任务失败。
    void report(Object error) {
      try {
        onError(error);
      } catch (_) {
        // 忽略上报过程中的任何异常。
      }
    }

    cancellationToken?.throwIfCancelled();
    try {
      // 走真实服务时把底层错误原样上报（例如阿里云的 Code/Message、
      // HTTP 状态码），否则用户只能看到「翻译未完成」而无法判断原因。
      // 测试注入的 translateSentence 没有 onError 参数，故分流处理。
      final AsrSentenceTranslator? injected = translateSentence;
      final String? result = injected != null
          ? await injected(sentence: english, settings: settings).timeout(
              const Duration(seconds: 45),
            )
          : await wordLookupService
                .translateSentence(
                  sentence: english,
                  settings: settings,
                  onError: report,
                )
                .timeout(const Duration(seconds: 45));
      if (result != null && result.trim().isNotEmpty) {
        return result.trim();
      }
      report(StateError('翻译服务返回空结果'));
    } catch (error) {
      report(error);
    }
    return null;
  }

  String? _bilingualConfigurationError(LearningSettingsState settings) {
    if (!settings.generateBilingualAsrSubtitles || translateSentence != null) {
      return null;
    }
    if (settings.translationApiKey.trim().isEmpty) {
      return '无法生成双语字幕：请先在“翻译”中填写 API Key。';
    }
    if ((settings.translationProvider == '百度翻译' ||
            settings.translationProvider == '阿里云翻译') &&
        settings.translationApiSecret.trim().isEmpty) {
      return '无法生成双语字幕：${settings.translationProvider} 还需要填写 Secret。';
    }
    if (settings.translationBaseUrl.trim().isEmpty) {
      return '无法生成双语字幕：请在“翻译”中填写服务地址。';
    }
    if (_isAiTranslationProvider(settings.translationProvider) &&
        settings.translationModel.trim().isEmpty) {
      return '无法生成双语字幕：请在“翻译”中填写模型名称。';
    }
    return null;
  }

  bool _isAiTranslationProvider(String provider) {
    return provider == 'OpenAI' ||
        provider == 'OpenRouter' ||
        provider == 'SiliconFlow' ||
        provider == 'DeepSeek';
  }

  Future<Directory> jobDirectory({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
  }) async {
    final Directory support = supportDirectory == null
        ? await getApplicationSupportDirectory()
        : await supportDirectory!();
    final String key = _jobKey(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    return Directory(
      '${support.path}${Platform.pathSeparator}asr_subtitles'
      '${Platform.pathSeparator}${_safe(episodeId)}'
      '${Platform.pathSeparator}jobs'
      '${Platform.pathSeparator}$key',
    );
  }

  Future<AsrSubtitleRepairSummary> readRepairSummary({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
  }) async {
    final Directory jobDir = await jobDirectory(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    final File reportFile = File(
      '${jobDir.path}${Platform.pathSeparator}subtitle_quality_report.json',
    );
    if (!reportFile.existsSync()) {
      return const AsrSubtitleRepairSummary(0);
    }
    try {
      final Object? decoded = jsonDecode(await reportFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const AsrSubtitleRepairSummary(0);
      }
      final int count =
          decoded['repairCount'] as int? ??
          (decoded['wordFix'] as int? ?? 0) +
              (decoded['wordDeleted'] as int? ?? 0) +
              (decoded['chunkBoundaryFix'] as int? ?? 0);
      return AsrSubtitleRepairSummary(count);
    } catch (_) {
      return const AsrSubtitleRepairSummary(0);
    }
  }

  Future<Map<String, Object?>> _transcribe({
    required AsrAudioChunk chunk,
    required LearningSettingsState settings,
  }) async {
    if (cloudTranscribeChunk != null) {
      return cloudTranscribeChunk!(chunk: chunk, settings: settings);
    }
    return service.generateCloudChunk(chunk: chunk, settings: settings);
  }

  List<PlayerSubtitleWord> _wordsForCurrentLine(
    List<Map<String, Object?>> recognizedLines,
    PlayerSubtitleLine currentLine,
  ) {
    final String raw = jsonEncode(<String, Object?>{
      'version': 1,
      'lines': recognizedLines,
    });
    final List<PlayerSubtitleWord> candidates =
        parseSubtitleLines(raw)
            .expand((PlayerSubtitleLine line) => line.words)
            .where((PlayerSubtitleWord word) {
              final int midpoint =
                  word.startMs + ((word.endMs - word.startMs) ~/ 2);
              return midpoint >= currentLine.startMs &&
                  midpoint <= currentLine.endMs;
            })
            .toList(growable: false)
          ..sort(
            (PlayerSubtitleWord a, PlayerSubtitleWord b) =>
                a.startMs.compareTo(b.startMs),
          );
    final List<PlayerSubtitleWord> result = <PlayerSubtitleWord>[];
    for (final PlayerSubtitleWord word in candidates) {
      final int startMs = word.startMs.clamp(
        currentLine.startMs,
        currentLine.endMs,
      );
      final int endMs = word.endMs.clamp(
        currentLine.startMs,
        currentLine.endMs,
      );
      final int safeStartMs = result.isEmpty
          ? startMs
          : startMs < result.last.endMs
          ? result.last.endMs
          : startMs;
      if (endMs <= safeStartMs) continue;
      result.add(
        PlayerSubtitleWord(
          text: word.text,
          startMs: safeStartMs,
          endMs: endMs,
          confidence: word.confidence,
        ),
      );
    }
    return result;
  }

  Future<String> _translateRegeneratedLine({
    required String english,
    required LearningSettingsState settings,
  }) async {
    if (!settings.generateBilingualAsrSubtitles) return '';
    final String? configurationError = _bilingualConfigurationError(settings);
    if (configurationError != null) {
      throw AsrSubtitleGenerationException('$configurationError 原句已保留。');
    }
    Object? lastError;
    for (int attempt = 0; attempt < 2; attempt += 1) {
      try {
        final String? translated =
            await (translateSentence ??
                    const WordLookupService().translateSentence)(
                  sentence: english,
                  settings: settings,
                )
                .timeout(const Duration(seconds: 45));
        if (translated != null && translated.trim().isNotEmpty) {
          return translated.trim();
        }
        lastError = StateError('empty-translation');
      } catch (error) {
        lastError = error;
      }
    }
    throw AsrSubtitleGenerationException(
      '当前句英文已识别，但中文翻译失败，原句已保留：${_errorMessage(lastError ?? 'unknown-error')}',
    );
  }

  Map<String, Object?> _lineToJson(PlayerSubtitleLine line) {
    return <String, Object?>{
      'startMs': line.startMs,
      'endMs': line.endMs,
      'english': line.english,
      'chinese': line.chinese,
      'words': line.words
          .map(
            (PlayerSubtitleWord word) => <String, Object?>{
              'text': word.text,
              'startMs': word.startMs,
              'endMs': word.endMs,
              if (word.confidence != null) 'confidence': word.confidence,
            },
          )
          .toList(growable: false),
    };
  }

  Future<void> _loadOrTranscribeValidChunk({
    required File chunkFile,
    required AsrAudioChunk chunk,
    required int chunkEndMs,
    required LearningSettingsState settings,
    required int sourceChunk,
    required _SubtitleQualityReport report,
    required bool allowReferenceFallback,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    for (int attempt = 0; attempt < 2; attempt += 1) {
      try {
        cancellationToken?.throwIfCancelled();
        late final Map<String, Object?> chunkJson;
        if (attempt == 0 && chunkFile.existsSync()) {
          final Object? decoded = jsonDecode(await chunkFile.readAsString());
          if (decoded is! Map<String, dynamic>) {
            throw StateError('invalid-asr-chunk');
          }
          chunkJson = Map<String, Object?>.from(decoded);
        } else {
          chunkJson = await _transcribe(chunk: chunk, settings: settings)
              .timeout(
                const Duration(minutes: 20),
                onTimeout: () => throw TimeoutException('AI 字幕生成超时，请重试或换更小模型。'),
              );
        }
        final Map<String, Object?> normalized = _normalizeChunkTimeline(
          chunkJson,
          chunkStartMs: chunk.offsetMs,
          chunkEndMs: chunkEndMs,
          sourceChunk: sourceChunk,
          report: report,
        );
        final Object? lines = normalized['lines'];
        if (lines is! List<dynamic> || lines.isNotEmpty) {
          _validateFinalResult(jsonEncode(normalized));
        }
        await chunkFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(normalized),
        );
        return;
      } catch (error) {
        cancellationToken?.throwIfCancelled();
        if (chunkFile.existsSync()) {
          await chunkFile.delete();
        }
        if (attempt == 1) {
          // 「这段音频里没有识别到语音」不是错误。
          // 影视资源里静音段、纯音乐段、无对白段很常见，阿里云对这类分片
          // 返回 FAILED + SUCCESS_WITH_NO_VALID_FRAGMENT。
          // 若把它当成致命错误，整个字幕生成会在任意一个静音段中断
          // （实测：一部剧会在第 41 段左右挂掉）。
          // 这里按「空段落」落盘并继续处理后续分片。
          if (_isNoSpeechFragment(error)) {
            report
              ..repairCount += 1
              ..anomalies.add(<String, Object?>{
                'kind': 'silentChunk',
                'sourceChunk': sourceChunk,
              });
            await chunkFile.writeAsString(
              const JsonEncoder.withIndent(' ').convert(<String, Object?>{
                'version': 1,
                'language': 'en',
                'lines': const <Object?>[],
              }),
            );
            return;
          }
          if (allowReferenceFallback) {
            report
              ..repairCount += 1
              ..usedReferenceFallback = true
              ..anomalies.add(<String, Object?>{
                'kind': 'referenceFallback',
                'sourceChunk': sourceChunk,
                'errorType': error.runtimeType.toString(),
              });
            await chunkFile.writeAsString(
              const JsonEncoder.withIndent(' ').convert(<String, Object?>{
                'version': 1,
                'language': 'en',
                'lines': const <Object?>[],
              }),
            );
            return;
          }
          throw StateError(
            '第 ${sourceChunk + 1} 段处理失败：${_errorMessage(error)}',
          );
        }
      }
    }
  }

  void _validateFinalResult(String raw, {bool allowLineOverlap = false}) {
    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    if (lines.isEmpty) {
      throw StateError('字幕检查失败：没有识别到有效字幕。');
    }

    int previousEndMs = -1;
    for (int index = 0; index < lines.length; index += 1) {
      final PlayerSubtitleLine line = lines[index];
      final String location = '第 ${index + 1} 句';
      if (line.english.trim().isEmpty) {
        throw StateError('字幕检查失败：$location 存在空字幕。');
      }
      if (line.endMs <= line.startMs) {
        throw StateError('字幕检查失败：$location 存在无效时间轴。');
      }
      if (line.words.isEmpty) {
        throw StateError('字幕检查失败：$location 未返回词级时间戳，无法精准跟读单词。');
      }
      final int expectedWordCount = _wordCount(line.english);
      final int timedWordCount = line.words.fold<int>(
        0,
        (int count, PlayerSubtitleWord word) => count + _wordCount(word.text),
      );
      if (expectedWordCount > 0 && timedWordCount < expectedWordCount) {
        throw StateError('字幕检查失败：$location 不是每个英文单词都有词级时间戳。');
      }
      if (_comparableText(line.english) !=
          _comparableText(
            line.words.map((PlayerSubtitleWord word) => word.text).join(' '),
          )) {
        throw StateError('字幕检查失败：$location 的正文与词级时间戳文本不一致。');
      }
      int previousWordEndMs = -1;
      for (final PlayerSubtitleWord word in line.words) {
        if (previousWordEndMs >= 0 && word.startMs < previousWordEndMs) {
          throw StateError('字幕检查失败：$location 的单词时间轴乱序或重叠。');
        }
        previousWordEndMs = word.endMs;
      }
      if (!allowLineOverlap &&
          previousEndMs >= 0 &&
          line.startMs < previousEndMs - 250) {
        throw StateError('字幕检查失败：$location 时间轴乱序或重叠过多。');
      }
      previousEndMs = line.endMs;
    }
  }

  String _repairFinalWordTimelines(
    String raw, {
    required _SubtitleQualityReport report,
  }) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    for (final Object? item in lines) {
      if (item is! Map<String, dynamic>) continue;
      final String english = (item['english'] as String? ?? '').trim();
      final int startMs = _timelineMs(item['startMs']);
      final int endMs = _timelineMs(item['endMs']);
      if (english.isEmpty || endMs <= startMs) continue;
      final List<Map<String, Object?>> words =
          (item['words'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(Map<String, Object?>.from)
              .toList(growable: false);
      final int expectedWordCount = _wordCount(english);
      final int timedWordCount = words.fold<int>(
        0,
        (int count, Map<String, Object?> word) =>
            count + _wordCount(word['text'] as String? ?? ''),
      );
      final bool hasValidCoverage =
          words.isNotEmpty &&
          timedWordCount >= expectedWordCount &&
          _comparableText(english) ==
              _comparableText(
                words
                    .map((Map<String, Object?> word) => word['text'] ?? '')
                    .join(' '),
              ) &&
          _hasValidWordTimeline(words) &&
          words.every(
            (Map<String, Object?> word) =>
                _timelineMs(word['startMs']) >= startMs &&
                _timelineMs(word['endMs']) <= endMs,
          );
      if (hasValidCoverage) continue;
      final List<Map<String, Object?>> repaired = _synthesizeWords(
        english,
        startMs,
        endMs,
      );
      if (repaired.isEmpty) continue;
      item['words'] = repaired;
      report
        ..wordFix += repaired.length
        ..repairCount += 1;
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  int _wordCount(String text) {
    return RegExp("[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?").allMatches(text).length;
  }

  String _comparableText(String text) => RegExp(
    '[A-Za-z0-9]+',
  ).allMatches(text).map((Match match) => match.group(0)!.toLowerCase()).join();

  Future<String> _mergeChunks(
    Directory chunksDir,
    int totalChunks, {
    required _SubtitleQualityReport report,
  }) async {
    final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
    final Map<String, String> glossary = <String, String>{};
    for (int index = 0; index < totalChunks; index += 1) {
      final File chunkFile = File(
        '${chunksDir.path}${Platform.pathSeparator}${index.toString().padLeft(5, '0')}.json',
      );
      final Object? decoded = jsonDecode(await chunkFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw StateError('invalid-asr-chunk');
      }
      lines.addAll(
        (decoded['lines'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (Map<String, dynamic> line) => <String, Object?>{
                ...line,
                '_sourceChunk': index,
              },
            ),
      );
      for (final Object? item
          in decoded['glossary'] as List<dynamic>? ?? const <dynamic>[]) {
        if (item is! Map<String, dynamic>) continue;
        final String word = (item['word'] as String? ?? '')
            .trim()
            .toLowerCase();
        final String definition = (item['definitionCn'] as String? ?? '')
            .trim();
        if (RegExp(r'^[a-z]{2,}$').hasMatch(word) && definition.isNotEmpty) {
          glossary.putIfAbsent(word, () => definition);
        }
      }
    }
    final List<Map<String, Object?>> boundaryNormalized =
        _normalizeChunkBoundaries(lines, report: report);
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'version': 1,
      'language': '',
      'lines': _normalizeTimeline(
        boundaryNormalized,
        report: report,
      ).map(_withoutSourceChunk).toList(growable: false),
      'glossary': glossary.entries
          .map(
            (MapEntry<String, String> entry) => <String, String>{
              'word': entry.key,
              'definitionCn': entry.value,
            },
          )
          .toList(growable: false),
    });
  }

  List<Map<String, Object?>> _normalizeTimeline(
    List<Map<String, Object?>> lines, {
    _SubtitleQualityReport? report,
  }) {
    final List<Map<String, Object?>> sorted =
        lines.map(Map<String, Object?>.from).toList(growable: false)..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              _timelineMs(a['startMs']).compareTo(_timelineMs(b['startMs'])),
        );
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (Map<String, Object?> line in sorted) {
      if (result.isEmpty) {
        result.add(line);
        continue;
      }
      final Map<String, Object?> previous = result.last;
      if (_sameOverlappingLine(previous, line)) {
        continue;
      }
      final int overlapMs =
          _timelineMs(previous['endMs']) - _timelineMs(line['startMs']);
      if (overlapMs > 0) {
        final int previousSourceChunk = _sourceChunk(previous);
        final int currentSourceChunk = _sourceChunk(line);
        report?.addOverlap(
          kind: 'sentence',
          previousText: previous['english'] as String? ?? '',
          previousStart: _timelineMs(previous['startMs']),
          previousEnd: _timelineMs(previous['endMs']),
          currentText: line['english'] as String? ?? '',
          currentStart: _timelineMs(line['startMs']),
          currentEnd: _timelineMs(line['endMs']),
          overlapMs: overlapMs,
          sourceChunk: currentSourceChunk,
          previousSourceChunk: previousSourceChunk,
        );
      }
      if (overlapMs > 0) {
        report?.repairCount += 1;
        if (overlapMs <= _repairableOverlapMs) {
          line = _shiftLine(line, overlapMs);
        } else if (_trimLineAtBoundary(
          previous,
          _timelineMs(line['startMs']),
        )) {
          report?.wordFix += 1;
        } else {
          line = _shiftLine(line, overlapMs);
        }
        if (_sourceChunk(previous) != _sourceChunk(line)) {
          report?.chunkBoundaryFix += 1;
        }
      }
      result.add(line);
    }
    return result;
  }

  List<Map<String, Object?>> _normalizeChunkBoundaries(
    List<Map<String, Object?>> lines, {
    required _SubtitleQualityReport report,
  }) {
    final Map<int, List<Map<String, Object?>>> byChunk =
        <int, List<Map<String, Object?>>>{};
    for (final Map<String, Object?> line in lines) {
      byChunk
          .putIfAbsent(_sourceChunk(line), () => <Map<String, Object?>>[])
          .add(Map<String, Object?>.from(line));
    }
    Map<String, Object?>? previousLastWord;
    int previousChunk = -1;
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final int sourceChunk in byChunk.keys.toList()..sort()) {
      List<Map<String, Object?>> chunkLines = byChunk[sourceChunk]!
        ..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              _timelineMs(a['startMs']).compareTo(_timelineMs(b['startMs'])),
        );
      final Map<String, Object?>? firstWord = _firstWord(chunkLines);
      if (previousLastWord != null && firstWord != null) {
        final int overlapMs =
            _timelineMs(previousLastWord['endMs']) -
            _timelineMs(firstWord['startMs']);
        if (overlapMs > 0) {
          report.addOverlap(
            kind: 'chunkBoundary',
            previousText: previousLastWord['text'] as String? ?? '',
            previousStart: _timelineMs(previousLastWord['startMs']),
            previousEnd: _timelineMs(previousLastWord['endMs']),
            currentText: firstWord['text'] as String? ?? '',
            currentStart: _timelineMs(firstWord['startMs']),
            currentEnd: _timelineMs(firstWord['endMs']),
            overlapMs: overlapMs,
            sourceChunk: sourceChunk,
            previousSourceChunk: previousChunk,
          );
          if (overlapMs <= _repairableOverlapMs) {
            chunkLines = chunkLines
                .map((Map<String, Object?> line) => _shiftLine(line, overlapMs))
                .toList(growable: false);
            report
              ..chunkBoundaryFix += 1
              ..repairCount += 1;
          } else if (_trimPreviousLineAtBoundary(
            result,
            _timelineMs(firstWord['startMs']),
          )) {
            report
              ..chunkBoundaryFix += 1
              ..repairCount += 1;
          }
        }
      }
      final Map<String, Object?>? lastWord = _lastWord(chunkLines);
      if (lastWord != null) {
        previousLastWord = lastWord;
        previousChunk = sourceChunk;
      }
      result.addAll(chunkLines);
    }
    return result;
  }

  bool _trimPreviousLineAtBoundary(
    List<Map<String, Object?>> lines,
    int boundaryMs,
  ) {
    for (int index = lines.length - 1; index >= 0; index -= 1) {
      final Map<String, Object?> line = lines[index];
      if (_lineWords(line).isEmpty) continue;
      return _trimLineAtBoundary(line, boundaryMs);
    }
    return false;
  }

  bool _trimLineAtBoundary(Map<String, Object?> line, int boundaryMs) {
    final List<Map<String, Object?>> words = _lineWords(line);
    if (words.isEmpty) return false;
    final Map<String, Object?> lastWord = words.last;
    if (_timelineMs(lastWord['startMs']) >= boundaryMs ||
        _timelineMs(lastWord['endMs']) <= boundaryMs) {
      return false;
    }
    lastWord['endMs'] = boundaryMs;
    line['words'] = words;
    line['endMs'] = boundaryMs;
    return true;
  }

  Map<String, Object?>? _firstWord(List<Map<String, Object?>> lines) {
    for (final Map<String, Object?> line in lines) {
      final List<Map<String, Object?>> words = _lineWords(line);
      if (words.isNotEmpty) return words.first;
    }
    return null;
  }

  Map<String, Object?>? _lastWord(List<Map<String, Object?>> lines) {
    for (final Map<String, Object?> line in lines.reversed) {
      final List<Map<String, Object?>> words = _lineWords(line);
      if (words.isNotEmpty) return words.last;
    }
    return null;
  }

  List<Map<String, Object?>> _lineWords(Map<String, Object?> line) =>
      (line['words'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Map<String, Object?>.from)
          .toList(growable: false);

  Map<String, Object?> _normalizeChunkTimeline(
    Map<String, Object?> chunk, {
    required int chunkStartMs,
    required int chunkEndMs,
    required int sourceChunk,
    required _SubtitleQualityReport report,
  }) {
    final List<Map<String, Object?>> lines =
        (chunk['lines'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (Map<String, dynamic> line) => <String, Object?>{
                ...line,
                '_sourceChunk': sourceChunk,
              },
            )
            .toList(growable: false);
    final List<Map<String, Object?>> constrained = _constrainChunkTimeline(
      lines,
      chunkStartMs: chunkStartMs,
      chunkEndMs: chunkEndMs,
      report: report,
    );
    final List<Map<String, Object?>> normalized = _normalizeWords(
      constrained,
      report: report,
    );
    return <String, Object?>{
      ...chunk,
      'lines': _normalizeTimeline(
        normalized,
        report: report,
      ).map(_withoutSourceChunk).toList(growable: false),
    };
  }

  List<Map<String, Object?>> _constrainChunkTimeline(
    List<Map<String, Object?>> lines, {
    required int chunkStartMs,
    required int chunkEndMs,
    required _SubtitleQualityReport report,
  }) {
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Map<String, Object?> original in lines) {
      bool repaired = false;
      final Map<String, Object?> line = Map<String, Object?>.from(original);
      final List<Map<String, Object?>> originalWords = _lineWords(line);
      final List<Map<String, Object?>> words = <Map<String, Object?>>[];
      for (final Map<String, Object?> originalWord in originalWords) {
        final int startMs = _timelineMs(originalWord['startMs']);
        final int endMs = _timelineMs(originalWord['endMs']);
        if (endMs <= chunkStartMs || startMs >= chunkEndMs) {
          report.wordDeleted += 1;
          repaired = true;
          continue;
        }
        final Map<String, Object?> word = Map<String, Object?>.from(
          originalWord,
        );
        word['startMs'] = startMs < chunkStartMs ? chunkStartMs : startMs;
        word['endMs'] = endMs > chunkEndMs ? chunkEndMs : endMs;
        repaired =
            repaired || word['startMs'] != startMs || word['endMs'] != endMs;
        if (_timelineMs(word['endMs']) > _timelineMs(word['startMs'])) {
          words.add(word);
        } else {
          report.wordDeleted += 1;
          repaired = true;
        }
      }
      if (words.length != originalWords.length) {
        words.clear();
      }
      if (words.isNotEmpty) {
        line['words'] = words;
        line['startMs'] = _timelineMs(words.first['startMs']);
        line['endMs'] = _timelineMs(words.last['endMs']);
      } else {
        line['words'] = const <Map<String, Object?>>[];
        int startMs = _timelineMs(line['startMs']);
        int endMs = _timelineMs(line['endMs']);
        if (startMs < chunkStartMs || startMs >= chunkEndMs) {
          startMs = chunkStartMs;
          repaired = true;
        }
        if (endMs <= startMs || endMs > chunkEndMs) {
          final int tokenCount = _wordCount(line['english'] as String? ?? '');
          final int fallbackEndMs =
              startMs + (tokenCount > 0 ? tokenCount * 400 : 1000);
          endMs = fallbackEndMs < chunkEndMs ? fallbackEndMs : chunkEndMs;
          repaired = true;
        }
        if (endMs <= startMs) continue;
        line['startMs'] = startMs;
        line['endMs'] = endMs;
      }
      if (repaired) report.repairCount += 1;
      result.add(line);
    }
    return result;
  }

  List<Map<String, Object?>> _normalizeWords(
    List<Map<String, Object?>> lines, {
    required _SubtitleQualityReport report,
  }) {
    final List<Map<String, Object?>> sorted =
        lines.map(Map<String, Object?>.from).toList(growable: false)..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              _timelineMs(a['startMs']).compareTo(_timelineMs(b['startMs'])),
        );
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Map<String, Object?> line in sorted) {
      if (result.isNotEmpty && _sameOverlappingLine(result.last, line)) {
        continue;
      }
      List<Map<String, Object?>> words =
          (line['words'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(Map<String, Object?>.from)
              .where(
                (Map<String, Object?> word) =>
                    _timelineMs(word['endMs']) > _timelineMs(word['startMs']),
              )
              .toList(growable: false)
            ..sort(
              (Map<String, Object?> a, Map<String, Object?> b) => _timelineMs(
                a['startMs'],
              ).compareTo(_timelineMs(b['startMs'])),
            );
      final int originalCount =
          (line['words'] as List<dynamic>? ?? const <dynamic>[]).length;
      report.wordDeleted += originalCount - words.length;
      final String english = line['english'] as String? ?? '';
      bool repaired = false;
      if (words.isEmpty ||
          _comparableText(english) !=
              _comparableText(
                words
                    .map((Map<String, Object?> word) => word['text'] ?? '')
                    .join(' '),
              )) {
        words = _synthesizeWords(
          english,
          _timelineMs(line['startMs']),
          _timelineMs(line['endMs']),
        );
        report.wordFix += words.length;
        repaired = true;
      }
      Map<String, Object?>? previousWord;
      for (final Map<String, Object?> word in words) {
        if (previousWord != null &&
            _timelineMs(word['startMs']) < _timelineMs(previousWord['endMs'])) {
          final int overlapMs =
              _timelineMs(previousWord['endMs']) - _timelineMs(word['startMs']);
          report.addOverlap(
            kind: 'word',
            previousText: previousWord['text'] as String? ?? '',
            previousStart: _timelineMs(previousWord['startMs']),
            previousEnd: _timelineMs(previousWord['endMs']),
            currentText: word['text'] as String? ?? '',
            currentStart: _timelineMs(word['startMs']),
            currentEnd: _timelineMs(word['endMs']),
            overlapMs: overlapMs,
            sourceChunk: _sourceChunk(line),
            previousSourceChunk: _sourceChunk(line),
          );
          final int currentStartMs = _timelineMs(word['startMs']);
          if (currentStartMs > _timelineMs(previousWord['startMs'])) {
            previousWord['endMs'] = currentStartMs;
          } else {
            final int latestEndMs =
                _timelineMs(previousWord['endMs']) > _timelineMs(word['endMs'])
                ? _timelineMs(previousWord['endMs'])
                : _timelineMs(word['endMs']);
            final int boundaryMs =
                _timelineMs(previousWord['startMs']) +
                ((latestEndMs - _timelineMs(previousWord['startMs'])) ~/ 2);
            previousWord['endMs'] = boundaryMs;
            word['startMs'] = boundaryMs;
          }
          report.wordFix += 1;
          repaired = true;
        }
        previousWord = word;
      }
      if (!_hasValidWordTimeline(words)) {
        words = _synthesizeWords(
          english,
          _timelineMs(line['startMs']),
          _timelineMs(line['endMs']),
        );
        report.wordFix += words.length;
        repaired = true;
      }
      if (words.isNotEmpty) {
        line['words'] = words;
        line['startMs'] = _timelineMs(words.first['startMs']);
        line['endMs'] = _timelineMs(words.last['endMs']);
      }
      if (repaired) report.repairCount += 1;
      result.add(line);
    }
    return result;
  }

  List<Map<String, Object?>> _synthesizeWords(
    String english,
    int startMs,
    int endMs,
  ) {
    final List<String> tokens = RegExp("[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?")
        .allMatches(english)
        .map((Match match) => match.group(0)!)
        .toList(growable: false);
    if (tokens.isEmpty || endMs <= startMs) {
      return const <Map<String, Object?>>[];
    }
    final int durationMs = endMs - startMs < tokens.length
        ? tokens.length
        : endMs - startMs;
    return <Map<String, Object?>>[
      for (int index = 0; index < tokens.length; index += 1)
        <String, Object?>{
          'text': tokens[index],
          'startMs': startMs + (durationMs * index ~/ tokens.length),
          'endMs': startMs + (durationMs * (index + 1) ~/ tokens.length),
        },
    ];
  }

  bool _hasValidWordTimeline(List<Map<String, Object?>> words) {
    int previousEndMs = -1;
    for (final Map<String, Object?> word in words) {
      final int startMs = _timelineMs(word['startMs']);
      final int endMs = _timelineMs(word['endMs']);
      if (endMs <= startMs || (previousEndMs >= 0 && startMs < previousEndMs)) {
        return false;
      }
      previousEndMs = endMs;
    }
    return true;
  }

  int _sourceChunk(Map<String, Object?> line) {
    final Object? value = line['_sourceChunk'];
    return value is int ? value : -1;
  }

  Map<String, Object?> _withoutSourceChunk(Map<String, Object?> line) =>
      <String, Object?>{
        for (final MapEntry<String, Object?> entry in line.entries)
          if (entry.key != '_sourceChunk') entry.key: entry.value,
      };

  bool _sameOverlappingLine(
    Map<String, Object?> previous,
    Map<String, Object?> current,
  ) {
    final String previousText = (previous['english'] as String? ?? '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    final String currentText = (current['english'] as String? ?? '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    return previousText.isNotEmpty &&
        previousText == currentText &&
        _timelineMs(current['startMs']) <= _timelineMs(previous['endMs']) &&
        _timelineMs(current['endMs']) >= _timelineMs(previous['startMs']);
  }

  Map<String, Object?> _shiftLine(Map<String, Object?> line, int offsetMs) {
    return <String, Object?>{
      ...line,
      'startMs': _timelineMs(line['startMs']) + offsetMs,
      'endMs': _timelineMs(line['endMs']) + offsetMs,
      'words': (line['words'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> word) => <String, Object?>{
              ...word,
              'startMs': _timelineMs(word['startMs']) + offsetMs,
              'endMs': _timelineMs(word['endMs']) + offsetMs,
            },
          )
          .toList(growable: false),
    };
  }

  int _timelineMs(Object? value) => value is num ? value.round() : -1;

  Future<String?> _previewText(File chunkFile) async {
    final Object? decoded = jsonDecode(await chunkFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    for (final Object? line in lines.reversed) {
      if (line is Map<String, dynamic>) {
        final String text = (line['english'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    return null;
  }

  Future<int> _currentMs(File chunkFile, int fallbackMs) async {
    final Object? decoded = jsonDecode(await chunkFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return fallbackMs;
    }
    int currentMs = fallbackMs;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    for (final Object? line in lines) {
      if (line is Map<String, dynamic>) {
        final int? endMs = line['endMs'] as int?;
        if (endMs != null && endMs > currentMs) {
          currentMs = endMs;
        }
      }
    }
    return currentMs;
  }

  int _estimatedTotalMs(List<AsrAudioChunk> chunks) {
    if (chunks.isEmpty) {
      return 0;
    }
    if (chunks.length == 1) {
      return chunks.first.offsetMs + 60000;
    }
    final int stepMs =
        chunks.last.offsetMs - chunks[chunks.length - 2].offsetMs;
    return chunks.last.offsetMs + stepMs;
  }

  Future<void> _writeJob({
    required Directory jobDir,
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    required int totalChunks,
    required String status,
    required String error,
  }) async {
    await jobDir.create(recursive: true);
    await File('${jobDir.path}${Platform.pathSeparator}job.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'version': 1,
        'episodeId': episodeId,
        'videoPath': videoPath,
        'provider': settings.asrProvider,
        'model': settings.asrModel,
        'chunkMs': 58000,
        'totalChunks': totalChunks,
        'status': status,
        'error': error,
      }),
    );
  }

  String _jobKey({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
  }) {
    final FileStat stat = File(videoPath).statSync();
    final String value =
        '$episodeId|${File(videoPath).absolute.path}|${stat.size}|'
        '${stat.modified.millisecondsSinceEpoch}|${settings.asrProvider}|'
        '${settings.asrBaseUrl}|${settings.asrModel}';
    return sha1.convert(utf8.encode(value)).toString();
  }

  String _translationSignature(LearningSettingsState settings) {
    final String value =
        '${settings.translationProvider}|${settings.translationBaseUrl}|'
        '${settings.translationModel}';
    return sha1.convert(utf8.encode(value)).toString();
  }

  String _translationLineKey(Map<String, dynamic> line, String english) {
    final String value = '${line['startMs']}|${line['endMs']}|$english';
    return sha1.convert(utf8.encode(value)).toString();
  }

  Future<Map<String, String>> _loadTranslations(
    File file,
    String signature,
  ) async {
    if (!file.existsSync()) return <String, String>{};
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['signature'] != signature ||
          decoded['translations'] is! Map<String, dynamic>) {
        return <String, String>{};
      }
      return (decoded['translations'] as Map<String, dynamic>).map(
        (String key, dynamic value) =>
            MapEntry<String, String>(key, value is String ? value : ''),
      )..removeWhere((String _, String value) => value.isEmpty);
    } catch (_) {
      await file.delete();
      return <String, String>{};
    }
  }

  Future<void> _writeJsonAtomically(
    File file,
    Map<String, Object?> value,
  ) async {
    final File part = File('${file.path}.part');
    try {
      await part.writeAsString(jsonEncode(value), flush: true);
      await part.rename(file.path);
    } finally {
      if (part.existsSync()) await part.delete();
    }
  }

  String _errorMessage(Object error) {
    if (error is StateError) return error.message;
    if (error is AsrSubtitleGenerationException) return error.message;
    return error.toString();
  }

  /// 判断错误是否表示「这段音频里没有语音」。
  ///
  /// 阿里云 ASR 对无语音分片返回 FAILED，message 为
  /// `SUCCESS_WITH_NO_VALID_FRAGMENT`（也有大小写/带前缀的变体）。
  /// 这类分片应当跳过而不是让整个任务失败。
  bool _isNoSpeechFragment(Object error) {
    final String message = _errorMessage(error).toUpperCase();
    return message.contains('SUCCESS_WITH_NO_VALID_FRAGMENT') ||
        message.contains('NO_VALID_FRAGMENT') ||
        message.contains('NO_VALID_SEGMENT');
  }

  String _safe(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp('_+'), '_');
  }
}
