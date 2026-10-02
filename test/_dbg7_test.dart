import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('诊断：InkWell 里的文字能否被长按选中', (WidgetTester tester) async {
    String selected = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (SelectedContent? c) {
              selected = c?.plainText ?? '';
            },
            child: SizedBox(
              width: 400,
              height: 300,
              child: Wrap(
                children: <Widget>[
                  for (final String w in <String>[
                    'FRANK:', 'Lip,', 'smart', 'as', 'a', 'whip.',
                  ])
                    InkWell(
                      onTap: () {},
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                        child: Text(w, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder target = find.text('smart');
    final TestGesture g = await tester.startGesture(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await g.up();
    await tester.pumpAndSettle();
    debugPrint('DIAG InkWell内长按选中=[$selected]');
  });

  testWidgets('对照：纯文本长按选中', (WidgetTester tester) async {
    String selected = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (SelectedContent? c) {
              selected = c?.plainText ?? '';
            },
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Lip, smart as a whip.', style: TextStyle(fontSize: 20)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final TestGesture g = await tester.startGesture(
      tester.getCenter(find.text('Lip, smart as a whip.')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await g.up();
    await tester.pumpAndSettle();
    debugPrint('DIAG 纯文本长按选中=[$selected]');
  });
}
