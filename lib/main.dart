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
  final initial = await Future.wait<Object?>([
    StyleController.load(),
    PlannerRepository.openLastAccount()
        .then<PlannerRepository?>((r) => r)
        .catchError((Object _) => null),
  ]);
  runApp(
    ChronoPilotRoot(
      styles: initial[0] as StyleController,
      repository: initial[1] as PlannerRepository?,
      restoreAccount: true,
    ),
  );
}

class ChronoPilotRoot extends StatelessWidget {
  final StyleController styles;
  final PlannerRepository? repository;
  final bool restoreAccount;
  const ChronoPilotRoot({
    super.key,
    required this.styles,
    this.repository,
    this.restoreAccount = false,
  });
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: PlannerApp(
          repository: repository,
          restoreAccount: restoreAccount,
        ),
      ),
    ),
  );
}
