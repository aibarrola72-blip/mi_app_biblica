// lib/database/auth_service.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  /// 🚀 FLUJO UNIFICADO DE INICIO DE SESIÓN CON GOOGLE
  Future<bool> iniciarSesionConGoogle() async {
    try {
      if (kIsWeb) {
        // 🌐 ENTORNO WEB: Autenticación nativa por redirección segura de Supabase
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'https://aibarrola72-blip.github.io/mi_app_biblica/',
        );
        return true;
      } else {
        // 📱 ENTORNO MÓVIL: Consumo de diálogos de Google Sign-In nativos del celular
        // Reemplaza por tu ID de cliente WEB de Google Cloud (requisito de Supabase para Android)
        const webClientId = '40946649762-pi30rq46mutt97ooitp4nam79ld72i3p.apps.googleusercontent.com';

        final GoogleSignIn googleSignIn = GoogleSignIn(
          serverClientId: webClientId,
        );
        
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) return false; // El pastor canceló el diálogo

        final googleAuth = await googleUser.authentication;
        final accessToken = googleAuth.accessToken;
        final idToken = googleAuth.idToken;

        if (accessToken == null || idToken == null) return false;

        // Inyectamos el ID Token directamente en el motor de seguridad de Supabase
        final response = await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );

        return response.user != null;
      }
    } catch (e) {
      print('Fallo crítico en el inicio de sesión con Google: $e');
      return false;
    }
  }

  /// 🚪 CERRAR SESIÓN (Limpia tokens de la memoria RAM y cookies web)
  Future<void> cerrarSesion() async {
    await _supabase.auth.signOut();
    if (!kIsWeb) {
      await GoogleSignIn().signOut();
    }
  }

  /// 🔑 EVALUADOR DE SESIÓN ACTIVA
  User? get usuarioActual => _supabase.auth.currentUser;
}
