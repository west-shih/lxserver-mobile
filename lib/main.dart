import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  runApp(LxApp(controller: controller));
  controller.restore();
}
