import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/shared/song_tile.dart';

void main() {
  testWidgets(
    'Current track shows playback state and opens quality from list',
    (tester) async {
      final c = AppController();
      addTearDown(c.dispose);
      final session = Session(
        Uri.parse('https://example.test'),
        'fixture',
        'fixture-token',
      );
      final song = Song({
        'songmid': 'current',
        'name': 'Current',
      }, MusicSource.tx);
      final other = Song({'songmid': 'other', 'name': 'Other'}, MusicSource.tx);
      c.player.enqueue(session, song);
      c.player.enqueue(session, other);
      c.player.index = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SongTile(song: song, controller: c, queue: [song, other]),
                SongTile(song: other, controller: c, queue: [song, other]),
              ],
            ),
          ),
        ),
      );
      expect(find.byTooltip('继续播放当前歌曲'), findsOneWidget);
      c.player.playing = true;
      c.player.refreshQualityAvailability();
      await tester.pump();
      expect(find.byTooltip('暂停当前歌曲'), findsOneWidget);
      await tester.tap(find.byTooltip('Current的更多操作'));
      await tester.pumpAndSettle();
      expect(find.text('音质选择'), findsOneWidget);
      await tester.tap(find.text('音质选择'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quality-sheet')), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      c.player.index = 1;
      c.player.playing = false;
      c.player.refreshQualityAvailability();
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(SongTile).first,
          matching: find.byTooltip('继续播放当前歌曲'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(SongTile).last,
          matching: find.byTooltip('继续播放当前歌曲'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Current的更多操作'));
      await tester.pumpAndSettle();
      expect(find.text('音质选择'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
