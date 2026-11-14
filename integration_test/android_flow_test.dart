import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lxserver_mobile/app/app.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/player/player_views.dart';
import 'package:lxserver_mobile/features/player/playback_mode.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android aggregate search, collections, discovery, lyrics and logout',
    (tester) async {
      // The same define adds an Android package suffix in Gradle. Never clear normal app data.
      expect(
        const bool.fromEnvironment('LX_INTEGRATION'),
        true,
        reason: 'Run with --dart-define=LX_INTEGRATION=true to isolate test storage',
      );
      final mediaRoot = await Directory.systemTemp.createTemp(
        'lx-fixture-media-',
      );
      final c = AppController(mediaDirectory: () => Future.value(mediaRoot))
        ..restoring = false;
      await c.store.clear();
      Future<void> waitUntil(bool Function() condition) async {
        for (var i = 0; i < 100 && !condition(); i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(condition(), true);
      }

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        final bytes = await binding.takeScreenshot(name);
        await File('${Directory.systemTemp.path}/lx-$name.png')
            .writeAsBytes(bytes);
      }

      Future<void> tab(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pump();
      }

      await tester.pumpWidget(LxApp(controller: c));
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'http://10.0.2.2:18765',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'fixture-user');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'fixture-password',
      );
      await tester.ensureVisible(find.text('连接并登录'));
      await tester.tap(find.text('连接并登录'));
      await waitUntil(() => c.session != null && !c.checkingSources);
      expect(c.availableSources, isNot(contains(MusicSource.mg)));
      expect(c.availableSources.length, 4);
      expect(c.availability?.readyCount, 1);
      await c.search('partial');
      expect(c.songs.length, 3);
      expect(c.sourceFailures.keys, contains(MusicSource.kg));
      expect(c.availableSources, contains(MusicSource.kg));
      await c.search('测试');
      await waitUntil(() => c.serverFiles.available);
      await tester.pumpAndSettle();
      expect(c.songs.length, 4);
      expect(c.searchError, null);
      expect(find.text('已缓存'), findsNothing);
      expect(find.text('已下载'), findsNothing);
      await binding.convertFlutterSurfaceToImage();
      await capture('aggregate');

      await tab('我的');
      await waitUntil(() => !c.library.loading);
      expect(find.text('我的喜欢'), findsOneWidget);
      expect(find.text('测试歌单'), findsOneWidget);
      await capture('library');
      await tester.tap(find.text('我的喜欢'));
      await tester.pumpAndSettle();
      expect(find.text('接口测试歌曲'), findsOneWidget);
      await tester.tap(find.text('接口测试歌曲'));
      await waitUntil(
        () => c.player.position.inMilliseconds > 0 && !c.player.loadingLyrics,
      );
      expect(c.player.error, null);
      expect(c.player.duration.inSeconds, greaterThan(0));
      expect(c.player.lyrics.lines.length, 3);
      expect(c.player.lyrics.lines.first.translation, 'First line');
      expect(c.player.requestedQuality, 'flac');
      expect(c.player.reportedQuality, 'flac');
      await waitUntil(() => c.localMedia.badge(c.player.current!) == '已缓存');
      await tester.tap(find.byType(MiniPlayer));
      await tester.pumpAndSettle();
      await capture('player-cover');
      await tester.tap(find.text('已缓存'));
      await tester.pumpAndSettle();
      expect(find.text('清除本机缓存？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('歌曲更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('信息'));
      await tester.pumpAndSettle();
      expect(find.text('存储'), findsOneWidget);
      expect(find.text('本机'), findsOneWidget);
      expect(find.text('LXServer'), findsOneWidget);
      await capture('song-storage');
      Navigator.of(tester.element(find.text('存储'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('歌曲评论'));
      await tester.pumpAndSettle();
      await waitUntil(() => find.text('Fixture comment').evaluate().isNotEmpty);
      await capture('comments');
      await tester.tap(find.byTooltip('关闭评论'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('player-pages')),
        const Offset(-340, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('第一行歌词'), findsOneWidget);
      await capture('lyrics');
      await tester.tap(find.text('第三行歌词'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.player.position.inSeconds, greaterThanOrEqualTo(4));
      await c.player.toggle();
      expect(c.player.playing, false);
      final pausedAt = c.player.position;
      await tester.tap(find.byTooltip('歌曲更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('音质选择'));
      await tester.pumpAndSettle();
      await capture('quality');
      await tester.tap(
        find.byKey(const ValueKey('unverified-quality-options')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('高品质'));
      await tester.tap(find.text('高品质'));
      await waitUntil(
        () => !c.player.changingQuality && c.player.reportedQuality == '320k',
      );
      expect(c.player.playing, false);
      expect(
        (c.player.position - pausedAt).inMilliseconds.abs(),
        lessThan(800),
      );
      expect(c.player.preferredQuality, 'flac');
      expect(
        c.player.cache.successful(
          c.player.cache.scope(c.session!),
          c.player.current!,
          preference: 'flac',
        ),
        'flac',
      );
      await c.player.setPreferredQuality('hires');
      expect(await c.store.readQuality(), 'hires');
      final restarted = AppController(
        mediaDirectory: () => Future.value(mediaRoot),
      );
      await restarted.restore();
      expect(restarted.player.preferredQuality, 'hires');
      restarted.dispose();
      await c.player.changeQuality('flac24bit');
      expect(c.player.requestedQuality, 'flac');
      expect(c.player.reportedQuality, 'flac');
      expect(c.player.qualityFailed, false);
      expect(c.player.qualityNotice, isNot(contains('本机文件')));
      expect(c.player.preferredQuality, 'hires');
      await capture('quality-result');
      Navigator.of(tester.element(find.byKey(const ValueKey('quality-sheet'))))
          .pop();
      await tester.pumpAndSettle();
      await c.player.toggle();
      expect(c.player.playing, true);
      await c.player.changeQuality('hires');
      expect(c.player.reportedQuality, 'flac');
      expect(c.player.preferredQuality, 'hires');
      await waitUntil(() => c.player.playing);
      expect(c.player.error, null);
      expect(c.player.qualityNotice, isNot(contains('本机文件')));
      await c.player.toggle();
      final statsBefore = await c.api.read(c.session!, '/fixture/stats') as Map;
      await c.player.play(c.session!, c.player.current!);
      expect(c.player.reportedQuality, 'flac');
      expect(c.player.preferredQuality, 'hires');
      expect(c.player.error, null);
      final statsAfter = await c.api.read(c.session!, '/fixture/stats') as Map;
      expect(statsAfter['resolutionCount'], statsBefore['resolutionCount']);
      await c.player.toggle();
      await c.player.audio.stop();
      await c.localMedia.releasePlayback();
      await c.localMedia.clearCache();
      await c.api.read(c.session!, '/fixture/cache-enable');
      await c.player.retryPreferredQuality();
      expect(c.player.reportedQuality, 'flac');
      expect(c.player.preferredQuality, 'hires');
      expect(c.player.error, null);
      final cachedStats = await c.api.read(c.session!, '/fixture/stats') as Map;
      // Only Hi-Res was parsed; lossless was served from the server cache.
      expect(
        cachedStats['resolutionCount'],
        (statsAfter['resolutionCount'] as int) + 1,
      );
      expect(await c.store.readQuality(), 'hires');
      final intermediateErrors = <String>[];
      void observeRecovery() {
        if (c.player.resolving && c.player.error != null) {
          intermediateErrors.add(c.player.error!);
        }
      }

      c.player.addListener(observeRecovery);
      await c.player.play(
        c.session!,
        Song({
          'songmid': 'fixture-recovery',
          'name': '恢复测试歌曲',
          'singer': '测试数据',
        }, MusicSource.kw),
      );
      await tester.pump(const Duration(milliseconds: 300));
      c.player.removeListener(observeRecovery);
      expect(c.player.reportedQuality, 'hires');
      expect(c.player.error, null);
      expect(intermediateErrors, isEmpty);
      final recoveryStats =
          await c.api.read(c.session!, '/fixture/stats') as Map;
      expect(recoveryStats['lastExcluded'], ['fixture-bad']);
      expect(
        recoveryStats['resolutionCount'],
        (cachedStats['resolutionCount'] as int) + 2,
      );
      await c.player.toggle();
      await tester.drag(
        find.byKey(const ValueKey('player-pages')),
        const Offset(340, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('收起播放器'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      final originalSong = c.library.collections.first.songs.first;
      await c.localMedia.enqueue(
        c.session!,
        originalSong,
        c.player.preferredQuality,
      );
      await waitUntil(
        () => c.localMedia.downloads.length == 1 && c.localMedia.jobs.isEmpty,
      );
      expect(c.localMedia.badge(originalSong), '已下载');
      await c.localMedia.flushArtwork();
      expect(c.localMedia.artworkPath(originalSong), isNotNull);
      await tester.tap(find.byTooltip('本机下载'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已下载'));
      await tester.pumpAndSettle();
      await capture('local-downloads');
      expect(find.text('酷我'), findsOneWidget);
      expect(
        tester.widget<Image>(find.byType(Image).first).image,
        isA<FileImage>(),
      );
      await tester.tap(find.text('接口测试歌曲'));
      await waitUntil(
        () => c.player.position.inMilliseconds > 0 && !c.player.resolving,
      );
      expect(c.player.error, null);
      expect(c.player.qualityNotice, null);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('个人中心'));
      await tester.pumpAndSettle();
      await capture('personal-center');
      await tester.tap(find.text('缓存设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('256 MB').last);
      await tester.pumpAndSettle();
      expect(c.localMedia.cacheLimitMb, 256);
      await tester.tap(find.text('清空音频缓存'));
      await tester.pumpAndSettle();
      expect(c.localMedia.cacheBytes, 0);
      expect(c.localMedia.downloads.length, 1);
      await capture('cache-settings');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('歌手'));
      await tester.pumpAndSettle();
      expect(find.text('收藏测试歌手'), findsOneWidget);
      await tester.tap(find.text('专辑'));
      await tester.pumpAndSettle();
      expect(find.text('收藏测试专辑'), findsOneWidget);

      await tab('歌单');
      await waitUntil(() => !c.discovery.loading);
      await tester.pumpAndSettle();
      expect(c.discovery.error, null);
      expect(find.text('测试发现歌单'), findsOneWidget);
      await tester.tap(find.text('全部分类'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('流行'));
      await waitUntil(() => !c.discovery.loading);
      expect(c.discovery.tag, 'pop');
      await capture('discovery');
      await tester.tap(find.text('测试发现歌单'));
      await waitUntil(() => find.text('接口测试歌曲').evaluate().isNotEmpty);
      await c.player.reset();
      await c.localMedia.flush();
      await c.api.read(c.session!, '/fixture/go-offline');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox());
      await c.localMedia.deactivate();
      await c.localMedia.flush();
      c.dispose();
      final offline = AppController(
        mediaDirectory: () => Future.value(mediaRoot),
      );
      await offline.restore();
      expect(offline.offlineMode, true);
      expect(offline.session, isNotNull);
      expect(offline.localMedia.downloads.length, 1);
      expect(offline.localMedia.downloads.single.song.source, MusicSource.kw);
      expect(offline.localMedia.downloads.single.song.image, isNotEmpty);
      expect(
        offline.localMedia.artworkPath(
          offline.localMedia.downloads.single.song,
        ),
        isNotNull,
      );
      await tester.pumpWidget(LxApp(key: UniqueKey(), controller: offline));
      await tester.pumpAndSettle();
      await tab('我的');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('本机下载'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已下载'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('接口测试歌曲'));
      await waitUntil(
        () =>
            offline.player.position.inMilliseconds > 0 &&
            !offline.player.resolving,
      );
      expect(offline.player.error, null);
      expect(offline.player.qualityNotice, null);
      await capture('offline-downloads');
      offline.player.setMode(PlaybackMode.single);
      await offline.player.seek(
        offline.player.duration - const Duration(milliseconds: 200),
      );
      await tester.pump(const Duration(seconds: 1));
      await waitUntil(
        () =>
            !offline.player.resolving &&
            offline.player.playing &&
            offline.player.position.inSeconds < 5,
      );
      offline.player.setMode(PlaybackMode.order);
      await offline.player.seek(
        offline.player.duration - const Duration(milliseconds: 200),
      );
      await tester.pump(const Duration(seconds: 1));
      await waitUntil(
        () => !offline.player.playing && offline.player.position.inSeconds < 1,
      );
      // Logout while a private local-download route is open must dismiss it too.
      await offline.logout();
      await tester.pumpAndSettle();
      expect(find.text('连接并登录'), findsOneWidget);
      expect(offline.session, null);
      expect(await offline.store.read(), null);
      const storage = FlutterSecureStorage();
      await storage.delete(key: 'lx.server');
      expect(offline.player.current, null);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await offline.localMedia.flush();
      offline.dispose();
      expect(
        mediaRoot.absolute.path.startsWith(Directory.systemTemp.absolute.path),
        true,
      );
      await mediaRoot.delete(recursive: true);
    },
  );
}
