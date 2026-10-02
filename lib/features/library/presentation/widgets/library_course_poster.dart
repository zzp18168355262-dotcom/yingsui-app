import 'package:flutter/material.dart';

import '../../../shared/presentation/media/cover_image.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';

class LibraryCoursePoster extends StatelessWidget {
const LibraryCoursePoster({
    required this.title,
    required this.path,
    required this.borderRadius,
    this.fit = BoxFit.cover,
    /// 是否在占位海报中央显示标题。
    ///
    /// 首页预览卡在正中还有一个播放按钮，若同时显示标题就会互相压住
    /// （用户截图可见「导入你的第一套课程」被按钮遮住）。该处传 false。
    this.showTitle = true,
    super.key,
  });

  final String title;
  final String path;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    if (path.trim().isEmpty) {
      return _PosterPlaceholder(
        title: title,
        borderRadius: borderRadius,
        showTitle: showTitle,
      );
    }

    return CoverImage(
      path: path,
      fit: fit,
      errorBuilder: (_, _, __) {
        return _PosterPlaceholder(
          title: title,
          borderRadius: borderRadius,
          showTitle: showTitle,
        );
      },
    );
  }
}

class LibraryCoursePosterTitle extends StatelessWidget {
  const LibraryCoursePosterTitle({
    required this.title,
    super.key,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 3,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.15,
        color: AppDesignTokens.appWhite,
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({
    required this.title,
    required this.showTitle,
    required this.borderRadius,
  });

  final String title;
  final bool showTitle;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.primaryBlueDark,
        borderRadius: borderRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: showTitle
              ? LibraryCoursePosterTitle(title: title)
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
