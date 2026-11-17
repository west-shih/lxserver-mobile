import 'package:flutter/widgets.dart';

import '../app/controller.dart';

/// Keeps page position independently from content cache eviction.
mixin RememberedPage<T extends StatefulWidget> on State<T> {
  AppController get browseApp;
  String get browseKey;
  ScrollController get browseScroll;
  Map<String, dynamic> saveView();
  void restoreView(Map<String, dynamic> value);
  bool _rememberReady = false;

  void rememberView() {
    if (!_rememberReady || browseApp.session == null) return;
    final old = browseApp.pageState(browseKey);
    browseApp.rememberPage(browseKey, {
      ...saveView(),
      'offset': browseScroll.hasClients
          ? browseScroll.offset
          : old['offset'] ?? 0,
    });
  }

  void finishRemembering() {
    rememberView();
    _rememberReady = false;
    browseScroll.removeListener(rememberView);
  }

  @override
  void initState() {
    super.initState();
    final value = browseApp.pageState(browseKey);
    restoreView(value);
    _rememberReady = true;
    browseScroll.addListener(rememberView);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !browseScroll.hasClients) return;
      final offset = value['offset'];
      if (offset is num && offset.isFinite && offset >= 0) {
        browseScroll.jumpTo(
          offset.toDouble().clamp(0, browseScroll.position.maxScrollExtent),
        );
      }
    });
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    rememberView();
  }

  @override
  void dispose() {
    finishRemembering();
    super.dispose();
  }
}
