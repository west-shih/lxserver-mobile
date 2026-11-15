import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/app/app.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/features/library/library_screen.dart';
import 'package:lxserver_mobile/features/search/entity_widgets.dart';
import 'package:lxserver_mobile/features/search/album_card.dart';
import 'package:lxserver_mobile/features/search/artist_card.dart';

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets(
      'Favorite album uses shared cards and switching preserves filter positions at scale $scale',
      (tester) async {
        final c = AppController();
        c.library.artists = [
          {'id': 'a', 'source': 'tx', 'name': '收藏歌手'},
        ];
        c.library.albums = [
          {
            'id': 'b',
            'source': 'tx',
            'name': 'Fixture Album',
            'artistName': '收藏歌手',
            'publishTime': '2020-01-02',
          },
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: LibraryScreen(controller: c)),
            ),
          ),
        );
        await tester.tap(find.widgetWithText(ChoiceChip, '歌手'));
        await tester.pumpAndSettle();
        expect(find.byType(ArtistCard), findsOneWidget);
        final badge = tester.getRect(find.byType(EntityBadge));
        final filter = tester.getRect(find.byType(ChoiceChip).first);
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.widgetWithText(ChoiceChip, '专辑'));
          await tester.pumpAndSettle();
          expect(find.byType(AlbumCard), findsOneWidget);
          expect(find.text('2020-01-02'), findsOneWidget);
          expect(find.byType(ListTile), findsNothing);
          expect(tester.getRect(find.byType(ChoiceChip).first), filter);
          await tester.tap(find.widgetWithText(ChoiceChip, '歌手'));
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(EntityBadge)), badge);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
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
      expect(c.availableSources.map((v) => v.label), [
        '网易',
        'QQ',
        '酷狗',
        '酷我',
        '咪咕',
      ]);
      final platformRects = find
          .byType(ChoiceChip)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)))
          .toList();
      for (final rect in platformRects) {
        expect(rect.width, closeTo(platformRects.first.width, .1));
      }
      if (scale == 1) {
        expect(platformRects.first.left, closeTo(16, .1));
        expect(platformRects.last.right, closeTo(344, .1));
      }
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
      final categoryRects = find
          .byType(ChoiceChip)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)))
          .toList();
      expect(categoryRects.length, 3);
      for (final rect in categoryRects) {
        expect(rect.width, closeTo(categoryRects.first.width, .1));
      }
      expect(categoryRects.first.left, closeTo(16, .1));
      expect(categoryRects.last.right, closeTo(344, .1));
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
      expect(find.widgetWithText(ChoiceChip, '网易').hitTestable(), findsNothing);
      c.keyword = 'new results';
      c.songs = [c.songs.first];
      c.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(ChoiceChip, '网易').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
