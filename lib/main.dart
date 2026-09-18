import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:mi_app_biblica/core/config.dart';
import 'package:mi_app_biblica/ui/bosquejos/vista_editor.dart';
import 'package:mi_app_biblica/ui/lector/splash_screen_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Las credenciales pueden sobrescribirse en compilación con:
// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );

  runApp(const MiAppBiblica());
}

class MiAppBiblica extends StatelessWidget {
  const MiAppBiblica({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Biblia del Predicador',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF1A73E8),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
      ),

      // CONFIGURACIÓN DE IDIOMAS PARA EL EDITOR DE SERMONES
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es'),
        Locale('en'),
      ],

      home: const SplashScreenView(),
    );
  }
}

// Busca esta clase al final de tu lib/main.dart y déjala exactamente así:
class PantallaPrincipalBase extends StatelessWidget {
  const PantallaPrincipalBase({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: VistaEditorBosquejo(), // Eliminado el 'const' de aquí adentro para corregir el error
      ),
    );
  }
}