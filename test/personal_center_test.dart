import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/app/app.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/player/player_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

AppController fixture() => AppController()
  ..restoring = false
  ..offlineMode = true
  ..session = Session(
    Uri.parse('https://example.test'),
    'fixture',
    'fixture-token',
  );

void main() {
  testWidgets(
    'Compact library opens downloads and personal storage without a refresh button',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixture();
      await tester.pumpWidget(LxApp(controller: c));
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('刷新我的收藏'), findsNothing);
      expect(find.text('缓存设置'), findsNothing);
      await tester.tap(find.byTooltip('本机下载'));
      await tester.pumpAndSettle();
      expect(find.text('下载任务'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('个人中心'));
      await tester.pumpAndSettle();
      expect(find.text('离线模式'), findsOneWidget);
      expect(find.text('fixture'), findsOneWidget);
      FlutterSecureStorage.setMockInitialValues({});
      await tester.tap(find.text('首选音质'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('高品质'));
      await tester.pumpAndSettle();
      expect(c.player.preferredQuality, '320k');
      expect(await c.store.readQuality(), '320k');
      expect(c.player.current, null);
      await tester.tap(find.text('缓存设置'));
      await tester.pumpAndSettle();
      expect(find.text('自动缓存上限'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('Current song menu is available from cover and lyrics pages', (
    tester,
  ) async {
    final c = fixture();
    c.player.enqueue(
      c.session!,
      Song({
        'songmid': 'fixture',
        'name': 'Fixture song',
        'singer': 'Artist',
      }, MusicSource.kw),
    );
    c.player.index = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(player: c.player, controller: c),
      ),
    );
    await tester.tap(find.byTooltip('歌曲更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('音质选择'), findsOneWidget);
    expect(find.text('立即播放'), findsNothing);
    expect(find.text('下载到手机'), findsOneWidget);
    expect(find.text('信息'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌词'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('歌曲更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('信息'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
