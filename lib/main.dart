import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'utils/global.dart';
import 'planner/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(
    MaterialApp(
      navigatorKey: navigatorKey,
      title: 'ChronoPilot Go',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xff176b61),
      ),
      home: const PlannerApp(),
    ),
  );
}
