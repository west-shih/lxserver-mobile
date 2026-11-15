import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/controller.dart';
import 'features/player/system_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  await initializeSystemAudio(controller.player);
  runApp(LxApp(controller: controller));
  controller.restore();
}
