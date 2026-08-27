// lib/modules/home/splash_screen_view.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../database/biblia_db_helper.dart'; // Tu manejador de persistencia
import 'pantalla_inicio_view.dart';

class SplashScreenView extends StatefulWidget {
  const SplashScreenView({super.key});

  @override
  State<SplashScreenView> createState() => _SplashScreenViewState();
}

class _SplashScreenViewState extends State<SplashScreenView> {
  double _opacidad = 0.0;
  String _estadoCarga = "Iniciando sistema...";

  @override
  void initState() {
    super.initState();
    
    // 🚀 EFECTO ENTRADA: Desvanecimiento visual de la UI
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _opacidad = 1.0);
    });

    // 🚀 INICIALIZACIÓN PARALELA DE HARDWARE Y DISPARO
    _ejecutarPrecargaYTransicion();
  }

  Future<void> _ejecutarPrecargaYTransicion() async {
    final int milisegundosInicio = DateTime.now().millisecondsSinceEpoch;

    try {
      // 1. Despertar la base de datos SQLite local y forzar onCreate/onUpgrade si aplica
      if (mounted) setState(() => _estadoCarga = "Verificando base de datos offline...");
      final dbHelper = BibliaDatabaseHelper();
      final db = await dbHelper.databaseLocal;

      // 2. Ejecutar una consulta ligera (PRAGMA o conteo rápido) para levantar los descriptores de archivo en la RAM
      if (db != null) {
        if (mounted) setState(() => _estadoCarga = "Optimizando índices de lectura...");
        // Ejecuta un comando interno para calentar el Page Cache de SQLite
        await db.rawQuery('PRAGMA synchronous = NORMAL;');
      }

      // 3. Calentar el diccionario estático de abreviaturas canónicas en la memoria RAM
      if (mounted) setState(() => _estadoCarga = "Estructurando mapas relacionales...");
      dbHelper.obtenerMapaAbreviaturas();

    } catch (e) {
      print('Aviso de contingencia silenciosa en precarga: $e');
    }

    // Calcular cuánto tiempo tomó la operación para cumplir los 2.5 segundos estéticos sin retrasar al pastor
    final int tiempoTranscurrido = DateTime.now().millisecondsSinceEpoch - milisegundosInicio;
    final int tiempoRestanteEspera = 2500 - tiempoTranscurrido;

    // Esperar el remanente si la CPU fue ultra rápida, garantizando la fluidez de la animación
    if (tiempoRestanteEspera > 0) {
      await Future.delayed(Duration(milliseconds: tiempoRestanteEspera));
    }

    if (mounted) {
      // Despacho final al centro de mandos destruyendo el Splash de la pila de memoria
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const PantallaInicioView()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A73E8),
      body: Center(
        child: AnimatedOpacity(
          opacity: _opacidad,
          duration: const Duration(milliseconds: 1000),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_stories_rounded, 
                  size: 72, 
                  color: Color(0xFF1A73E8),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Biblioteca Pastoral',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              
              // 🚀 TEXTO DE ESTADO DINÁMICO: Informa al pastor qué se está procesando por debajo
              Text(
                _estadoCarga,
                style: TextStyle(
                  color: Colors.blue.shade100,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 40),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.0,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
