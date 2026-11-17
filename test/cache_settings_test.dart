import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/browse_cache.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/settings/personal_center_screen.dart';
import 'package:lxserver_mobile/features/local_media/local_media_screens.dart';

class UsageCache extends BrowseCache {
  int usage = 3 * 1024 * 1024;
  @override
  Future<int> bytes() async => usage;
  @override
  Future<void> clear() async {
    usage = 0;
  }
}

void main() {
  testWidgets(
    'Total includes browsing files and refreshes after clearing and returning',
    (tester) async {
      final cache = UsageCache();
      final c =
          AppController(
              api: LxApi(
                client: MockClient((_) async => http.Response('{}', 200)),
                browseCache: cache,
              ),
            )
            ..restoring = false
            ..session = Session(
              Uri.parse('https://example.test'),
              'fixture',
              'fixture-token',
            );
      await tester.pumpWidget(
        MaterialApp(home: PersonalCenterScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      expect(find.text('3.0 MB'), findsOneWidget);
      await tester.tap(find.text('缓存设置'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('cache-total-usage')))
            .data,
        '3.0 MB',
      );
      expect(find.textContaining('下载'), findsNothing);
      await tester.scrollUntilVisible(find.byTooltip('清理浏览缓存'), 160);
      await tester.tap(find.byTooltip('清理浏览缓存'));
      await tester.pumpAndSettle();
      expect(find.text('清理浏览缓存？'), findsOneWidget);
      expect(cache.usage, 3 * 1024 * 1024);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cache.usage, 3 * 1024 * 1024);
      await tester.tap(find.byTooltip('清理浏览缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清理'));
      await tester.pumpAndSettle();
      expect(cache.usage, 0);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('cache-total-usage')),
        -160,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('cache-total-usage')))
            .data,
        '0 KB',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('3.0 MB'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  for (final scale in [1.0, 1.6]) {
    testWidgets('Cache cards fit a narrow screen at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(
        api: LxApi(
          client: MockClient((_) async => http.Response('{}', 200)),
          browseCache: UsageCache(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: CacheSettingsScreen(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byTooltip('清空音频缓存'), 160);
      await tester.tap(find.byTooltip('清空音频缓存'));
      await tester.pumpAndSettle();
      expect(find.text('清理音频缓存？'), findsOneWidget);
      expect(find.textContaining('主动下载的文件会保留'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byTooltip('清理浏览缓存'), 160);
      expect(find.text('浏览缓存容量'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
