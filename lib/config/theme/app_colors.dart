import 'package:flutter/material.dart';

/// 英语角 / English Corner —— 设计系统颜色令牌
///
/// 设计方向：翠玉（Jade）+ 琥珀金（Amber）+ 紫（Violet），冷白底。
/// 三色体系保证有记忆点，同时用深主色守住质感，
/// 避免荧光色带来的廉价感。
///
/// 使用约定：
/// - 组件里**不要**再写十六进制字面量，一律引用这里的令牌。
/// - 需要随亮/暗模式变化的颜色，用 `AppColors.of(context)` 取。
class AppColors {
  AppColors._();

  // ───────────────────────── 品牌色 ─────────────────────────

  /// 亮色模式品牌主色：深翠玉。够深所以高级，饱和度够高所以有辨识度。
  static const Color brandJade = Color(0xFF00695C);

  /// 暗色模式品牌主色：亮翠玉（保证暗底上的对比度）。
  static const Color brandJadeLight = Color(0xFF3DD6C0);

  /// 点缀金：用于跟读高亮、进度、关键强调。暖色在冷底上最抓眼。
  static const Color brandAmber = Color(0xFFF2A007);

  /// 暗色模式点缀金。
  static const Color brandAmberLight = Color(0xFFFFC24B);

  /// 紫：第三品牌色，用于进度、词级高亮、成长体系等差异化场景。
  static const Color brandViolet = Color(0xFF7C5CFF);

  /// 暗色模式紫。
  static const Color brandVioletLight = Color(0xFFA78BFA);

  // ───────────────────────── 中性色（亮） ─────────────────────────

  static const Color _canvasLight = Color(0xFFF8F9FA);
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _surfaceAltLight = Color(0xFFF1F3F4);
  static const Color _borderLight = Color(0xFFE3E7E8);
  static const Color _dividerLight = Color(0xFFEDF0F1);

  static const Color _textPrimaryLight = Color(0xFF0F1416);
  static const Color _textSecondaryLight = Color(0xFF566062);
  static const Color _textTertiaryLight = Color(0xFF8A9396);

  // ───────────────────────── 中性色（暗） ─────────────────────────

  static const Color _canvasDark = Color(0xFF0B0D0E);
  static const Color _surfaceDark = Color(0xFF15181A);
  static const Color _surfaceAltDark = Color(0xFF1D2124);
  static const Color _borderDark = Color(0xFF262B2E);
  static const Color _dividerDark = Color(0xFF1E2225);

  static const Color _textPrimaryDark = Color(0xFFEDEFF0);
  static const Color _textSecondaryDark = Color(0xFF9BA5A8);
  static const Color _textTertiaryDark = Color(0xFF6B7578);

  // ───────────────────────── 语义色 ─────────────────────────

  static const Color success = Color(0xFF1B8A5A);
  static const Color successDark = Color(0xFF43C98A);
  static const Color warning = Color(0xFFD08A00);
  static const Color warningDark = Color(0xFFE8B44A);
  static const Color danger = Color(0xFFD1453B);
  static const Color dangerDark = Color(0xFFEF7A70);
  static const Color info = Color(0xFF2D6FA8);
  static const Color infoDark = Color(0xFF64A6DC);

  // ───────────────────────── 渐变 ─────────────────────────

  /// 品牌渐变：用于主按钮、头图等需要视觉分量的位置。
  static LinearGradient brandGradient(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const LinearGradient(
        colors: <Color>[Color(0xFF3DD6C0), Color(0xFF7C5CFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    return const LinearGradient(
      colors: <Color>[Color(0xFF00695C), Color(0xFF00897B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  // ───────────────────────── 阴影 ─────────────────────────

  /// 卡片阴影：低透明度多层，避免"糊成一块"的廉价感。
  static List<BoxShadow> cardShadow(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const <BoxShadow>[
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ];
    }
    return const <BoxShadow>[
      BoxShadow(color: Color(0x0A0F1416), blurRadius: 8, offset: Offset(0, 2)),
      BoxShadow(
        color: Color(0x0F0F1416),
        blurRadius: 24,
        offset: Offset(0, 12),
      ),
    ];
  }

  // ───────────────────────── 便捷取色 ─────────────────────────

  /// 根据当前亮/暗模式取对应中性色。
  static AppPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const AppPalette._dark()
        : const AppPalette._light();
  }
}

/// 一套完整的调色板，随亮/暗模式切换。
class AppPalette {
  const AppPalette._light()
    : canvas = AppColors._canvasLight,
      surface = AppColors._surfaceLight,
      surfaceAlt = AppColors._surfaceAltLight,
      border = AppColors._borderLight,
      divider = AppColors._dividerLight,
      textPrimary = AppColors._textPrimaryLight,
      textSecondary = AppColors._textSecondaryLight,
      textTertiary = AppColors._textTertiaryLight,
      brand = AppColors.brandJade,
      accent = AppColors.brandAmber,
      tertiary = AppColors.brandViolet,
      onBrand = const Color(0xFFFFFFFF),
      success = AppColors.success,
      warning = AppColors.warning,
      danger = AppColors.danger,
      info = AppColors.info,
      isDark = false;

  const AppPalette._dark()
    : canvas = AppColors._canvasDark,
      surface = AppColors._surfaceDark,
      surfaceAlt = AppColors._surfaceAltDark,
      border = AppColors._borderDark,
      divider = AppColors._dividerDark,
      textPrimary = AppColors._textPrimaryDark,
      textSecondary = AppColors._textSecondaryDark,
      textTertiary = AppColors._textTertiaryDark,
      brand = AppColors.brandJadeLight,
      accent = AppColors.brandAmberLight,
      tertiary = AppColors.brandVioletLight,
      onBrand = const Color(0xFF04100E),
      success = AppColors.successDark,
      warning = AppColors.warningDark,
      danger = AppColors.dangerDark,
      info = AppColors.infoDark,
      isDark = true;

  final Color canvas;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// 品牌主色（当前模式）。
  final Color brand;

  /// 强调色（琥珀金）。
  final Color accent;

  /// 第三品牌色（紫）。
  final Color tertiary;

  /// 品牌色之上的文字色。
  final Color onBrand;

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final bool isDark;
}
