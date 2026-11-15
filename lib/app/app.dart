import 'package:flutter/material.dart';

import 'dart:async';

import '../features/connection/login_screen.dart';
import 'home.dart';
import 'controller.dart';
import 'theme.dart';

class LxApp extends StatefulWidget {
  const LxApp({super.key, required this.controller});
  final AppController controller;
  @override
  State<LxApp> createState() => _LxAppState();
}

class _LxAppState extends State<LxApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  AppController get controller => widget.controller;
  bool _hadSession = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hadSession = controller.session != null;
    controller.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    final hasSession = controller.session != null;
    if (_hadSession && !hasSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigator.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
    _hadSession = hasSession;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(controller.flushPlayback());
      unawaited(controller.flushBrowseState());
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LXServer Mobile',
    navigatorKey: _navigator,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: lxGreen,
        brightness: Brightness.light,
      ).copyWith(primary: lxGreen, surface: Colors.white, onSurface: lxInk),
      scaffoldBackgroundColor: lxCanvas,
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, color: lxInk),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lxCanvas,
        foregroundColor: lxInk,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2EAE5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2EAE5)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    home: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.restoring) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return controller.session == null
            ? LoginScreen(controller: controller)
            : MusicHome(controller: controller);
      },
    ),
  );
}
