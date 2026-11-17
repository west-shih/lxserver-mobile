import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/app/app.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';

void main() {
  for (final size in [
    const Size(360, 640),
    const Size(393, 852),
    const Size(320, 568),
  ]) {
    testWidgets('Login fits portrait $size without scrolling', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController()..restoring = false;
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.maxScrollExtent, 0);

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(scroll.position.maxScrollExtent, 0);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  testWidgets('Login validates required fields without contacting a server', (
    tester,
  ) async {
    final c = AppController()..restoring = false;
    await tester.pumpWidget(LxApp(controller: c));
    await tester.ensureVisible(find.text('连接并登录'));
    await tester.tap(find.text('连接并登录'));
    await tester.pumpAndSettle();
    expect(find.text('请输入账号'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(find.text('填写完整的 http:// 或 https:// 地址'), findsOneWidget);
    expect(c.session, null);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('Search layout fits narrow devices and has five source choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController()
      ..restoring = false
      ..session = Session(
        Uri.parse('https://example.test'),
        'test',
        'test-token',
      );
    await tester.pumpWidget(LxApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('全部'), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('search-platforms')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('咪咕'), findsOneWidget);
    expect(find.byKey(const ValueKey('top-search-0')), findsOneWidget);
    expect(find.text('找到你的下一首。'), findsNothing);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
