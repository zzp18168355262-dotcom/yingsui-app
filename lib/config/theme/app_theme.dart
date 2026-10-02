import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 英语角 / English Corner —— 应用主题
///
/// 字体使用项目内置的 Nunito（见 pubspec.yaml 的 fonts 段），
/// 不再走 google_fonts 的运行时下载，避免国内网络问题。
const String kAppFontFamily = 'Nunito';

/// 圆角令牌：统一卡片与控件的圆角，形成稳定的视觉语言。
///
/// 为什么需要这份令牌：此前全项目硬编码了 11 种圆角数值
/// （24/28/18/16/22/20/14/26/32…），同一屏内相邻卡片圆角不一致，
/// 观感会显得随意、不精致。这里收敛为 7 档语义化取值，
/// 新增界面请一律引用令牌，不要写字面量。
class AppRadius {
  AppRadius._();

  /// 微小元素：标签、徽章。
  static const double xs = 6;

  /// 小控件：输入框、小按钮。
  static const double sm = 10;

  /// 中控件：列表项、次级卡片。
  static const double md = 14;

  /// 常规卡片。
  static const double lg = 18;

  /// 大卡片：主视觉容器。
  static const double xl = 24;

  /// 特大容器：底部面板、弹窗。
  static const double xxl = 28;

  /// 全圆角：胶囊按钮、开关。
  static const double pill = 999;
}

/// 阴影令牌：统一界面高度层次。
///
/// 采用材质设计的「多层阴影」做法 —— 同一层级由两到三组
/// 不同模糊半径/偏移的阴影叠加，而不是单一阴影。
/// 单一阴影要么显得脏（太深太大），要么显得平（太小太淡），
/// 这是界面「廉价感」的常见来源。
///
/// 阴影颜色统一取带品牌色相的中性色 0x0F1416（偏冷的深灰绿），
/// 而不是纯黑：纯黑投影会显脏、发灰。
class AppElevation {
  AppElevation._();

  /// 阴影基色：0F1416，偏冷的中性深色。
  static const Color _tint = Color(0xFF0F1416);

  /// 层级 0：贴地。用于表格分隔、内嵌区块，仅有极淡的边界感。
  static const List<BoxShadow> flat = <BoxShadow>[
    BoxShadow(color: Color(0x080F1416), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// 层级 1：轻微浮起。用于列表项、次级卡片。
  static const List<BoxShadow> low = <BoxShadow>[
    BoxShadow(color: Color(0x0A0F1416), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x060F1416), blurRadius: 12, offset: Offset(0, 6)),
  ];

  /// 层级 2：常规卡片。默认卡片高度。
  static const List<BoxShadow> medium = <BoxShadow>[
    BoxShadow(color: Color(0x0A0F1416), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0A0F1416), blurRadius: 20, offset: Offset(0, 10)),
  ];

  /// 层级 3：明显浮层。用于悬浮导航、下拉、气泡。
  static const List<BoxShadow> high = <BoxShadow>[
    BoxShadow(color: Color(0x0F0F1416), blurRadius: 10, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x140F1416), blurRadius: 28, offset: Offset(0, 14)),
  ];

  /// 层级 4：模态。用于弹窗、底部面板。
  static const List<BoxShadow> modal = <BoxShadow>[
    BoxShadow(color: Color(0x140F1416), blurRadius: 16, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x1A0F1416), blurRadius: 48, offset: Offset(0, 24)),
  ];

  /// 品牌强调光晕：用于主按钮等需要吸引视线的元素。
  /// 注意：必须配合品牌色使用，不要当作通用阴影。
  static List<BoxShadow> brandGlow(Color color) => <BoxShadow>[
    BoxShadow(
      color: color.withValues(alpha: 0.24),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  /// 仅为保持引用一致（避免 lint 报未使用私有字段）。
  static Color get tint => _tint;
}

ThemeData buildAppTheme(Brightness brightness) {
  final bool isDark = brightness == Brightness.dark;

  // 以品牌翠玉为种子生成完整色板，再覆盖需要精确控制的槽位。
  // 用 fromSeed 而不是手写 ColorScheme 构造，可保证与当前 Flutter 版本的
  // 必需字段完全兼容。
  final ColorScheme base = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: AppColors.brandJade,
  );

  final ColorScheme colorScheme = base.copyWith(
    primary: isDark ? AppColors.brandJadeLight : AppColors.brandJade,
    onPrimary: isDark ? const Color(0xFF04100E) : Colors.white,
    secondary: isDark ? AppColors.brandAmberLight : AppColors.brandAmber,
    onSecondary: isDark ? const Color(0xFF231705) : Colors.white,
    tertiary: isDark ? AppColors.brandVioletLight : AppColors.brandViolet,
    surface: isDark ? const Color(0xFF15181A) : Colors.white,
    onSurface: isDark ? const Color(0xFFEDEFF0) : const Color(0xFF0F1416),
    surfaceContainerHighest: isDark
        ? const Color(0xFF1D2124)
        : const Color(0xFFF1F3F4),
    outline: isDark ? const Color(0xFF262B2E) : const Color(0xFFE3E7E8),
    error: isDark ? AppColors.dangerDark : AppColors.danger,
    onError: Colors.white,
  );

  final TextTheme textTheme = _buildTextTheme(colorScheme);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    fontFamily: kAppFontFamily,
    textTheme: textTheme,
    visualDensity: const VisualDensity(horizontal: -0.5, vertical: -0.5),
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF0C0D0F)
        : const Color(0xFFF7F6F3),
    cardColor: colorScheme.surface,
    dividerColor: isDark ? const Color(0xFF1F2329) : const Color(0xFFEFEDE8),

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // 用 onPrimary 而非固定白色：暗色模式下主色是浅墨青，
        // 固定白色文字会导致对比度过低、几乎不可读。
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.outline),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      margin: EdgeInsets.zero,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      selectedColor: colorScheme.primary,
      labelStyle: textTheme.labelLarge,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark
          ? const Color(0xFF23272E)
          : const Color(0xFF1B1E24),
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: colorScheme.surfaceContainerHighest,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: colorScheme.primary,
      thumbColor: colorScheme.primary,
      inactiveTrackColor: colorScheme.surfaceContainerHighest,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) {
          return states.contains(WidgetState.selected)
              ? colorScheme.onPrimary
              : null;
        },
      ),
      trackColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) {
          return states.contains(WidgetState.selected)
              ? colorScheme.primary
              : null;
        },
      ),
    ),

    splashFactory: InkSparkle.splashFactory,
  );
}

TextTheme _buildTextTheme(ColorScheme colorScheme) {
  // 使用内置 Nunito 字重（Light 300 / Regular 400 / Medium 500 / Bold 700）。
  // 字重映射到实际存在的字重，避免浏览器或系统做合成加粗。
  final TextTheme base = ThemeData(brightness: colorScheme.brightness)
      .textTheme
      .apply(
        fontFamily: kAppFontFamily,
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      );

  return base.copyWith(
    // 关键标题：用 Bold + 轻微负字距，提升"高级感"
    displayLarge: base.displayLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
    ),
    displayMedium: base.displayMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
    ),
    displaySmall: base.displaySmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w500),
    bodyLarge: base.bodyLarge?.copyWith(height: 1.45),
    bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );
}
