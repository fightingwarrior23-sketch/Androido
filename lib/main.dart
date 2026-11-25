import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/l10n.dart';
import 'services/native.dart';
import 'services/settings.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.i.load();
  L10n.i.setLang(AppSettings.i.lang);
  Native.init();
  runApp(const StamperApp());
}

class StamperApp extends StatelessWidget {
  const StamperApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3F51B5);
    return ListenableBuilder(
      listenable: L10n.i,
      builder: (_, __) => MaterialApp(
        title: 'Lecture Stamper',
        debugShowCheckedModeBanner: false,
        locale: Locale(L10n.i.lang),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
