// lib/database/migrador_biblico.dart

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:html/parser.dart' show parse; 
import 'package:html/dom.dart' as dom;

class MigradorBiblico {
  final _client = Supabase.instance.client;

  static const Map<String, int> _mapaLibrosUsfm = {
    'GEN': 1, 'EXO': 2, 'LEV': 3, 'NUM': 4, 'DEU': 5, 'JOS': 6, 'JDG': 7, 'RUT': 8,
    '1SA': 9, '2SA': 10, '1KI': 11, '2KI': 12, '1CH': 13, '2CH': 14, 'EZR': 15, 'NEH': 16,
    'EST': 17, 'JOB': 18, 'PSA': 19, 'PRO': 20, 'ECC': 21, 'SNG': 22, 'ISA': 23, 'JER': 24,
    'LAM': 25, 'EZK': 26, 'DAN': 27, 'HOS': 28, 'JOL': 29, 'AMO': 30, 'OBA': 31, 'JON': 32,
    'MIC': 33, 'NAM': 34, 'HAB': 35, 'ZEP': 36, 'HAG': 37, 'ZEC': 38, 'MAL': 39, 'MAT': 40,
    'MRK': 41, 'LUK': 42, 'JHN': 43, 'ACT': 44, 'ROM': 45, '1CO': 46, '2CO': 47, 'GAL': 48,
    'EPH': 49, 'PHP': 50, 'COL': 51, '1TH': 52, '2TH': 53, '1TI': 54, '2TI': 55, 'TIT': 56,
    'PHM': 57, 'HEB': 58, 'JAS': 59, '1PE': 60, '2PE': 61, '1JN': 62, '2JN': 63, '3JN': 64,
    'JUD': 65, 'REV': 66
  };

  static const Map<String, int> _diccionarioCitasMarginales = {
    'gn': 1, 'ex': 2, 'lv': 3, 'nm': 4, 'dt': 5, 'jos': 6, 'jue': 7, 'rt': 8,
    '1 sm': 9, '2 sm': 10, '1 r': 11, '2 r': 12, '1 cr': 13, '2 cr': 14, 'esd': 15, 'neh': 16,
    'est': 17, 'job': 18, 'sal': 19, 'pr': 20, 'ec': 21, 'cnt': 22, 'is': 23, 'jr': 24,
    'lam': 25, 'ez': 26, 'dn': 27, 'os': 28, 'jl': 29, 'am': 30, 'abd': 31, 'jon': 32,
    'mi': 33, 'nah': 34, 'hab': 35, 'sof': 36, 'hag': 37, 'zac': 38, 'mal': 39, 'mt': 40,
    'mr': 41, 'lc': 42, 'jn': 43, 'hch': 44, 'ro': 45, '1 co': 46, '2 co': 47, 'ga': 48,
    'ef': 49, 'flp': 50, 'col': 51, '1 ts': 52, '2 ts': 53, '1 ti': 54, '2 ti': 55, 'ti': 56,
    'flm': 57, 'heb': 58, 'stg': 59, '1 p': 60, '2 p': 61, '1 jn': 62, '2 jn': 63, '3 jn': 64,
    'jud': 65, 'ap': 66
  };

  // Función interna para asegurar la higiene digital de caracteres especiales
  String _sanearHtmlAcentosManual(String html) {
    return html
        .replaceAll('&aacute;', 'á').replaceAll('&Aacute;', 'Á')
        .replaceAll('&eacute;', 'é').replaceAll('&Eacute;', 'É')
        .replaceAll('&iacute;', 'í').replaceAll('&Iacute;', 'Í')
        .replaceAll('&oacute;', 'ó').replaceAll('&Oacute;', 'Ó')
        .replaceAll('&uacute;', 'ú').replaceAll('&Uacute;', 'Ú')
        .replaceAll('&ntilde;', 'ñ').replaceAll('&Ntilde;', 'Ñ')
        .replaceAll('&nbsp;', ' ');
  }

  Future<void> cargarVersionDesdeJsonLocal(String versionId, String nombreArchivoJson, Function(String) onProgreso) async {
    onProgreso('💾 Abriendo archivo local $nombreArchivoJson.json...');

    try {
      // Registrar la versión padre en el catálogo relacional
      await _client.from('versiones').upsert({
        'id': versionId, 
        'nombre': 'Biblia Traducida ($versionId)', 
        'idioma': 'es'
      }, onConflict: 'id');

      final datosBytes = await rootBundle.load('assets/biblias/$nombreArchivoJson.json');
      final String contenidoJsonLimpio = utf8.decode(datosBytes.buffer.asUint8List());

      final Map<String, dynamic> objetoBibliaJson = jsonDecode(contenidoJsonLimpio);
      final List<dynamic> librosJson = objetoBibliaJson['books'] ?? [];

      List<Map<String, dynamic>> loteVersiculos = [];
      List<Map<String, dynamic>> loteReferencias = [];
      
      // 🚀 CORRECCIÓN DE RESETEO: Obligamos a vaciar el Set al inicio de cada versión bíblica
      final Set<String> llavesEnBufferActual = {}; 
      
      int contadorTotalVersiculos = 0;
      int contadorTotalReferencias = 0;

      final RegExp regExpPartesReferencia = RegExp(r'([1-3]?\s?[A-Za-zÁ-ú]+)\.\s*([0-9]+)[:\.]\s*([0-9]+)');

      for (var libro in librosJson) {
        // Toleramos variaciones de minúsculas/mayúsculas en las llaves USFM de origen
        final String abbrUsfm = (libro['book_usfm'] ?? libro['abbr']).toString().trim().toUpperCase();
        final int? libroId = _mapaLibrosUsfm[abbrUsfm];
        if (libroId == null) continue;

        final List<dynamic> capitulos = libro['chapters'];
        for (int cIdx = 0; cIdx < capitulos.length; cIdx++) {
          final int capituloNum = cIdx + 1;
          final Map<String, dynamic> capituloMap = capitulos[cIdx];
          
          String htmlContenido = capituloMap['chapter_html'] ?? '';
          if (htmlContenido.isEmpty) continue;

          // Sanitización preventiva antes de estructurar el árbol de nodos DOM
          htmlContenido = _sanearHtmlAcentosManual(htmlContenido);

          final dom.Document document = parse(htmlContenido);
          final List<dom.Element> elementosVerso = document.querySelectorAll('span.verse');
          
          Map<int, String> versosUnificados = {};

          for (var elVerso in elementosVerso) {
            final String clases = elVerso.className;
            final RegExp matchNumeroClase = RegExp(r'v([0-9]+)');
            final matchClase = matchNumeroClase.firstMatch(clases);
            if (matchClase == null) continue;
            
            final int versoNum = int.parse(matchClase.group(1)!);

            // 1. EXTRACCIÓN DE CITAS MARGINALES RELACIONALES
            final List<dom.Element> nodosNotas = elVerso.querySelectorAll('span.note.x');
            for (var nodoNota in nodosNotas) {
              final dom.Element? nodoBody = nodoNota.querySelector('span.body');
              if (nodoBody != null) {
                String textoNotaRaw = nodoBody.text.trim();
                
                final matchCita = regExpPartesReferencia.firstMatch(textoNotaRaw);
                if (matchCita != null) {
                  final String libroDestinoRaw = matchCita.group(1)!.toLowerCase().trim();
                  final int capituloDestino = int.parse(matchCita.group(2)!);
                  final int versiculoDestino = int.parse(matchCita.group(3)!);

                  final int? libroDestinoId = _diccionarioCitasMarginales[libroDestinoRaw];

                  if (libroDestinoId != null) {
                    final String llaveUnica = '${libroId}_${capituloNum}_${versoNum}_${libroDestinoId}_${capituloDestino}_${versiculoDestino}';

                    if (!llavesEnBufferActual.contains(llaveUnica)) {
                      llavesEnBufferActual.add(llaveUnica);
                      loteReferencias.add({
                        'origen_libro_id': libroId,
                        'origen_capitulo': capituloNum,
                        'origen_versiculo': versoNum,
                        'destino_libro_id': libroDestinoId,
                        'destino_capitulo': capituloDestino,
                        'destino_versiculo': versiculoDestino,
                        'llave_unica': llaveUnica,
                      });
                    }
                  }
                }
              }
              nodoNota.remove(); // Removemos para no contaminar el cuerpo de la escritura
            }

            // 2. EXTRACCIÓN Y LIMPIEZA DE TEXTO PLANO CONSERVANDO TILDES
            String textoVersiculoLimpio = elVerso.text.trim();
            textoVersiculoLimpio = textoVersiculoLimpio.replaceFirst(RegExp('^$versoNum\\s*'), '');

            if (textoVersiculoLimpio.isEmpty) continue;

            if (versosUnificados.containsKey(versoNum)) {
              if (!versosUnificados[versoNum]!.contains(textoVersiculoLimpio)) {
                versosUnificados[versoNum] = '${versosUnificados[versoNum]} $textoVersiculoLimpio';
              }
            } else {
              versosUnificados[versoNum] = textoVersiculoLimpio;
            }
          }

          // Traspaso de tuplas limpias al buffer masivo de red
          versosUnificados.forEach((versoNum, textoFinal) {
            loteVersiculos.add({
              'version_id': versionId,
              'libro_id': libroId,
              'capitulo': capituloNum,
              'versiculo': versoNum,
              'texto': textoFinal.replaceAll(RegExp(r'\s+'), ' ').trim(),
            });
          });

          // DISPARO DE BUFFER CONTROLADO (RPC Ultrarrápido nativo)
          if (loteVersiculos.length >= 300 || loteReferencias.length >= 300) {
            await _client.rpc(
              'importar_lotes_biblia',
              params: {
                'versiculos_input': loteVersiculos,
                'referencias_input': loteReferencias,
              },
            );

            contadorTotalVersiculos += loteVersiculos.length;
            contadorTotalReferencias += loteReferencias.length;

            loteVersiculos.clear();
            loteReferencias.clear();
            llavesEnBufferActual.clear(); // Limpieza incremental del lote actual

            onProgreso('📦 Inyectados $contadorTotalVersiculos versos de la versión $versionId...');
            await Future.delayed(const Duration(milliseconds: 40));
          }
        }
      }

      // ENVIAR REMANENTES FINALES FLOTANTES DEL BUFFER
      if (loteVersiculos.isNotEmpty || loteReferencias.isNotEmpty) {
        await _client.rpc(
          'importar_lotes_biblia',
          params: {
            'versiculos_input': loteVersiculos,
            'referencias_input': loteReferencias,
          },
        );
        contadorTotalVersiculos += loteVersiculos.length;
        contadorTotalReferencias += loteReferencias.length;
      }

      onProgreso('✅ ¡$versionId listo con éxito! ($contadorTotalVersiculos versos guardados).');
    } catch (e) {
      onProgreso('❌ Error fatal en migrador de versión $versionId: $e');
      rethrow;
    }
  }
}
