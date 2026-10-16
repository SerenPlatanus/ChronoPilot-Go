import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'utils/global.dart';
import 'planner/app.dart';
import 'planner/repository.dart';
import 'ui/styles.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(ChronoPilotRoot(styles: await StyleController.load()));
}

class ChronoPilotRoot extends StatelessWidget {
  final StyleController styles;
  final PlannerRepository? repository;
  const ChronoPilotRoot({super.key, required this.styles, this.repository});
  @override
  Widget build(BuildContext context) => StyleScope(
    controller: styles,
    child: ListenableBuilder(
      listenable: styles,
      builder: (_, __) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'ChronoPilot Go',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        theme: styles.theme,
        // Apply the complete palette atomically; no partial Material theme lerp.
        themeAnimationDuration: Duration.zero,
        home: PlannerApp(repository: repository),
      ),
    ),
  );
}
