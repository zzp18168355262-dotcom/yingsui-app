/// 逐词全文浮动窗格。
///
/// 用户要求：点「全文阅读」弹出**独立窗格**，与视频并存，
/// 而不是整页盖住播放页；并且窗格要能拖动。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/widgets/draggable_pane.dart';

void main() {
  Widget page({required VoidCallback onClose}) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            // 代表底层播放页，用于确认窗格是「叠加」而不是「替换」。
            const Positioned.fill(
              child: ColoredBox(
                key: ValueKey<String>('player-underneath'),
                color: Color(0xFF10161A),
              ),
            ),
            DraggablePane(
              title: '逐词全文',
              onClose: onClose,
              child: const Center(child: Text('阅读内容')),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('窗格叠加在播放页之上（不替换底层内容）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(onClose: () {}));
    await tester.pumpAndSettle();

    expect(find.text('逐词全文'), findsOneWidget);
    expect(find.text('阅读内容'), findsOneWidget);
    // 底层仍然存在 —— 这正是「两个并存」的含义。
    expect(
      find.byKey(const ValueKey<String>('player-underneath')),
      findsOneWidget,
    );
  });

  testWidgets('拖动标题栏可移动窗格', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(onClose: () {}));
    await tester.pumpAndSettle();

    final Finder handle = find.byIcon(Icons.drag_indicator_rounded);
    final Offset before = tester.getTopLeft(handle);

    await tester.drag(handle, const Offset(-120, 90));
    await tester.pumpAndSettle();

    final Offset after = tester.getTopLeft(handle);
    expect(after.dx, lessThan(before.dx - 50), reason: '应能向左拖动');
    expect(after.dy, greaterThan(before.dy + 30), reason: '应能向下拖动');
  });

  testWidgets('四边与四角都能缩放（不再只能抓右下角）', (WidgetTester tester) async {
    // 用户反馈「只能按住右下角那个图标缩放，不方便」。
    // 现在八个方向都有把手。
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(onClose: () {}));
    await tester.pumpAndSettle();

    // 直接测窗格本体：标题栏高度是固定的 40，测不出高度变化。
    Size paneSize() =>
        tester.getSize(find.byKey(const ValueKey<String>('pane-surface')));

    // 八个把手都应存在。
    for (final String name in <String>[
      'top',
      'bottom',
      'left',
      'right',
      'topLeft',
      'topRight',
      'bottomLeft',
      'bottomRight',
    ]) {
      expect(
        find.byKey(ValueKey<String>('pane-resize-$name')),
        findsOneWidget,
        reason: '$name 方向应有缩放手把',
      );
    }

    // 拖右边 → 宽度变大。
    final Size before = paneSize();
    await tester.drag(
      find.byKey(const ValueKey<String>('pane-resize-right')),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    expect(paneSize().width, greaterThan(before.width + 50), reason: '拖右边应加宽');

    // 拖下边 → 高度变大。
    final Size beforeHeight = paneSize();
    await tester.drag(
      find.byKey(const ValueKey<String>('pane-resize-bottom')),
      const Offset(0, 90),
    );
    await tester.pumpAndSettle();
    expect(
      paneSize().height,
      greaterThan(beforeHeight.height + 30),
      reason: '拖下边应加高',
    );
  });

  testWidgets('尺寸调节范围足够大（可缩到很小、也可铺满窗口）', (WidgetTester tester) async {
    // 用户反馈「可以调节的大小范围还是有限」。
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(onClose: () {}));
    await tester.pumpAndSettle();

    // 直接测窗格本体：标题栏高度是固定的 40，测不出高度变化。
    Size paneSize() =>
        tester.getSize(find.byKey(const ValueKey<String>('pane-surface')));

    // 缩到最小：往左上角猛拖右下角把手。
    await tester.drag(
      find.byKey(const ValueKey<String>('pane-resize-bottomRight')),
      const Offset(-2000, -2000),
    );
    await tester.pumpAndSettle();
    final Size small = paneSize();
    expect(small.width, lessThan(320), reason: '应能缩到很小');

    // 放到最大：往右下角猛拖。
    await tester.drag(
      find.byKey(const ValueKey<String>('pane-resize-bottomRight')),
      const Offset(3000, 3000),
    );
    await tester.pumpAndSettle();
    final Size large = paneSize();
    expect(
      large.width,
      greaterThan(1100),
      reason: '应能放大到接近铺满窗口（1200 宽）',
    );
  });

  testWidgets('点击关闭按钮触发回调', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    bool closed = false;
    await tester.pumpWidget(page(onClose: () => closed = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });

  testWidgets('窗格不会被拖出屏幕（标题栏始终可点）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(onClose: () {}));
    await tester.pumpAndSettle();

    final Finder handle = find.byIcon(Icons.drag_indicator_rounded);
    // 往左上角猛拖。
    await tester.drag(handle, const Offset(-2000, -2000));
    await tester.pumpAndSettle();

    final Rect handleRect = tester.getRect(handle);
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      handleRect.left,
      lessThan(screen.width),
      reason: '标题栏不应被拖到屏幕右侧之外',
    );
    expect(handleRect.top, greaterThanOrEqualTo(-1), reason: '标题栏不应被拖到屏幕上方之外');
  });
}
