import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/player/quality.dart';
import 'package:lxserver_mobile/features/player/player_screen.dart';
import 'package:lxserver_mobile/features/player/lyrics.dart';
import 'package:lxserver_mobile/shared/music_badge.dart';
import 'package:lxserver_mobile/shared/song_tile.dart';

void main() {
  testWidgets('Only labels containing Chinese receive baseline correction', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Column(
            children: [
              MusicBadge('无损', tone: BadgeTone.green),
              MusicBadge('24bit 无损', tone: BadgeTone.yellow),
              MusicBadge('QQ', tone: BadgeTone.green),
              MusicBadge('Hi-Res', tone: BadgeTone.yellow),
            ],
          ),
        ),
      ),
    );
    for (final label in ['无损', '24bit 无损', 'QQ', 'Hi-Res']) {
      final text = find.text(label);
      final badge = find.ancestor(of: text, matching: find.byType(MusicBadge));
      final style = tester.widget<Text>(text).style!;
      final chinese = label.contains('无损');
      expect(style.height, 1.3);
      expect(
        style.leadingDistribution,
        chinese ? null : TextLeadingDistribution.even,
      );
      expect(
        tester.getCenter(text).dy - tester.getCenter(badge).dy,
        closeTo(chinese ? -.8 : 0, .01),
      );
    }
  });

  testWidgets(
    'List badge prefers remembered track quality and resets to metadata',
    (tester) async {
      final c = AppController();
      addTearDown(c.dispose);
      final session = Session(
        Uri.parse('https://example.test'),
        'fixture',
        'fixture-token',
      );
      c.session = session;
      final song = Song({
        'songmid': 'badge-fixture',
        'quality': 'master',
      }, MusicSource.tx);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SongTile(song: song, controller: c, queue: [song]),
          ),
        ),
      );
      expect(find.text('Master'), findsOneWidget);
      for (final quality in ['atmos', '128k']) {
        c.player.cache.success(
          c.player.cache.scope(session),
          song,
          PlaybackResource(
            Uri.parse('https://media.test/audio'),
            quality,
            quality,
          ),
          preference: 'flac',
        );
        c.player.refreshQualityAvailability();
        await tester.pump();
        expect(find.text(AudioQuality.labelOf(quality)), findsOneWidget);
        expect(find.text('Master'), findsNothing);
      }
      c.player.restoreQuality('hires');
      c.player.refreshQualityAvailability();
      await tester.pump();
      expect(find.text('标准'), findsOneWidget);
      c.player.cache.forget(c.player.cache.scope(session), song);
      c.player.refreshQualityAvailability();
      await tester.pump();
      expect(find.text('Master'), findsOneWidget);
    },
  );
  test('Badges reflect track metadata, not platform possibilities', () {
    expect(QualityPolicy.badge(Song({}, MusicSource.tx)), null);
    expect(
      QualityPolicy.badge(
        Song({
          'types': [
            {'type': 'flac'},
            {'type': 'hires', 'isPlatformQuality': true},
          ],
        }, MusicSource.tx),
      ),
      '无损',
    );
    expect(
      QualityPolicy.badge(
        Song({
          'meta': {
            '_qualitys': {'flac24bit': {}},
          },
        }, MusicSource.kg),
      ),
      'Hi-Res',
    );
    expect(
      QualityPolicy.badge(Song({'quality': 'master'}, MusicSource.tx)),
      'Master',
    );
  });
  testWidgets('Source and quality remain visible before a long artist name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController();
    addTearDown(c.dispose);
    final song = Song({
      'name': '歌曲名称' * 10,
      'singer': '很长的歌手名称' * 20,
      'types': [
        {'type': 'flac', 'size': '28.00 MB'},
      ],
    }, MusicSource.tx);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongTile(song: song, controller: c, queue: [song]),
        ),
      ),
    );
    expect(find.text('QQ').hitTestable(), findsOneWidget);
    expect(find.text('无损').hitTestable(), findsOneWidget);
    await tester.longPress(find.text('无损'));
    await tester.pumpAndSettle();
    expect(find.text('FLAC · 28.00 MB'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('QQ')).dx,
      lessThan(tester.getTopLeft(find.text(song.singer)).dx),
    );
    expect(tester.takeException(), null);
  });
  test(
    'Lossless failure falls back in platform order without changing tracks',
    () async {
      final calls = <String>[];
      final song = Song({}, MusicSource.tx);
      final result = await loadWithQualityFallback(
        song: song,
        preference: 'flac',
        isCurrent: () => true,
        onAttempt: (_) {},
        resolve: (quality) async {
          calls.add(quality);
          if (quality == 'flac') throw const ApiFailure('Unavailable');
          return PlaybackResource(
            Uri.parse('https://media.test/audio'),
            quality,
            quality,
          );
        },
        load: (_) async {},
      );
      expect(calls, ['flac', '320k']);
      expect(result!.reportedQuality, '320k');
      expect(QualityPolicy.attempts(song, '128k'), ['128k']);
    },
  );
  test(
    'Mismatched and unloadable resources fall back; auth never retries',
    () async {
      final song = Song({}, MusicSource.tx);
      final loaded = <String>[];
      final result = await loadWithQualityFallback(
        song: song,
        preference: 'flac',
        isCurrent: () => true,
        onAttempt: (_) {},
        resolve: (quality) async => PlaybackResource(
          Uri.parse('https://media.test/audio'),
          quality,
          quality == 'flac' ? '128k' : quality,
        ),
        load: (resource) async {
          loaded.add(resource.requestedQuality);
          if (resource.requestedQuality == '320k') {
            throw StateError('decode failed');
          }
        },
      );
      expect(loaded, ['320k', '128k']);
      expect(result!.reportedQuality, '128k');
      var calls = 0;
      await expectLater(
        loadWithQualityFallback(
          song: song,
          preference: 'flac',
          isCurrent: () => true,
          onAttempt: (_) {},
          resolve: (_) async {
            calls++;
            throw const ApiFailure('Expired', unauthorized: true);
          },
          load: (_) async {},
        ),
        throwsA(
          isA<ApiFailure>().having((e) => e.unauthorized, 'unauthorized', true),
        ),
      );
      expect(calls, 1);
    },
  );
  test('Cancellation stops fallback and exhaustion is surfaced', () async {
    var current = true;
    var calls = 0;
    final song = Song({}, MusicSource.mg);
    expect(
      await loadWithQualityFallback(
        song: song,
        preference: 'flac',
        isCurrent: () => current,
        onAttempt: (_) {},
        resolve: (_) async {
          calls++;
          current = false;
          throw const ApiFailure('Unavailable');
        },
        load: (_) async => fail('Stale resource loaded'),
      ),
      isNull,
    );
    expect(calls, 1);
    await expectLater(
      loadWithQualityFallback(
        song: song,
        preference: '128k',
        isCurrent: () => true,
        onAttempt: (_) {},
        resolve: (_) async => throw const ApiFailure('Unavailable'),
        load: (_) async {},
      ),
      throwsA(isA<ApiFailure>()),
    );
  });
  test(
    'Lossless is the default preference and invalid stored values reset safely',
    () {
      final c = AppController();
      addTearDown(c.dispose);
      expect(c.player.preferredQuality, 'flac');
      c.player.restoreQuality('320k');
      expect(c.player.preferredQuality, '320k');
      c.player.restoreQuality('invalid');
      expect(c.player.preferredQuality, 'flac');
    },
  );
  test(
    'Sparse old metadata never downgrades a lossless preference to standard',
    () {
      final song = Song({
        'types': [
          {'type': '128k'},
          {'type': '320k'},
          {'type': 'flac', 'isPlatformQuality': true},
        ],
      }, MusicSource.kw);
      expect(QualityPolicy.initial(song, 'flac'), 'flac');
      expect(
        QualityPolicy.initial(
          Song({
            'types': [
              {'type': '128k'},
            ],
          }, MusicSource.tx),
          'flac',
        ),
        'flac',
      );
      expect(QualityPolicy.initial(song, '128k'), '128k');
      expect(QualityPolicy.selectable(song).map((v) => v.id), contains('flac'));
      expect(QualityPolicy.advertised(song), isNot(contains('flac')));
    },
  );
  test('Missing metadata can request lossless; platform limits exclude unsupported advanced modes', () {
    final song = Song({}, MusicSource.mg);
    expect(QualityPolicy.initial(song, 'flac'), 'flac');
    expect(QualityPolicy.initial(song, 'master'), 'flac');
    expect(QualityPolicy.selectable(song).map((v) => v.id), [
      '128k',
      '320k',
      'flac',
    ]);
  });
  test('Playback metadata preserves server quality and does not invent a missing type', () async {
    var response = <String, dynamic>{
      'url': 'https://media.test/audio',
      'type': '320k',
    };
    final api = LxApi(
      client: MockClient((request) async {
        expect(jsonDecode(request.body)['quality'], 'flac');
        return http.Response(jsonEncode(response), 200);
      }),
    );
    addTearDown(api.close);
    final session = Session(
      Uri.parse('https://example.test'),
      'test',
      'fixture-token',
    );
    final resource = await api.resolvePlayback(
      session,
      Song({}, MusicSource.kw),
      quality: 'flac',
    );
    expect(resource.requestedQuality, 'flac');
    expect(resource.reportedQuality, '320k');
    response = {'url': 'https://media.test/audio'};
    expect(
      (await api.resolvePlayback(
        session,
        Song({}, MusicSource.kw),
        quality: 'flac',
      )).reportedQuality,
      null,
    );
  });
  testWidgets(
    'Cover and lyrics swipe without duplicated controls or automatic horizontal jumps',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController();
      c.player.enqueue(
        Session(Uri.parse('https://example.test'), 'test', 'fixture-token'),
        Song({
          'name': 'Test',
          'singer': 'Artist',
          '_types': {
            '128k': {'size': '4.25 MB'},
            'flac': {'size': '0 B'},
          },
        }, MusicSource.kw),
      );
      c.player.index = 0;
      c.player.lyrics = Lyrics.parse({
        'lyric': '[00:00.00]Line one\n[00:02.00]Line two',
      });
      c.player.duration = const Duration(seconds: 30);
      c.player.reportedQuality = 'flac';
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(player: c.player, controller: c),
        ),
      );
      final pager = find.byKey(const ValueKey('player-pages'));
      final queueIcon = find.byIcon(Icons.queue_music_rounded);
      void expectTabsCentered() {
        final queueCenter = tester.getCenter(queueIcon).dy;
        for (final tab in ['封面', '歌词']) {
          expect(tester.getCenter(find.text(tab)).dy, closeTo(queueCenter, .1));
        }
      }

      expectTabsCentered();
      await tester.drag(pager, const Offset(-330, 0));
      await tester.pumpAndSettle();
      expectTabsCentered();
      expect(find.text('Line one'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      await tester.drag(pager, const Offset(330, 0));
      await tester.pumpAndSettle();
      c.player.position = const Duration(seconds: 3);
      c.player.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.widget<PageView>(pager).controller!.page, closeTo(0, .01));
      c.player.error = '请求无损，音源返回标准';
      c.player.notifyListeners();
      await tester.pump();
      await tester.tap(find.byTooltip('歌曲更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('音质选择'));
      await tester.pumpAndSettle();
      expect(find.text('音质'), findsOneWidget);
      expect(find.text('128 kbps · 4.25 MB'), findsOneWidget);
      expect(find.text('标注大小仅供参考，以实际文件为准。'), findsOneWidget);
      expect(find.text('重新尝试首选音质'), findsNothing);
      expect(find.text('FLAC'), findsOneWidget);
      expect(find.text('Hi-Res'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('unverified-quality-options')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hi-Res'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('quality-sheet')),
          matching: find.text('请求无损，音源返回标准'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
