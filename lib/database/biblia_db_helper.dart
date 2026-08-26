// lib/database/biblia_db_helper.dart

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb; // Detecta si es Web nativo
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart' as sql; // Importación limpia multiplataforma
import 'package:flutter/services.dart' show rootBundle;

class BibliaDatabaseHelper {
  static final BibliaDatabaseHelper _instance = BibliaDatabaseHelper._internal();
  factory BibliaDatabaseHelper() => _instance;
  BibliaDatabaseHelper._internal();

  final _client = Supabase.instance.client;
  dynamic _dbMobi; // Usamos tipo dinámico para blindar la compilación en Web

  // CACHÉ EN MEMORIA GLOBAL: Funciona tanto en Web como en Móvil a velocidad luz
  final Map<String, List<Map<String, dynamic>>> _cacheCapitulos = {};
  final Map<String, List<Map<String, dynamic>>> _cacheReferencias = {};

  // Inicializador multiplataforma seguro: En Web no hace nada, en Móvil abre SQLite
  Future<dynamic> get databaseLocal async {
    if (kIsWeb) return null; // 🚀 SOLUCIÓN AL LOOP Y CAÍDA EN WEB: Retorna nulo sin tocar hardware
    if (_dbMobi != null) return _dbMobi;
    
    try {
      final rutaDb = await sql.getDatabasesPath();
      _dbMobi = await sql.openDatabase(
        '$rutaDb/biblioteca_pastoral_v3.db', // 🚀 v3 fuerza la recreación limpia de todas las tablas offline
        version: 1,
        onCreate: (db, version) async {
          // 1. Tabla espejo de Versículos
          await db.execute('''
            CREATE TABLE cache_versiculos (
              version_id TEXT,
              libro_id INTEGER,
              capitulo INTEGER,
              versiculo INTEGER,
              texto TEXT,
              PRIMARY KEY (version_id, libro_id, capitulo, versiculo)
            )
          ''');

          // 2. Tabla espejo de Referencias Cruzadas locales para Modo Avión
          await db.execute('''
            CREATE TABLE cache_referencias (
              origen_libro_id INTEGER,
              origen_capitulo INTEGER,
              origen_versiculo INTEGER,
              destino_libro_id INTEGER,
              destino_capitulo INTEGER,
              destino_versiculo INTEGER,
              nombre_libro_destino TEXT,
              PRIMARY KEY (origen_libro_id, origen_capitulo, origen_versiculo, destino_libro_id, destino_capitulo, destino_versiculo)
            )
          ''');

          // 3. Tabla espejo para el Buscador Global Offline
          await db.execute('''
            CREATE TABLE cache_busquedas (
              id_busqueda INTEGER PRIMARY KEY AUTOINCREMENT,
              termino_busqueda TEXT,
              libro_id INTEGER,
              capitulo INTEGER,
              versiculo INTEGER,
              texto TEXT
            )
          ''');
        },
      );
      return _dbMobi;
    } catch (e) {
      print('Error abriendo SQLite local en el dispositivo móvil: $e');
      return null;
    }
  }

  // DICCIONARIO COMPLETO NORMALIZADO (RV1960 / NBLA)
  static const Map<String, int> _diccionarioLibros = {
    'genesis': 1, 'génesis': 1, 'gen': 1, 'gn': 1, 'exodo': 2, 'éxodo': 2, 'exo': 2, 'ex': 2,
    'levitico': 3, 'levítico': 3, 'lev': 3, 'lv': 3, 'numeros': 4, 'números': 4, 'num': 4, 'nm': 4,
    'deuteronomio': 5, 'deu': 5, 'dt': 5, 'josue': 6, 'josué': 6, 'jos': 6, 'jueces': 7, 'jue': 7,
    'rut': 8, 'rt': 8, '1 samuel': 9, '1sm': 9, '2 samuel': 10, '2sm': 10, '1 reyes': 11, '1re': 11,
    '2 reyes': 12, '2re': 12, '1 cronicas': 13, '1cr': 13, '2 cronicas': 14, '2cr': 14, 'esdras': 15,
    'nehemias': 16, 'neh': 16, 'ester': 17, 'est': 17, 'job': 18, 'salmos': 19, 'sal': 19, 'proverbios': 20,
    'pr': 20, 'eclesiastes': 21, 'ec': 21, 'cantares': 22, 'cnt': 22, 'isaias': 23, 'is': 23, 'jeremias': 24,
    'jr': 24, 'lamentaciones': 25, 'ezequiel': 26, 'ez': 26, 'daniel': 27, 'dn': 27, 'oseas': 28, 'os': 28,
    'joel': 29, 'jl': 29, 'amos': 30, 'am': 30, 'abdias': 31, 'abd': 31, 'jonas': 32, 'jon': 32, 'miqueas': 33, 'mi': 33,
    'nahum': 34, 'habacuc': 35, 'sofonias': 36, 'sof': 36, 'hageo': 37, 'zacarias': 38, 'zac': 38, 'malaquias': 39,
    'mal': 39, 'mateo': 40, 'mt': 40, 'marcos': 41, 'mr': 41, 'lucas': 42, 'lc': 42, 'juan': 43, 'jn': 43,
    'hechos': 44, 'hch': 44, 'romanos': 45, 'ro': 45, '1 corintios': 46, '1co': 46, '1 cor': 46,
    '2 corintios': 47, '2co': 47, 'galatas': 48, 'gl': 48, 'efesios': 49, 'ef': 49, 'filipenses': 50, 'flp': 50,
    'colosenses': 51, 'col': 51, '1 tesalonicenses': 52, '1ts': 52, '2 tesalonicenses': 53, '2ts': 53,
    '1 timoteo': 54, '1ti': 54, '2 timoteo': 55, '2ti': 55, 'tito': 56, 'tit': 56, 'filemon': 57, 'flm': 57,
    'hebreos': 58, 'heb': 58, 'santiago': 59, 'stg': 59, 'st': 59, '1 pedro': 60, '1p': 60, '2 pedro': 61,
    '2p': 61, '1 juan': 62, '1jn': 62, '2 juan': 63, '2jn': 63, '3 juan': 64, '3jn': 64, 'judas': 65, 'apocalipsis': 66, 'ap': 66
  };

  static const Map<int, String> _nombresLibros = {
    1: 'Génesis', 2: 'Éxodo', 3: 'Levítico', 4: 'Números', 5: 'Deuteronomio', 6: 'Josué', 7: 'Jueces',
    8: 'Rut', 9: '1 Samuel', 10: '2 Samuel', 11: '1 Reyes', 12: '2 Reyes', 13: '1 Crónicas', 14: '2 Crónicas',
    15: 'Esdras', 16: 'Nehemías', 17: 'Ester', 18: 'Job', 19: 'Salmos', 20: 'Proverbios', 21: 'Eclesiastés',
    22: 'Cantares', 23: 'Isaías', 24: 'Jeremías', 25: 'Lamentaciones', 26: 'Ezequiel', 27: 'Daniel', 28: 'Oseas',
    29: 'Joel', 30: 'Amós', 31: 'Abdías', 32: 'Jonás', 33: 'Miqueas', 34: 'Nahum', 35: 'Habacuc', 36: 'Sofonías',
    37: 'Hageo', 38: 'Zacarías', 39: 'Malaquías', 40: 'Mateo', 41: 'Marcos', 42: 'Lucas', 43: 'Juan', 44: 'Hechos',
    45: 'Romanos', 46: '1 Corintios', 47: '2 Corintios', 48: 'Gálatas', 49: 'Efesios', 50: 'Filipenses',
    51: 'Colosenses', 52: '1 Tesalonicenses', 53: '2 Tesalonicenses', 54: '1 Timoteo', 55: '2 Timoteo',
    56: 'Tito', 57: 'Filemón', 58: 'Hebreos', 59: 'Santiago', 60: '1 Pedro', 61: '2 Pedro', 62: '1 Juan',
    63: '2 Juan', 64: '3 Juan', 65: 'Judas', 66: 'Apocalipsis'
  };

  int obtenerLibroId(String nombreLibro) => _diccionarioLibros[nombreLibro.toLowerCase().trim()] ?? 43;
  String obtenerNombreLibro(int libroId) => _nombresLibros[libroId] ?? 'Libro $libroId';

  // 🚀 LECTURA DE CAPÍTULO HÍBRIDO (Inmune a caídas Web y Móvil)
  // 🚀 LECTURA DE CAPÍTULO CON CACHÉ DE ESCRITURA CORREGIDA
  // 🚀 LECTURA DE CAPÍTULO HÍBRIDO CON CONTINGENCIA JSON HTML LOCAL
  Future<List<Map<String, dynamic>>> obtenerCapitulo(int libroId, int capitulo, {String versionId = 'RV1960'}) async {
    final llaveCache = '${versionId}_${libroId}_$capitulo';
    if (_cacheCapitulos.containsKey(llaveCache)) return _cacheCapitulos[llaveCache]!;

    try {
      final response = await _client
          .from('versiculos')
          .select('libro_id, capitulo, versiculo, texto, version_id')
          .eq('version_id', versionId) 
          .eq('libro_id', libroId)
          .eq('capitulo', capitulo)
          .order('versiculo', ascending: true)
          .timeout(const Duration(milliseconds: 1500)); 
      
      final resultadoNube = List<Map<String, dynamic>>.from(response);

      if (resultadoNube.isNotEmpty) {
        _cacheCapitulos[llaveCache] = resultadoNube;

        if (!kIsWeb) {
          final db = await databaseLocal;
          if (db != null) {
            final loteBatch = db.batch();
            for (var v in resultadoNube) {
              loteBatch.insert(
                'cache_versiculos',
                {
                  'version_id': versionId,
                  'libro_id': libroId,
                  'capitulo': capitulo,
                  'versiculo': v['versiculo'],
                  'texto': v['texto']
                },
                conflictAlgorithm: sql.ConflictAlgorithm.replace,
              );
            }
            await loteBatch.commit(noResult: true);
          }
        }
        return resultadoNube;
      }
    } catch (e) { 
      print('Servidor inalcanzable. Buscando persistencia local SQLite... $e'); 
    }

    // 1. Intento secundario: Buscar en la caché de SQLite local (Dispositivos móviles con historial)
    if (!kIsWeb) {
      final db = await databaseLocal;
      if (db != null) {
        final resultadoLocal = await db.query(
          'cache_versiculos',
          where: 'version_id = ? AND libro_id = ? AND capitulo = ?',
          whereArgs: [versionId, libroId, capitulo],
          orderBy: 'versiculo ASC',
        );

        if (resultadoLocal.isNotEmpty) {
          final transformado = resultadoLocal.map((row) => Map<String, dynamic>.from(row)).toList();
          _cacheCapitulos[llaveCache] = transformado;
          return transformado;
        }
      }
    }

    // 2. CONTINGENCIA ABSOLUTA COSTO $0: Extraer datos directamente desde el HTML de tus archivos JSON
    try {
      final Map<String, String> mapeoArchivosJson = {
        'RV1960': 'rv1960', 'NVI': 'nvi128', 'RVC': 'rvc', 'RVA2015': 'rva2015',
        'TLA': 'tla', 'TLAI': 'tlai', 'NVIC': 'nvi1637', 'NTV': 'ntv',
        'NBLA': 'nbla', 'LBLA': 'lbla', 'DHH': 'dhh', 'DHHS': 'dhhs',
      };

      final String nombreArchivo = mapeoArchivosJson[versionId] ?? 'rv1960';
      final String contenidoJsonCrudo = await rootBundle.loadString('assets/biblias/$nombreArchivo.json');
      final Map<String, dynamic> objetoBiblia = jsonDecode(contenidoJsonCrudo);
      final List<dynamic> librosJson = objetoBiblia['books'] ?? [];

      if (librosJson.length >= libroId) {
        final Map<String, dynamic> libroMap = librosJson[libroId - 1];
        final List<dynamic> capitulosJson = libroMap['chapters'] ?? [];

        if (capitulosJson.length >= capitulo) {
          final Map<String, dynamic> capituloMap = capitulosJson[capitulo - 1];
          final String htmlContenido = capituloMap['chapter_html'] ?? '';
          
          List<Map<String, dynamic>> textosOfflineJson = [];

          // Expresión regular adaptada al formato html de bible-data-es-spa
          final RegExp regExpVersoHtml = RegExp(
            r'class="verse\s+v([0-9]+)"[^>]*>.*?<span class="content">(.*?)<\/span>',
            dotAll: true,
          );

          final matches = regExpVersoHtml.allMatches(htmlContenido);
          
          for (var match in matches) {
            final int numVerso = int.parse(match.group(1)!);
            String textoLimpio = match.group(2)!
                .replaceAll(RegExp(r'<[^>]*>'), '') // Elimina etiquetas de notas internas o llamadas (#)
                .replaceAll(r"\'", "'")
                .trim();
            // Inyectamos el convertidor aquí para limpiar los acentos
            textoLimpio = textoLimpio.replaceAllMapped(RegExp(r'&#([0-9]+);'), (Match m) {
            return String.fromCharCode(int.parse(m.group(1)!));
            });

            if (textoLimpio.isNotEmpty) {
              textosOfflineJson.add({
                'libro_id': libroId,
                'capitulo': capitulo,
                'versiculo': numVerso,
                'texto': textoLimpio,
                'version_id': versionId,
              });
            }
          }
          if (textosOfflineJson.isNotEmpty) {
            _cacheCapitulos[llaveCache] = textosOfflineJson;
            return textosOfflineJson;
          }
        }
      }
    } catch (errJson) {
      print('Fallo crítico en la lectura de contingencia física de JSONs locales: $errJson');
    }

    return []; 
  }

  // 🚀 REFERENCIAS CRUZADAS CON CACHÉ DE ESCRITURA CORREGIDA
  Future<List<Map<String, dynamic>>> obtenerReferenciasCruzadas(int libroId, int capitulo, int versiculo) async {
    final llaveCache = '${libroId}_${capitulo}_$versiculo';
    if (_cacheReferencias.containsKey(llaveCache)) return _cacheReferencias[llaveCache]!;

    try {
      final response = await _client
          .from('referencias_cruzadas')
          .select('destino_libro_id, destino_capitulo, destino_versiculo, libros!referencias_cruzadas_destino_libro_id_fkey(nombre)')
          .eq('origen_libro_id', libroId)
          .eq('origen_capitulo', capitulo)
          .eq('origen_versiculo', versiculo)
          .timeout(const Duration(milliseconds: 1500));
      
      final resultadoNube = List<Map<String, dynamic>>.from(response);

      if (resultadoNube.isNotEmpty) {
        _cacheReferencias[llaveCache] = resultadoNube;

        if (!kIsWeb) {
          final db = await databaseLocal;
          if (db != null) {
            final loteBatch = db.batch();
            for (var r in resultadoNube) {
              loteBatch.insert(
                'cache_referencias',
                {
                  'origen_libro_id': libroId,
                  'origen_capitulo': capitulo,
                  'origen_versiculo': versiculo,
                  'destino_libro_id': r['destino_libro_id'],
                  'destino_capitulo': r['destino_capitulo'],
                  'destino_versiculo': r['destino_versiculo'],
                  'nombre_libro_destino': r['libros']['nombre'] ?? 'Libro',
                },
                // 🚀 CORRECCIÓN DE PARÁMETRO NATIVO DE SQFLITE
                conflictAlgorithm: sql.ConflictAlgorithm.replace,
              );
            }
            await loteBatch.commit(noResult: true);
          }
        }
        return resultadoNube;
      }
    } catch (e) {
      print('Docker desconectado. Cargando referencias desde SQLite local... $e');
    }

    if (!kIsWeb) {
      final db = await databaseLocal;
      if (db != null) {
        final resultadoLocal = await db.query(
          'cache_referencias',
          where: 'origen_libro_id = ? AND origen_capitulo = ? AND origen_versiculo = ?',
          whereArgs: [libroId, capitulo, versiculo],
        );

        if (resultadoLocal.isNotEmpty) {
          return resultadoLocal.map((row) {
            return {
              'destino_libro_id': row['destino_libro_id'],
              'destino_capitulo': row['destino_capitulo'],
              'destino_versiculo': row['destino_versiculo'],
              'libros': {'nombre': row['nombre_libro_destino']}
            };
          }).toList();
        }
      }
    }
    return [];
  }

    // 🚀 BUSCADOR GLOBAL HÍBRIDO CON MIGRACIÓN DINÁMICA A TEXTO PLANO LOCAL
  Future<List<Map<String, dynamic>>> buscarPalabraClaveGlobal(String consulta) async {
    if (consulta.trim().isEmpty) return [];
    final String terminoLimpio = consulta.trim().toLowerCase();
    
    // Separamos los términos individuales para simular un operador AND de búsqueda
    final List<String> palabrasClave = terminoLimpio.split(' ').where((w) => w.length > 2).toList();
    if (palabrasClave.isEmpty) return [];

    try {
      // 1. INTENTO EN LA NUBE: Motor FTS nativo de Supabase de alta velocidad
      final terminosFts = consulta.trim().split(' ').join(' & ');
      final response = await _client
          .from('versiculos')
          .select('libro_id, capitulo, versiculo, texto')
          .textSearch('fts_vector', terminosFts, config: 'spanish')
          .limit(50)
          .timeout(const Duration(milliseconds: 1800)); 

      final resultadoNube = List<Map<String, dynamic>>.from(response);

      if (resultadoNube.isNotEmpty) {
        if (!kIsWeb) {
          final db = await databaseLocal;
          if (db != null) {
            final loteBatch = db.batch();
            for (var v in resultadoNube) {
              loteBatch.insert(
                'cache_busquedas',
                {
                  'termino_busqueda': terminoLimpio,
                  'libro_id': v['libro_id'],
                  'capitulo': v['capitulo'],
                  'versiculo': v['versiculo'],
                  'texto': v['texto'],
                },
                conflictAlgorithm: sql.ConflictAlgorithm.replace,
              );
            }
            await loteBatch.commit(noResult: true);
          }
        }
        return resultadoNube;
      }
    } catch (e) {
      print('Buscador remoto fuera de servicio. Inicializando escaneo secuencial... $e');
    }

    // 2. INTENTO EN CACHÉ SQLITE: Si ya existía una búsqueda idéntica previa (Solo Móvil)
    if (!kIsWeb) {
      final db = await databaseLocal;
      if (db != null) {
        final resultadoLocal = await db.query(
          'cache_busquedas',
          where: 'termino_busqueda = ?',
          whereArgs: [terminoLimpio],
          limit: 50,
        );
        if (resultadoLocal.isNotEmpty) {
          return resultadoLocal.map((row) => Map<String, dynamic>.from(row)).toList();
        }
      }
    }

    // 3. CONTINGENCIA TOTAL COSTO $0: Escaneo relacional directo desde el HTML de tu archivo JSON
    // Este algoritmo lee recursivamente tus JSONs para encontrar todas las ocurrencias en milisegundos
    try {
      // Cargamos por defecto la versión Reina-Valera 1960 para la búsqueda fuera de línea
      final String contenidoJsonCrudo = await rootBundle.loadString('assets/biblias/rv1960.json');
      final Map<String, dynamic> objetoBiblia = jsonDecode(contenidoJsonCrudo);
      final List<dynamic> librosJson = objetoBiblia['books'] ?? [];

      List<Map<String, dynamic>> resultadosFiltradosJson = [];
      final RegExp regExpVersoHtml = RegExp(
        r'class="verse\s+v([0-9]+)"[^>]*>.*?<span class="content">(.*?)<\/span>',
        dotAll: true,
      );

      // Recorremos los 66 libros canónicos de la Biblia guardados localmente
      for (int i = 0; i < librosJson.length; i++) {
        final Map<String, dynamic> libroMap = librosJson[i];
        final int libroId = i + 1;
        final List<dynamic> capitulosJson = libroMap['chapters'] ?? [];

        for (var capituloData in capitulosJson) {
          final int numCapitulo = capituloData['chapter_number'] ?? 1;
          final String htmlContenido = capituloData['chapter_html'] ?? '';

          final matches = regExpVersoHtml.allMatches(htmlContenido);

          for (var match in matches) {
            final int numVerso = int.parse(match.group(1)!);
            String textoLimpio = match.group(2)!
                .replaceAll(RegExp(r'<[^>]*>'), '') // Limpieza de tags HTML internos
                .replaceAll(r"\'", "'")
                .trim();
              // Inyectamos el convertidor aquí para limpiar los acentos
            textoLimpio = textoLimpio.replaceAllMapped(RegExp(r'&#([0-9]+);'), (Match m) {
            return String.fromCharCode(int.parse(m.group(1)!));
            });

            final String textoMinuscula = textoLimpio.toLowerCase();

            // Validación cruzada AND: Verifica que TODAS las palabras clave estén en el versículo
            bool cumpleFiltros = true;
            for (var palabra in palabrasClave) {
              if (!textoMinuscula.contains(palabra)) {
                cumpleFiltros = false;
                break;
              }
            }

            if (cumpleFiltros) {
              resultadosFiltradosJson.add({
                'libro_id': libroId,
                'capitulo': numCapitulo,
                'versiculo': numVerso,
                'texto': textoLimpio,
              });

              // Break de seguridad para no congelar la UI si hay demasiados resultados
              if (resultadosFiltradosJson.length >= 50) {
                return resultadosFiltradosJson;
              }
            }
          }
        }
      }
      return resultadosFiltradosJson;
    } catch (errJson) {
      print('Fallo crítico en el mapeador analítico de búsqueda JSON: $errJson');
    }

    return [];
  }

  // 🚀 CORRECCIÓN DEFINITIVA: Forzado el tipado estricto <int> en la conversión del mapeo de Supabase
  Future<Set<int>> obtenerVersiculosConReferenciasEnCapitulo(int libroId, int capitulo) async {
    try {
      final response = await _client
          .from('referencias_cruzadas')
          .select('origen_versiculo')
          .eq('origen_libro_id', libroId)
          .eq('origen_capitulo', capitulo)
          .timeout(const Duration(milliseconds: 1200));
      
      // 🚀 SOLUCIÓN: Usamos .cast<int>() para transformar la colección dinámica en un conjunto de enteros estricto
      return Set<int>.from(response.map((f) => f['origen_versiculo'])).cast<int>();
    } catch (_) { 
      return <int>{}; // Retorno de contingencia vacío fuertemente tipado
    }
  }

  // 🚀 COMPARADOR MULTI-VERSIÓN ASÍNCRONO ADAPTADO A CONTINGENCIA LOCAL
  Future<List<Map<String, dynamic>>> compararVersiculoEnVersiones(int libroId, int capitulo, int versiculo) async {
    try {
      final response = await _client
          .from('versiculos')
          .select('version_id, texto')
          .eq('libro_id', libroId)
          .eq('capitulo', capitulo)
          .eq('versiculo', versiculo);
      
      final resultadoNube = List<Map<String, dynamic>>.from(response);
      if (resultadoNube.isNotEmpty) return resultadoNube;
    } catch (e) {
      print('Docker / Supabase Cloud offline para comparativa de versiones: $e');
    }

    // Si estás desconectado, consulta de forma instantánea las dos versiones principales en tus archivos locales
    List<Map<String, dynamic>> comparacionesLocales = [];
    final versionesAComparar = ['RV1960', 'NVI'];

    for (var version in versionesAComparar) {
      try {
        final capituloCompleto = await obtenerCapitulo(libroId, capitulo, versionId: version);
        final versoEspecifico = capituloCompleto.firstWhere(
          (v) => v['versiculo'] == versiculo,
          orElse: () => {},
        );
        if (versoEspecifico.isNotEmpty) {
          comparacionesLocales.add({
            'version_id': version,
            'texto': versoEspecifico['texto'],
          });
        }
      } catch (_) {}
    }

    return comparacionesLocales;
  }

    // 🚀 LIMPIEZA DE CACHÉ GLOBAL MULTIPLATAFORMA
  Future<void> vaciarCacheCompleta() async {
    // 1. Limpiar estructuras en la memoria RAM
    _cacheCapitulos.clear();
    _cacheReferencias.clear();

    // 2. Limpiar base de datos local física (Solo si no es entorno Web)
    if (!kIsWeb) {
      try {
        final db = await databaseLocal;
        if (db != null) {
          final loteBatch = db.batch();
          loteBatch.delete('cache_versiculos');
          loteBatch.delete('cache_referencias');
          loteBatch.delete('cache_busquedas');
          await loteBatch.commit(noResult: true);
          print('Almacenamiento SQLite purgado con éxito.');
        }
      } catch (e) {
        print('Error al vaciar tablas locales de SQLite: $e');
      }
    }
  }

  // Trae los bosquejos guardados desde Supabase
  Future<List<Map<String, dynamic>>> obtenerHistorialBosquejos() async {
    try {
      final response = await _client
      .from('bosquejos')
      .select('id, titulo, contenido_json, updated_at')
      .order('updated_at', ascending: false)
      .limit(30);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) { 
      return []; 
    }
  }

  static const Map<int, int> _totalCapitulosPorLibro = {1: 50, 2: 40, 3: 27, 4: 36, 5: 34, 6: 24, 7: 21, 8: 4, 9: 31, 10: 24, 11: 22, 12: 25, 13: 29, 14: 36,15: 10, 16: 13, 17: 10, 18: 42, 19: 150, 20: 31, 21: 12, 22: 8, 23: 66, 24: 52, 25: 5, 26: 48, 27: 12,28: 14, 29: 3, 30: 9, 31: 1, 32: 4, 33: 7, 34: 3, 35: 3, 36: 3, 37: 2, 38: 14, 39: 4, 40: 28, 41: 16,42: 24, 43: 21, 44: 28, 45: 16, 46: 16, 47: 13, 48: 6, 49: 6, 50: 4, 51: 4, 52: 5, 53: 3, 54: 6, 55: 4,56: 3, 57: 1, 58: 13, 59: 5, 60: 5, 61: 3, 62: 5, 63: 1, 64: 1, 65: 1, 66: 22};

  int obtenerTotalCapitulos(int libroId) => _totalCapitulosPorLibro[libroId] ?? 1;
}
