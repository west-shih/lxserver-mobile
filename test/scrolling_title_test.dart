import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/shared/scrolling_title.dart';

Widget title(String text, {bool reducedMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 120,
          height: 40,
          child: ScrollingTitle(text: text),
        ),
      ),
    ),
  ),
);

double translation(WidgetTester tester) => tester
    .widget<Transform>(
      find.descendant(
        of: find.byType(ScrollingTitle),
        matching: find.byType(Transform),
      ),
    )
    .transform
    .storage[12];

void main() {
  testWidgets('Short titles remain static at compact font size', (
    tester,
  ) async {
    await tester.pumpWidget(title('Short'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ScrollingTitle),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    expect(tester.widget<Text>(find.text('Short')).style!.fontSize, 17);
    expect(tester.binding.hasScheduledFrame, false);
  });
  testWidgets(
    'Overflowing title pauses then scrolls, and stops after renaming to a short title',
    (tester) async {
      await tester.pumpWidget(
        title('A long collection title that exceeds the available width'),
      );
      await tester.pump();
      expect(translation(tester), 0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(translation(tester), 0);
      await tester.pump(const Duration(seconds: 2));
      expect(translation(tester), lessThan(0));
      await tester.pumpWidget(title('Short'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ScrollingTitle),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      expect(tester.binding.hasScheduledFrame, false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'AppBar title moves with accessibility navigation enabled and retains a readable full title',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const name =
          'A long collection title that is much wider than its navigation bar';
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(accessibleNavigation: true),
            child: Scaffold(
              appBar: AppBar(
                leading: const BackButton(),
                title: const ScrollingTitle(text: name),
                actions: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(translation(tester), 0);
      final text = find.text(name);
      final before = tester.getTopLeft(text).dx;
      await tester.pump(const Duration(seconds: 3));
      expect(translation(tester), lessThan(0));
      expect(tester.getTopLeft(text).dx, lessThan(before));
      expect(find.bySemanticsLabel(name), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Reduced motion keeps the full accessible title without animation',
    (tester) async {
      const text = 'A long title with reduced motion enabled';
      await tester.pumpWidget(title(text, reducedMotion: true));
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ScrollingTitle),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      expect(tester.binding.hasScheduledFrame, false);
    },
  );
}
