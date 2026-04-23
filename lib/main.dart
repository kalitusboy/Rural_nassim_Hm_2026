import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/home_screen.dart';

void main() => runApp(const RuralNassimApp());

class RuralNassimApp extends StatelessWidget {
  const RuralNassimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'إحصاء السكن الريفي 2026',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF0D47A1),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        fontFamily: 'Cairo',
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0D47A1), foregroundColor: Colors.white, centerTitle: true, elevation: 4),
        elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2))),
        cardTheme: CardTheme(elevation: 6, shadowColor: Colors.black.withOpacity(0.06), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate],
      supportedLocales: const [Locale('ar', '')],
      locale: const Locale('ar', ''),
      home: const HomeScreen(),
    );
  }
}
