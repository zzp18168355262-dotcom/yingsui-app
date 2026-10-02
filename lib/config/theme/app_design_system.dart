import 'package:flutter/material.dart';

/// 英语角 / English Corner —— 间距、排版与描边令牌
///
/// 为什么单独一份：`app_theme.dart` 已定义颜色、圆角与阴影，
/// 但间距、字号字重、描边此前**完全没有令牌**，全部硬编码。
/// 审计结果（改动前）：
///   · 间距：18 种取值（4/5/6/8/10/12/14/16/18/20/22/24/28/32/48…）
///     其中 6/8/10/12/14 混用，同一屏内留白不齐，缺少节奏。
///   · 字号：14 种取值（10–28），11/12/13/14/15 几乎无法区分。
///   · 字重：w900 用了 100 处、w800 用了 110 处 —— **共 210 处粗体**，
///     标题与正文一样重，视觉层级消失。这是「质感差」的首要原因：
///     所有文字都在喊，等于没有重点。
///   · 描边：Border.all 68 处，且常与阴影同时出现（既描边又投影）。
///
/// 本文件提供统一取值。新增界面请一律引用令牌。

/// 间距令牌：4pt 基准网格。
///
/// 取值刻意收敛为 7 档。此前 6/8/10/12/14 混用，
/// 导致同类元素间距不一致 —— 视觉上「不齐」是最容易被察觉的廉价感。
class AppSpacing {
  AppSpacing._();

  /// 4 —— 紧凑元素内部（图标与文字之间）。
  static const double xs = 4;

  /// 8 —— 小间距（同类信息之间）。
  static const double sm = 8;

  /// 12 —— 常规内间距（列表项内边距）。
  static const double md = 12;

  /// 16 —— 卡片内边距、区块间距。
  static const double lg = 16;

  /// 20 —— 卡片内边距（宽松）。
  static const double xl = 20;

  /// 24 —— 区块之间。
  static const double xxl = 24;

  /// 32 —— 大区块之间。
  static const double section = 32;

  /// 常用的内边距组合，避免各处手写造成不齐。
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: xl,
    vertical: lg,
  );
  static const EdgeInsets listTilePadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );
}

/// 排版令牌：按语义分层，而不是按数值散用。
///
/// 核心原则是**字重分层**：只有真正的标题才用粗体，
/// 正文与辅助信息用常规/中等字重。这样层级才立得起来。
///
/// 字重分配（对齐 Material 语义）：
///   · display / title  → w700（标题，少量使用）
///   · body             → w600（正文，需清晰但不喧宾夺主）
///   · label / caption  → w500（辅助信息，最轻）
/// 此前 w900 与 w800 各上百处，属于滥用，已在本令牌中彻底移除。
class AppTypography {
  AppTypography._();

  /// 大标题：页面主标题（如「设置」）。
  static const TextStyle display = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.4,
  );

  /// 区块标题：卡片标题、分组标题（如「播放」「学习」）。
  static const TextStyle title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.2,
  );

  /// 小标题：列表项标题。
  static const TextStyle subtitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.35,
  );

  /// 正文：说明文字、段落。
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  /// 辅助文字：次要说明。
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  /// 标签：徽章、分类标签等极小文字。
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 0.2,
  );

  /// 数据展示：进度、分数等需要强调的数字。
  static const TextStyle metric = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.3,
  );
}

/// 描边令牌。
///
/// 审计发现 Border.all 68 处，且常与阴影同时出现 ——
/// 一张卡片既描边又投影会显得「堆叠」，是廉价感的来源之一。
///
/// 原则：**要么用描边，要么用阴影，不要两者都用**。
///   · 需要浮起 → 用 AppElevation 的阴影，不要再描边
///   · 需要贴地分隔 → 只用 1px 描边，不给阴影
class AppBorder {
  AppBorder._();

  /// 贴地卡片的细描边（配 AppElevation.flat 使用）。
  static const double hairline = 1;
}
