// lib/modules/home/splash_screen_view.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../database/biblia_db_helper.dart';
import '../../database/auth_service.dart'; // Importa el nuevo servicio
import 'controlador_navegacion.dart';

class SplashScreenView extends StatefulWidget {
  const SplashScreenView({super.key});

  @override
  State<SplashScreenView> createState() => _SplashScreenViewState();
}

class _SplashScreenViewState extends State<SplashScreenView> {
  double _opacidad = 0.0;
  String _estadoCarga = "Iniciando sistema...";
  bool _mostrarBotonLogin = false; // Controla si se requiere autenticación
  final AuthService _authService = AuthService();
  final BibliaDatabaseHelper _dbHelper = BibliaDatabaseHelper();

  @override
  void initState() {
    super.initState();
    _dbHelper.progresoOffline.addListener(_escucharProgresoOffline);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _opacidad = 1.0);
    });
    _ejecutarPrecargaYVerificacion();
  }

  @override
  void dispose() {
    _dbHelper.progresoOffline.removeListener(_escucharProgresoOffline);
    super.dispose();
  }

  void _escucharProgresoOffline() {
    if (!mounted || _mostrarBotonLogin) return;
    final String mensaje = _dbHelper.progresoOffline.value;
    if (mensaje.isNotEmpty) setState(() => _estadoCarga = mensaje);
  }

  Future<void> _ejecutarPrecargaYVerificacion() async {
    final int milisegundosInicio = DateTime.now().millisecondsSinceEpoch;

    try {
      if (kIsWeb) {
        if (mounted) setState(() => _estadoCarga = "Configurando entorno web...");
        _dbHelper.obtenerMapaAbreviaturas();
      } else {
        if (mounted) setState(() => _estadoCarga = "Verificando base de datos offline...");
        final db = await _dbHelper.databaseLocal;
        if (db != null) {
          await db.rawQuery('PRAGMA synchronous = NORMAL;');
        }
        _dbHelper.obtenerMapaAbreviaturas();
        // Población de la biblioteca offline en un isolate: no congela la UI
        // y los futuros capítulos se leen por SQL en lugar de re-parssear JSON.
        _dbHelper.inicializarBibliotecaOffline();
      }
    } catch (_) {}

    // 🚀 VALIDACIÓN DE SEGURIDAD EN TIEMPO REAL:
    try {
    final usuarioLogueado = _authService.usuarioActual;

    final int tiempoTranscurrido = DateTime.now().millisecondsSinceEpoch - milisegundosInicio;
    final int tiempoRestanteEspera = 2200 - tiempoTranscurrido;
    if (tiempoRestanteEspera > 0) {
      await Future.delayed(Duration(milliseconds: tiempoRestanteEspera));
    }

    if (mounted) {
      if (usuarioLogueado != null) {
        // Sesión activa: Salta directo al Tablero de Control
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ControladorNavegacion()),
        );
      } else {
        // No hay sesión: Detiene el loader y muestra el botón de Google
        setState(() => _mostrarBotonLogin = true);        
      }

    }
    } catch (e) {
      print("Aviso de bypass de seguridad: $e");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ControladorNavegacion()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 129, 7, 7),
      body: Center(
        child: AnimatedOpacity(
          opacity: _opacidad,
          duration: const Duration(milliseconds: 800),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.auto_stories_rounded, size: 64, color: Color.fromARGB(255, 129, 7, 7)),
              ),
              const SizedBox(height: 20),
              const Text('Biblia del Predicador', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              Text(_mostrarBotonLogin ? "Requiere inicio de sesión para sincronizar" : _estadoCarga, style: TextStyle(color: Colors.blue.shade100, fontSize: 13, fontStyle: FontStyle.italic)),
              const SizedBox(height: 48),
              
              // 🚀 RENDERIZADO CONDICIONAL DE INTERFAZ DE ACCESO:
              if (!_mostrarBotonLogin)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0))
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      elevation: 2,
                    ),
                    onPressed: () async {
                      bool exito = await _authService.iniciarSesionConGoogle();
                      if (exito && context.mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const ControladorNavegacion()),
                        );
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icono simulado de Google
                        Container(
                          width: 18, height: 18,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1A73E8)),
                          child: const Center(child: Text('G', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                        ),
                        const SizedBox(width: 12),
                        const Text('Acceder con su cuenta de Google', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
