// lib/modules/lector/migracion_service.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 🚀 REQUERIDO: Reemplaza a dart:isolate para compatibilidad Web
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../../database/biblia_db_helper.dart';
import 'dart:async'; 

class MigracionService {
  /// Método principal que corre en el hilo de la UI y gestiona la carga.
  static Future<int> migrarReferenciasCruzadas(BuildContext context) async {
    try {
      final supabase = Supabase.instance.client;

      // 1. Cargar el string crudo en el hilo principal
      final String contenidoJsonCrudo = await DefaultAssetBundle.of(context)
          .loadString('assets/biblias/rv1960.json');

      // 2. Obtener el mapa de abreviaturas estático
      final Map<String, int> diccionarioTildesSeguro = BibliaDatabaseHelper().obtenerMapaAbreviaturas();

      // 3. Crear el mapa de datos para pasar múltiples argumentos
      final Map<String, dynamic> datosIsolate = {
        'jsonCrudo': contenidoJsonCrudo,
        'diccionario': diccionarioTildesSeguro,
      };

      // 4. 🚀 EJECUCIÓN COMPATIBLE CON WEB: 'compute' abstrae el Isolate de forma segura
      // En Web se ejecuta de forma asíncrona sin romper el motor de Dart.
      final List<Map<String, dynamic>> todasLasreferencias = await compute(
        _procesarHtmlEnIsolate, 
        datosIsolate
      );

      if (todasLasreferencias.isEmpty) return 0;

      // 5. Regresar al flujo principal para la subida controlada en lotes de 2000
      int contadorTotal = 0;
      List<Map<String, dynamic>> loteActual = [];

      for (var referencia in todasLasreferencias) {
        loteActual.add(referencia);
        contadorTotal++;

        if (loteActual.length >= 2000) {
          await supabase.from('referencias_cruzadas').insert(loteActual);
          loteActual.clear();
        }
      }

      // Insertar el remanente si quedó algo
      if (loteActual.isNotEmpty) {
        await supabase.from('referencias_cruzadas').insert(loteActual);
      }

      return contadorTotal;
    } catch (e) {
      print('Error crítico en MigracionService: $e');
      return -1;
    }
  }
}

/// 🎯 FUNCIÓN GLOBAL / TOP-LEVEL (Fuera de cualquier clase)
/// Se mantiene idéntica, compatible tanto con Isolates nativos como con compute de Flutter.
@pragma('vm:entry-point')
List<Map<String, dynamic>> _procesarHtmlEnIsolate(Map<String, dynamic> datos) {
  final String jsonCrudo = datos['jsonCrudo'];
  final Map<String, int> diccionarioLibros = Map<String, int>.from(datos['diccionario']);

  final Map<String, dynamic> objetoBiblia = jsonDecode(jsonCrudo);
  final List<dynamic> librosJson = objetoBiblia['books'] ?? [];
  List<Map<String, dynamic>> referenciasExtraidas = [];

  final RegExp regExpVersiculoBlock = RegExp(
    r'class=\\"verse\s+v([0-9]+)\\"[^>]*>(.*?)<\/span>\s*<\/span>', 
    dotAll: true
  );
  final RegExp regExpNotaCruzada = RegExp(
    r'class=\\" body\\">(.*?)<\/span>', 
    dotAll: true
  );

  for (int i = 0; i < librosJson.length; i++) {
    final int origenLibroId = i + 1;
    final List<dynamic> capitulosJson = librosJson[i]['chapters'] ?? [];

    for (var capData in capitulosJson) {
      final int origenCapitulo = capData['chapter_number'] ?? 1;
      final String htmlContenido = capData['chapter_html'] ?? '';

      final matchesVersos = regExpVersiculoBlock.allMatches(htmlContenido);
      
      for (var matchV in matchesVersos) {
        final int origenVersiculo = int.parse(matchV.group(1)!);
        final String bloqueInternoHtml = matchV.group(2)!;

        if (bloqueInternoHtml.contains('class=\\"note x\\"')) {
          final matchesNotas = regExpNotaCruzada.allMatches(bloqueInternoHtml);
          
          for (var matchN in matchesNotas) {
            String textoNotaRaw = matchN.group(1)!;
            textoNotaRaw = textoNotaRaw.replaceAll(RegExp(r'<[^>]*>'), '').trim();

            List<String> segmentosPorLibro = textoNotaRaw.split(';');

            for (var segmento in segmentosPorLibro) {
              if (segmento.trim().isEmpty) continue;

              final matchBase = RegExp(r'([1-3]?\s?[A-Za-z\s]+)\.').firstMatch(segmento);
              if (matchBase == null) continue;
              
              String nombreLibroDestino = matchBase.group(1)!.trim();
              int destinoLibroId = diccionarioLibros[nombreLibroDestino] ?? 0;

              final RegExp regexNumeros = RegExp(r'([0-9]+)\.([0-9]+)');
              final matchesNumeros = regexNumeros.allMatches(segmento);

              for (var matchNum in matchesNumeros) {
                int destCap = matchNum.group(1) != null ? int.parse(matchNum.group(1)!) : 0;
                int destVer = matchNum.group(2) != null ? int.parse(matchNum.group(2)!) : 0;

                if (destinoLibroId != 0 && destCap != 0 && destVer != 0) {
                  referenciasExtraidas.add({
                    'origen_libro_id': origenLibroId,
                    'origen_capitulo': origenCapitulo,
                    'origen_versiculo': origenVersiculo,
                    'destino_libro_id': destinoLibroId,
                    'destino_capitulo': destCap,
                    'destino_versiculo': destVer,
                  });
                }
              }
            }
          }
        }
      }
    }
  }
  return referenciasExtraidas;
}
