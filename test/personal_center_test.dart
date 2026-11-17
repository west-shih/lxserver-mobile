import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/app/app.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/player/player_screen.dart';
import 'package:lxserver_mobile/features/player/quality.dart';
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
      final c = fixture()..pagedCollections = true;
      await tester.pumpWidget(LxApp(controller: c));
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('刷新我的收藏'), findsNothing);
      expect(find.text('缓存设置'), findsNothing);
      await tester.tap(find.byTooltip('本机下载'));
      await tester.pumpAndSettle();
      expect(find.text('下载任务'), findsOneWidget);
      expect(find.byTooltip('缓存设置'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('个人中心'));
      await tester.pumpAndSettle();
      expect(find.text('离线模式'), findsOneWidget);
      expect(find.text('fixture'), findsOneWidget);
      expect(find.text('账号与服务器'), findsNothing);
      expect(find.text('退出登录 / 切换服务器'), findsNothing);
      await tester.tap(find.byTooltip('退出登录 / 切换服务器'));
      await tester.pumpAndSettle();
      expect(find.text('退出当前账号？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(c.session, isNotNull);
      expect(find.text('浏览缓存容量'), findsNothing);
      expect(find.byTooltip('清理浏览缓存'), findsNothing);
      FlutterSecureStorage.setMockInitialValues({});
      await tester.ensureVisible(find.text('首选音质'));
      expect(
        tester.getTopRight(find.text('每页 20 项')).dx,
        closeTo(
          tester
              .getTopRight(
                find.text(AudioQuality.labelOf(c.player.preferredQuality)),
              )
              .dx,
          0.5,
        ),
      );
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
      expect(find.text('缓存设置'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('浏览缓存容量'), 200);
      expect(find.text('浏览缓存容量'), findsOneWidget);
      expect(find.byTooltip('清理浏览缓存'), findsOneWidget);
      expect(find.textContaining('下载'), findsNothing);
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
