import 'package:flutter/material.dart';

/// 英语角 / English Corner —— 设计令牌
///
/// 命名保留历史名称（brandGreen / primaryBlue 等），以兼容全项目 596 处
/// 引用与 210 处 `const` 上下文；但**取值已统一到新的品牌体系**：
/// 翠玉（Jade）+ 琥珀金（Amber）+ 紫（Violet）。
///
/// 完整的、区分亮暗模式的调色板见 `lib/config/theme/app_colors.dart`。
/// 新代码优先使用 AppColors / AppPalette。
class AppDesignTokens {
  AppDesignTokens._();

  // ── 品牌主色（原 brandGreen → 翠玉）────────────────────────
  /// 主色：深翠玉。被大量用作主色填充。
  static const Color brandGreen = Color(0xFF00695C);

  /// 主色加深：用于按钮底部投影等需要压暗的场景。
  static const Color brandGreenDark = Color(0xFF004D40);

  // ── 点缀色（原 primaryBlue → 琥珀金）──────────────────────
  /// 点缀色：琥珀金。用于强调、进度、跟读高亮。
  static const Color primaryBlue = Color(0xFFF2A007);

  /// 点缀色加深。
  static const Color primaryBlueDark = Color(0xFFC97F00);

  // ── 功能色 ───────────────────────────────────────────────
  /// 紫：第三品牌色。
  static const Color yellow = Color(0xFF7C5CFF);

  /// 橙：暖色提示。
  static const Color orange = Color(0xFFE07A3C);

  // ── 浅色底（用于卡片、标签背景）──────────────────────────
  /// 翠玉极浅底。
  static const Color pinkLight = Color(0xFFE3F3EF);

  /// 冷调浅底。
  static const Color skyLight = Color(0xFFE6F4F1);

  /// 紫极浅底。
  static const Color purpleLight = Color(0xFFEFEBFF);

  // ── 中性色 ───────────────────────────────────────────────
  static const Color appWhite = Color(0xFFFFFFFF);
  static const Color softWhite = Color(0xFFF8F9FA);
  static const Color softGray = Color(0xFFF1F3F4);
  static const Color borderGray = Color(0xFFE3E7E8);
  static const Color textPrimary = Color(0xFF0F1416);
  static const Color textSecondary = Color(0xFF566062);

  // ── 阴影 ─────────────────────────────────────────────────

  /// 卡片阴影：低透明度多层，避免"糊成一块"的廉价感。
  static const List<BoxShadow> toyCardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0A0F1416), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x140F1416), blurRadius: 24, offset: Offset(0, 12)),
  ];

  /// 按钮阴影（已修正）。
  ///
  /// 原实现为 `BoxShadow(color: brandGreenDark, offset: Offset(0, 5))`，
  /// 且**没有 blurRadius（即 0）** —— 那不是阴影，而是在按钮正下方
  /// 画了一块实心深绿色方块，视觉上像贴纸或早期 3D 按钮的「厚底」。
  /// 这是界面显得廉价最典型的手法，全项目有 35 处引用。
  ///
  /// 现改为柔和的品牌色光晕 + 极淡中性阴影：保留「按钮有分量」的意图，
  /// 但不再有硬边。
  static const List<BoxShadow> toyButtonShadow = <BoxShadow>[
    BoxShadow(color: Color(0x1F00695C), blurRadius: 16, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x0A0F1416), blurRadius: 4, offset: Offset(0, 1)),
  ];
}
