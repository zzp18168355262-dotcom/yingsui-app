import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme/app_theme.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import 'navigation_destination.dart';

class FloatingBottomNav extends StatelessWidget {
  const FloatingBottomNav({required this.current, super.key});

  final AppNavDestination current;

  static const List<AppNavDestination> _primaryDestinations =
      <AppNavDestination>[
        AppNavDestination.home,
        AppNavDestination.library,
        AppNavDestination.growth,
      ];

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double width = size.width;
    final bool compact = width < 768;
    final bool useMoreMenu = size.height > size.width;
    final List<AppNavDestination> allDestinations = AppNavDestination.values
        .where(
          (AppNavDestination destination) => destination.showInNav,
        )
        .toList(growable: false);
    final List<AppNavDestination> destinations = allDestinations
        .where(
          (AppNavDestination destination) =>
              destination.showInBottomNav,
        )
        .toList(growable: false);
    final List<AppNavDestination> secondaryDestinations = allDestinations
        .where(
          (AppNavDestination destination) =>
              !_primaryDestinations.contains(destination),
        )
        .toList(growable: false);
    final List<AppNavDestination> visibleDestinations = useMoreMenu
        ? _primaryDestinations
        : destinations;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 16,
        compact ? 8 : 12,
        compact ? 10 : 16,
        compact ? 10 : 16,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? AppRadius.xl : AppRadius.xxl),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(compact ? AppRadius.xl : AppRadius.xxl),
              boxShadow: AppDesignTokens.toyCardShadow,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 8,
                vertical: compact ? 6 : 8,
              ),
              child: Row(
                children: <Widget>[
                  ...visibleDestinations.map<Widget>(
                    (AppNavDestination destination) => Expanded(
                      child: _NavItem(
                        destination: destination,
                        selected: destination == current,
                      ),
                    ),
                  ),
                  if (useMoreMenu)
                    Expanded(
                      child: _MoreNavItem(
                        selected: secondaryDestinations.contains(current),
                        destinations: secondaryDestinations,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreNavItem extends StatelessWidget {
  const _MoreNavItem({required this.selected, required this.destinations});

  final bool selected;
  final List<AppNavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 768;
    return InkWell(
      key: const Key('bottom-nav-more'),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => _showMoreMenu(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 2 : 4,
          vertical: compact ? 8 : 10,
        ),
        // 与 _NavItem 保持完全一致的选中表达，
      // 避免同一组导航出现两种样式（此前「更多」是白底反色，与其它项不同）。
      decoration: BoxDecoration(
        color: selected
            ? AppDesignTokens.brandGreen.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: compact ? 30 : 34,
            height: compact ? 30 : 34,
            child: Icon(
              selected ? Icons.grid_view_rounded : Icons.grid_view_outlined,
              size: compact ? 20 : 22,
              color: selected
                  ? AppDesignTokens.brandGreen
                  : AppDesignTokens.textSecondary,
            ),
          ),
          SizedBox(height: compact ? 3 : 4),
          Text(
            '更多',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? AppDesignTokens.brandGreenDark
                  : AppDesignTokens.textSecondary,
              fontSize: compact ? 10 : 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          ], // children
        ),
      ),
    );
  }

  Future<void> _showMoreMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '更多功能',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...destinations.map(
                (AppNavDestination destination) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(destination.icon),
                  title: Text(destination.label),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go(destination.route);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected});

  final AppNavDestination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 768;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => context.go(destination.route),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 2 : 4,
          vertical: compact ? 8 : 10,
        ),
        // 选中态改为「淡色底 + 品牌色图标」。
      //
      // 原先是深绿实心底 + 白色方块里放反白图标，再叠一层硬边阴影，
      // 视觉上很重、像玩具按钮。现在统一为更克制的表达：
      // 用极淡的品牌色底暗示位置，图标与文字用品牌色表达选中，
      // 且不加阴影 —— 既清楚又不喧宾夺主。
      decoration: BoxDecoration(
        color: selected
            ? AppDesignTokens.brandGreen.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: compact ? 30 : 34,
            height: compact ? 30 : 34,
            child: Icon(
              selected ? destination.activeIcon : destination.icon,
              size: compact ? 20 : 22,
              color: selected
                  ? AppDesignTokens.brandGreen
                  : AppDesignTokens.textSecondary,
            ),
          ),
          SizedBox(height: compact ? 3 : 4),
          Text(
            destination.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? AppDesignTokens.brandGreenDark
                  : AppDesignTokens.textSecondary,
              fontSize: compact ? 10 : 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          ], // children
        ),
      ),
    );
  }
}
