import 'package:flutter/material.dart';
import 'package:wishiz/app/dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await createApp());
}
