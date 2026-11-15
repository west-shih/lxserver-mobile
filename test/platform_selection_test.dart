import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/app.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  AppController controller() => AppController(
    api: LxApi(
      client: MockClient((r) async {
        if (r.url.path == '/api/custom-source/list') {
          return http.Response(
            jsonEncode([
              {
                'enabled': true,
                'status': 'success',
                'supportedSources': ['tx'],
              },
            ]),
            200,
          );
        }
        return http.Response('{"list":[],"tags":[],"sortList":[]}', 200);
      }),
    ),
  );

  test('Platform choices restore by stable identity without querying a label count', () async {
    final c = controller();
    await c.restore();
    c.session = Session(
      Uri.parse('https://example.test'),
      'fixture',
      'fixture-token',
    );
    await c.changeSource(MusicSource.wy);
    await c.selectDiscoverySource(MusicSource.tx);
    final restored = controller();
    await restored.restore();
    expect(restored.aggregate, false);
    expect(restored.source, MusicSource.wy);
    expect(restored.discovery.source, MusicSource.tx);
    expect(restored.discovery.aggregate, false);
    await c.selectDiscoverySource(MusicSource.tx);
    await c.selectAggregate();
    final all = controller();
    await all.restore();
    expect(all.aggregate, true);
    expect(all.discovery.aggregate, true);
    c.dispose();
    restored.dispose();
    all.dispose();
  });

  test('Missing, corrupt and obsolete preferences fall back without breaking startup', () async {
    for (final value in [
      '',
      '{bad json',
      '{"search":"removed","discovery":"removed"}',
    ]) {
      FlutterSecureStorage.setMockInitialValues({
        'lx.platformSelection': value,
      });
      final c = controller();
      await c.restore();
      expect(c.aggregate, false);
      expect(c.source, MusicSource.wy);
      expect(c.discovery.source, MusicSource.wy);
      expect(c.authError, isNull);
      c.dispose();
    }
  });

  test('Availability changes clear an unavailable search filter and retain valid platforms', () async {
    final c = controller();
    await c.restore();
    c.session = Session(
      Uri.parse('https://example.test'),
      'fixture',
      'fixture-token',
    );
    await c.changeSource(MusicSource.wy);
    await c.refreshSources();
    expect(c.availableSources, [MusicSource.tx]);
    expect(c.aggregate, true);
    expect(c.discovery.aggregate, true);
    c.dispose();
  });

  testWidgets(
    'Search toggles selected platform off and both rows omit extra action buttons',
    (tester) async {
      final c = controller();
      await c.restore();
      c.session = Session(
        Uri.parse('https://example.test'),
        'fixture',
        'fixture-token',
      );
      c.offlineMode = true;
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('全部'), findsNothing);
      expect(find.byTooltip('音源状态'), findsNothing);
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((chip) => chip.selected)
            .length,
        1,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '酷我'));
      await tester.pumpAndSettle();
      expect(c.aggregate, false);
      await tester.tap(find.widgetWithText(ChoiceChip, '酷我'));
      await tester.pumpAndSettle();
      expect(c.aggregate, true);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('歌单'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('刷新歌单'), findsNothing);
      expect(c.discovery.aggregate, false);
      expect(c.discovery.source, MusicSource.wy);
      expect(find.text('全部分类'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '酷我'));
      await tester.pumpAndSettle();
      expect(c.discovery.aggregate, false);
      expect(find.text('全部分类'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '酷我'));
      await tester.pumpAndSettle();
      expect(c.discovery.aggregate, true);
      expect(find.text('全部分类'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
