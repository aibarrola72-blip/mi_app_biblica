// lib/database/auth_service.dart

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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
        // 🚀 USAMOS TU ID DE CLIENTE WEB VERIFICADO QUE SÍ COMPILA:
        const webClientId = '40946649762-pi30rq46mutt97ooitp4nam79ld72i3p.apps.googleusercontent.com';

        // 🚀 MEJORA DE CANDADO: Agregamos scopes obligatorios para forzar al celular a responder
        final GoogleSignIn googleSignIn = GoogleSignIn(
          serverClientId: webClientId,
          scopes: ['email', 'profile'],
        );
        
        // Limpiamos cualquier rastro previo para evitar congelamientos si el pastor reintenta el login
        await googleSignIn.signOut().catchError((_) => null);
        
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) return false; // El pastor canceló el diálogo

        final googleAuth = await googleUser.authentication;
        final accessToken = googleAuth.accessToken;
        final idToken = googleAuth.idToken;

        if (accessToken == null || idToken == null) {
          debugPrint('🔴 Error: Los tokens de Google retornaron nulos en el hardware del dispositivo.');
          return false;
        }

        // Inyectamos el ID Token directamente en el motor de seguridad de Supabase
        final response = await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );

        return response.user != null;
      }
    } catch (e) {
      debugPrint('Fallo crítico en el inicio de sesión con Google: $e');
      return false;
    }
  }

  /// 🚪 CERRAR SESIÓN (Limpia tokens de la memoria RAM y cookies web)
  Future<void> cerrarSesion() async {
    await _supabase.auth.signOut();
    if (!kIsWeb) {
      await GoogleSignIn().signOut().catchError((_) => null);
    }
  }

  /// 🔑 EVALUADOR DE SESIÓN ACTIVA
  User? get usuarioActual => _supabase.auth.currentUser;
}
