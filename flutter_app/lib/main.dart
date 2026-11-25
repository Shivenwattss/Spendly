import 'package:flutter/material.dart';
import 'screens/app.dart';

void main() => runApp(const SpendlyApp());

class SpendlyApp extends StatelessWidget {
  const SpendlyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Spendly',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4778D8)),
          scaffoldBackgroundColor: const Color(0xFFF5F6F8),
          cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.only(bottom: 10)),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7EA6F5), brightness: Brightness.dark),
        ),
        home: const AppHome(),
      );
}
