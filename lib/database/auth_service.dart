import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  Future<void> iniciarSesionConGoogle() async {
    if (kIsWeb) {
      // 🌐 CONFIGURACIÓN WEB: Redirección directa y costo $0 de red en navegadores
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        // Al compilar con Vercel o Firebase, especifica la URL de tu página web de producción
        redirectTo: 'https://vercel.app',
      );
    } else {
      // 📱 CONFIGURACIÓN NATIVA ANDROID: Lanza la ventana emergente oficial del teléfono
      // Reemplaza con tu Web Client ID obtenido en el panel de Google Cloud
      const clientIdWeb = 'TU_OAUTH_WEB_CLIENT_://googleusercontent.com'; 
      
      final googleSignIn = GoogleSignIn(serverClientId: clientIdWeb);
      final googleUser = await googleSignIn.signIn();
      
      if (googleUser != null) {
        final googleAuth = await googleUser.authentication;
        final accessToken = googleAuth.accessToken;
        final idToken = googleAuth.idToken;

        if (idToken != null && accessToken != null) {
          // Intercambia los tokens nativos con Supabase para abrir la sesión de forma segura
          await _supabase.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
            accessToken: accessToken,
          );
        }
      }
    }
  }

  // Cerrar sesión global
  Future<void> cerrarSesion() async {
    await _supabase.auth.signOut();
  }
}
