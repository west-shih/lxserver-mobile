import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/app/app.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets('Fresh tab categories align at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c =
          AppController(
              api: LxApi(
                client: MockClient((_) async => http.Response('{}', 200)),
              ),
            )
            ..restoring = false
            ..offlineMode = true
            ..session = Session(
              Uri.parse('https://example.test'),
              'fixture',
              'fixture-token',
            );
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      final searchTop = tester
          .getTopLeft(find.byType(ChoiceChip).hitTestable().first)
          .dy;
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('歌单'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(ChoiceChip).hitTestable().first).dy,
        closeTo(searchTop, .1),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('我的'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('我的收藏'), findsOneWidget);
      expect(find.text('我的音乐'), findsNothing);
      expect(
        tester.getTopLeft(find.byType(ChoiceChip).hitTestable().first).dy,
        closeTo(searchTop, .1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  testWidgets(
    'Long results scroll filters away while the compact top search remains reachable',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController()
        ..restoring = false
        ..session = Session(
          Uri.parse('https://example.test'),
          'fixture',
          'fixture-token',
        )
        ..keyword = 'long results'
        ..songs = List.generate(
          150,
          (i) => Song({
            'songmid': '$i',
            'name': 'Song $i',
            'singer': 'Artist',
          }, MusicSource.kw),
        );
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('top-search-0'));
      expect(tester.getSize(search).height, 40);
      expect(find.text('LX MUSIC'), findsNothing);
      expect(find.text('找到你的下一首。'), findsNothing);
      await tester.drag(
        find.byKey(const PageStorageKey('music-results-scroll')),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      expect(search.hitTestable(), findsOneWidget);
      expect(find.text('全部').hitTestable(), findsNothing);
      c.keyword = 'new results';
      c.songs = [c.songs.first];
      c.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('全部').hitTestable(), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
