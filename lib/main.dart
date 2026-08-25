import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'modules/bosquejos/vista_editor.dart'; // Importa el archivo del editor
import 'package:flutter/foundation.dart' show kIsWeb;

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();

//   // Inicialización de Supabase local en Docker
//   await Supabase.initialize(
//     url: 'http://192.168.0.149:55021', 
//     anonKey: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH', // Tu clave Publishable activa
//   );

//   runApp(const MiAppBiblica());
// }
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🚀 DIRECCIÓN INTELIGENTE: Si es Web usa localhost, si es celular usa la IP de la red Wi-Fi
  final String urlBaseSupabase = kIsWeb 
      ? 'http://localhost:55021' 
      : 'https://qvbojzmtdbrrahtewrrr.supabase.co/rest/v1/'; // Reemplázala por tu IPv4 real de la PC

  await Supabase.initialize(
    url: urlBaseSupabase,
    anonKey: 'sb_publishable_DaWE6HlrHwmTJAMeWOIyEQ_xOih2tAG',
  );

  runApp(const MiAppBiblica());
}

class MiAppBiblica extends StatelessWidget {
  const MiAppBiblica({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bosquejos y Biblia',
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
      
      home: const PantallaPrincipalBase(),
    );
  }
}

// class PantallaPrincipalBase extends StatelessWidget {
//   const PantallaPrincipalBase({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return const Scaffold( 
//       body: SafeArea(
//         // CORREGIDO: Llama a la clase del editor que no requiere parámetros obligatorios
//         child: VistaEditorBosquejo(), 
//       ),
//     );
//   }
// }
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

