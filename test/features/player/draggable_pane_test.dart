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

  testWidgets('拖动右下角把手可改变窗格尺寸', (WidgetTester tester) async {
    // 用户反馈「这个页面没法调整大小」。
    // 实测功能本身可用，但把手原先只有 14×14、图标也不明显，
    // 用户找不到。这里同时验证「能找到」与「拖动能改尺寸」。
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(onClose: () {}));
    await tester.pumpAndSettle();

    // 用标题栏宽度代表窗格宽度。
    Size paneSize() {
      final Finder bar = find.ancestor(
        of: find.text('逐词全文'),
        matching: find.byType(Container),
      );
      return tester.getSize(bar.first);
    }

    final Finder handle = find.byIcon(Icons.open_in_full_rounded);
    expect(handle, findsOneWidget, reason: '缩放把手应存在且可被找到');

    // 实际可拖区域应足够大、便于抓取（图标本身是可视部分，会小一些）。
    final Rect hitArea = tester.getRect(
      find
          .ancestor(of: handle, matching: find.byType(GestureDetector))
          .first,
    );
    expect(
      hitArea.width,
      greaterThanOrEqualTo(28),
      reason: '把手可拖区域不应小于 28 逻辑像素',
    );

    final Size before = paneSize();
    await tester.drag(handle, const Offset(160, 120));
    await tester.pumpAndSettle();
    final Size after = paneSize();

    expect(after.width, greaterThan(before.width + 50), reason: '拖拽应增大宽度');
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
