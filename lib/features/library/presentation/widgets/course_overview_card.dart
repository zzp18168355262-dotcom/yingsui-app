import 'package:flutter/material.dart';

import '../../../../config/theme/app_theme.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../library_mock_data.dart';
import 'library_course_poster.dart';

/// 课程概览卡：海报 + 标题信息 + 学习进度 + 续播提示。
///
/// 布局分三档，手机上不再挤压：
///   · phone  (< 600dp)：海报在上、内容在下（单列）
///   · compact(< 980dp)：海报在左、内容在右，海报 176 宽
///   · 宽屏            ：海报 220 宽
///
/// 为什么需要 phone 档：原先只有 compact/宽屏两档，且**两档都是左右 Row**
/// （海报固定宽度）。在 360dp 手机上右侧仅剩约 140dp，进度区里三个并排的
/// 统计块各只有 38dp 宽，「词汇储备」被迫逐字竖排、数字被裁切。
class CourseOverviewCard extends StatelessWidget {
  const CourseOverviewCard({
    required this.course,
    required this.activeEpisode,
    required this.onPlayTap,
    super.key,
  });

  final LibraryCourseData course;
  final LibraryEpisodeItem activeEpisode;
  final VoidCallback onPlayTap;

  @override
  Widget build(BuildContext context) {
    final int episodeNumber = int.tryParse(activeEpisode.numberStr) ?? 0;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool phone = constraints.maxWidth < 600;
        final bool compact = constraints.maxWidth < 980;

        // 窄屏把外层留白也收一点，给内容让出宽度。
        final double padding = phone ? 14 : 20;

        final Widget poster = _Poster(
          course: course,
          episodeNumber: episodeNumber,
          activeEpisode: activeEpisode,
          onPlayTap: onPlayTap,
          width: phone ? null : (compact ? 176 : 220),
          height: phone
              ? (constraints.maxWidth * 0.46).clamp(140.0, 200.0)
              : (compact ? 224 : 272),
        );

        final Widget content = _Content(
          course: course,
          activeEpisode: activeEpisode,
          episodeNumber: episodeNumber,
          compact: compact,
          phone: phone,
        );

        return Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: AppDesignTokens.appWhite,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            boxShadow: AppDesignTokens.toyCardShadow,
          ),
          child: phone
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    poster,
                    const SizedBox(height: 14),
                    content,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    poster,
                    SizedBox(width: compact ? 18 : 24),
                    Expanded(child: content),
                  ],
                ),
        );
      },
    );
  }
}

/// 海报区：封面 + 等级/分类角标 + 播放条。
class _Poster extends StatelessWidget {
  const _Poster({
    required this.course,
    required this.episodeNumber,
    required this.activeEpisode,
    required this.onPlayTap,
    this.width,
    required this.height,
  });

  final LibraryCourseData course;
  final int episodeNumber;
  final LibraryEpisodeItem activeEpisode;
  final VoidCallback onPlayTap;

  /// 为空表示占满可用宽度（手机单列时使用）。
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final Widget poster = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          LibraryCoursePoster(
            title: course.title,
            path: course.coverImage,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.36),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: _PillLabel(
              label: course.level,
              backgroundColor: AppDesignTokens.appWhite.withValues(alpha: 0.94),
              textColor: AppDesignTokens.primaryBlueDark,
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: _PillLabel(
              label: course.category,
              backgroundColor: AppDesignTokens.yellow,
              textColor: AppDesignTokens.textPrimary,
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPlayTap,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.appWhite.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: AppDesignTokens.brandGreen,
                          shape: BoxShape.circle,
                          boxShadow: AppDesignTokens.toyButtonShadow,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '第 $episodeNumber 集 · ${activeEpisode.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (width == null) {
      return SizedBox(width: double.infinity, height: height, child: poster);
    }
    return SizedBox(width: width, height: height, child: poster);
  }
}

/// 右侧/下方信息区。
class _Content extends StatelessWidget {
  const _Content({
    required this.course,
    required this.activeEpisode,
    required this.episodeNumber,
    required this.compact,
    required this.phone,
  });

  final LibraryCourseData course;
  final LibraryEpisodeItem activeEpisode;
  final int episodeNumber;
  final bool compact;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final List<Widget> stats = <Widget>[
      _StatBlock(
        label: '已完成',
        value: '${course.completedEpisodes}/${course.totalEpisodes} 集',
        inline: phone,
      ),
      _StatBlock(
        label: '词汇储备',
        value: '${course.totalWords} 个',
        inline: phone,
      ),
      _StatBlock(
        label: '评分',
        value: course.rating.toStringAsFixed(1),
        inline: phone,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          course.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: phone ? 22 : (compact ? 30 : 34),
            fontWeight: FontWeight.w700,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          course.description,
          maxLines: phone ? 3 : (compact ? 2 : 3),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: phone ? 14 : 16,
            height: 1.5,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '来源：${course.sourceLabel}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        SizedBox(height: phone ? 14 : 18),
        Container(
          padding: EdgeInsets.all(phone ? 14 : 18),
          decoration: BoxDecoration(
            color: AppDesignTokens.softWhite,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppDesignTokens.borderGray),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Flexible(
                    child: Text(
                      '学习进度',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${course.progressPercent}%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.brandGreenDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: course.progressPercent / 100,
                  minHeight: 10,
                  backgroundColor: AppDesignTokens.softGray,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppDesignTokens.brandGreen,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // 手机：每项占满一行，标签与数值左右排开，
              // 「词汇储备」不会再被压成竖排单字。
              // 宽屏：三个小卡片并排。
              if (phone)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final Widget stat in stats) ...<Widget>[
                      stat,
                      if (stat != stats.last) const SizedBox(height: 10),
                    ],
                  ],
                )
              else
                Row(
                  children: <Widget>[
                    for (final Widget stat in stats) ...<Widget>[
                      Expanded(child: stat),
                      if (stat != stats.last) const SizedBox(width: 12),
                    ],
                  ],
                ),
            ],
          ),
        ),
        SizedBox(height: phone ? 12 : 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppDesignTokens.purpleLight,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.lightbulb_rounded,
                color: AppDesignTokens.primaryBlueDark,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当前继续：第 $episodeNumber 集 ${activeEpisode.title}',
                  maxLines: phone ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 单项统计。
///
/// [inline] 为 true 时横排显示「标签 ——— 数值」（手机上用），
/// 否则是上下两行的小卡片（宽屏用）。横排是为了避免窄宽度下标签逐字换行。
class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    this.inline = false,
  });

  final String label;
  final String value;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    if (inline) {
      return Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textPrimary,
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillLabel extends StatelessWidget {
  const _PillLabel({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}
