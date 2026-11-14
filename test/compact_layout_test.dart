import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/app/app.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';

void main() {
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
      expect(tester.getSize(search).height, 44);
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
