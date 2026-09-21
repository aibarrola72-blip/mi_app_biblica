// lib/database/biblia_db_helper.dart

import 'dart:convert';
import 'package:flutter/foundation.dart'; // kIsWeb, compute y ValueNotifier
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart' as sql; // Importación limpia multiplataforma
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mi_app_biblica/domain/libros_catalogo.dart';
import 'package:mi_app_biblica/data/auth_service.dart';

class BibliaDatabaseHelper {
  static final BibliaDatabaseHelper _instance = BibliaDatabaseHelper._internal();
  factory BibliaDatabaseHelper() => _instance;
  BibliaDatabaseHelper._internal();

  final _client = Supabase.instance.client;
  dynamic _dbMobi; // Usamos tipo dinámico para blindar la compilación en Web
  Map<String, dynamic>? sermonEnTransito;
  // CACHÉ EN MEMORIA GLOBAL: Funciona tanto en Web como en Móvil a velocidad luz
  final Map<String, List<Map<String, dynamic>>> _cacheCapitulos = {};
  final Map<String, List<Map<String, dynamic>>> _cacheReferencias = {};

  // POBLACIÓN OFF LINE DE LA BIBLIOTECA EN SEGUNDO PLANO (progreso visible en el splash)
  bool _poblacionEnCurso = false;
  final ValueNotifier<String> _progresoOffline = ValueNotifier('');
  ValueNotifier<String> get progresoOffline => _progresoOffline;

  // Inicializador multiplataforma seguro: En Web no hace nada, en Móvil abre SQLite
  Future<dynamic> get databaseLocal async {
    if (kIsWeb) return null; // 🚀 SOLUCIÓN AL LOOP Y CAÍDA EN WEB: Retorna nulo sin tocar hardware
    if (_dbMobi != null) return _dbMobi;
    
    try {
      final rutaDb = await sql.getDatabasesPath();
      _dbMobi = await sql.openDatabase(
        '$rutaDb/biblioteca_pastoral_v4.db', // 🚀 v4 fuerza la recreación limpia de todas las tablas offline
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
      debugPrint('Error abriendo SQLite local en el dispositivo móvil: $e');
      return null;
    }
  }

  // Añade esto en tu clase BibliaDatabaseHelper debajo de obtenerLibroId
  Map<String, int> obtenerMapaAbreviaturas() {
    return Map.of(abreviaturasLibros);
  }

  String obtenerNombreLibro(int libroId) => nombresLibrosCanonicos[libroId] ?? 'Libro $libroId';
  String _removerAcentostildes(String texto) => removerAcentostildes(texto);
  // 🚀 REEMPLAZA EL MÉTODO EXACTO EN TU BIBLIA_DB_HELPER.DART
  int obtenerLibroId(String nombreLibro) => obtenerIdLibro(nombreLibro);

  // 🚀 LECTURA DE CAPÍTULO NUBE-PRIMERO CON CONTINGENCIA JSON LOCAL
  // Supabase es la fuente canónica cuando hay señal (y la cachea en SQLite);
  // si falla, se lee de SQLite y, en última instancia, del JSON en un isolate.
  Future<List<Map<String, dynamic>>> obtenerCapitulo(int libroId, int capitulo, {String versionId = 'RV1960'}) async {
    final llaveCache = '${versionId}_${libroId}_$capitulo';
    if (_cacheCapitulos.containsKey(llaveCache)) return _cacheCapitulos[llaveCache]!;

    // 1. NUBE: Supabase como fuente canónica cuando hay señal (y la cachea en SQLite)
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
      debugPrint('Servidor inalcanzable. Buscando persistencia local SQLite... $e');
    }

    // 2. PERSISTENCIA LOCAL SQLITE (suaviza la lectura offline con lo ya cacheado)
    if (!kIsWeb) {
      try {
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
      } catch (e) {
        debugPrint('Error de lectura en SQLite, usando JSON local: $e');
      }
    }

    // 3. CONTINGENCIA JSON: parseo pesado en un isolate para nunca congelar la interfaz
    try {
      final String nombreArchivo = _archivosJsonPorVersion[versionId] ?? 'rv1960';
      final String contenidoJsonCrudo = await rootBundle.loadString('assets/biblias/$nombreArchivo.json');

      final List<Map<String, dynamic>> textosOfflineJson = await compute(_parsearCapituloDesdeJson, {
        'contenido': contenidoJsonCrudo,
        'libroId': libroId,
        'capitulo': capitulo,
        'versionId': versionId,
      });

      if (textosOfflineJson.isNotEmpty) {
        _cacheCapitulos[llaveCache] = textosOfflineJson;
        return textosOfflineJson;
      }
    } catch (e) {
      debugPrint('Fallo crítico al mapear el nodo items del archivo bíblico JSON: $e');
    }

    return [];
  }

  // 🚀 POBLACIÓN COMPLETA DE LA BIBLIOTECA OFFLINE EN SEGUNDO PLANO
  // Lee cada JSON de Biblia en un isolate y vuelca todos sus versículos en
  // cache_versiculos (tabla con índice por capítulo). Se ejecuta una vez por
  // versión; las versiones terminadas se omiten en reinicios posteriores.
  Future<void> inicializarBibliotecaOffline() async {
    if (kIsWeb || _poblacionEnCurso) return;
    _poblacionEnCurso = true;
    try {
      final db = await databaseLocal;
      if (db == null) return;
      final prefs = await SharedPreferences.getInstance();

      for (final versionEntrada in _archivosJsonPorVersion.entries) {
        final String versionId = versionEntrada.key;
        final String prefClave = 'biblia_offline_completa_$versionId';
        if (prefs.getBool(prefClave) ?? false) continue;

        _progresoOffline.value = 'Preparando biblioteca offline ($versionId)...';
        final String contenido =
            await rootBundle.loadString('assets/biblias/${versionEntrada.value}.json');

        final List<List<dynamic>> filas = await compute(_parsearVersionJsonCompleta, {
          'contenido': contenido,
          'versionId': versionId,
        });

        for (int inicio = 0; inicio < filas.length; inicio += 1500) {
          final int finRes = inicio + 1500 > filas.length ? filas.length : inicio + 1500;
          final lote = db.batch();
          for (final fila in filas.sublist(inicio, finRes)) {
            lote.insert(
              'cache_versiculos',
              {
                'version_id': fila[0],
                'libro_id': fila[1],
                'capitulo': fila[2],
                'versiculo': fila[3],
                'texto': fila[4],
              },
              conflictAlgorithm: sql.ConflictAlgorithm.replace,
            );
          }
          await lote.commit(noResult: true);
        }
        await prefs.setBool(prefClave, true);
      }
    } catch (e) {
      debugPrint('Error al preparar la biblioteca offline: $e');
    } finally {
      _progresoOffline.value = '';
      _poblacionEnCurso = false;
    }
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
      debugPrint('Docker desconectado. Cargando referencias desde SQLite local... $e');
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

    // Sanitizamos el término de búsqueda ingresado por el pastor
    final String terminoSanitizado = _removerAcentostildes(consulta);
    final List<String> palabrasClave = terminoSanitizado.split(' ').where((w) => w.length > 2).toList();
    if (palabrasClave.isEmpty) return [];

    // 1. INTENTO EN LA NUBE (Supabase)
    try {
      final terminosFts = consulta.trim().split(' ').join(' & ');
      final response = await _client
          .from('versiculos')
          .select('libro_id, capitulo, versiculo, texto')
          .textSearch('fts_vector', terminosFts, config: 'spanish')
          .limit(50)
          .timeout(const Duration(milliseconds: 1800)); 

      final resultadoNube = List<Map<String, dynamic>>.from(response);
      if (resultadoNube.isNotEmpty) return resultadoNube;
    } catch (_) {}

    // 2. INTENTO EN CACHÉ SQLITE: Si ya existía una búsqueda idéntica previa (Solo Móvil)
    if (!kIsWeb) {
      try {
        final db = await databaseLocal;
        if (db != null) {
          final resultadoLocal = await db.query(
            'cache_busquedas',
            where: 'termino_busqueda = ?',
            whereArgs: [terminoSanitizado],
            limit: 50,
          );
          if (resultadoLocal.isNotEmpty) {
            return resultadoLocal.map((row) => Map<String, dynamic>.from(row)).toList();
          }
        }
      } catch (_) {}
    }

    // 3. SQUELCH DE CONTINGENCIA ABSOLUTO (Lectura de JSON Local)
    try {
      final String contenidoJsonCrudo = await rootBundle.loadString('assets/biblias/rv1960.json');
      final Map<String, dynamic> objetoBiblia = jsonDecode(contenidoJsonCrudo);
      final List<dynamic> librosJson = objetoBiblia['books'] ?? [];
      List<Map<String, dynamic>> resultadosFiltradosJson = [];

      for (int i = 0; i < librosJson.length; i++) {
        final Map<String, dynamic> libroMap = librosJson[i];
        final int libroId = i + 1;
        final List<dynamic> capitulosJson = libroMap['chapters'] ?? [];

        for (int c = 0; c < capitulosJson.length; c++) {
          final Map<String, dynamic> capituloData = capitulosJson[c];
          
          // 🚀 CORRECCIÓN CLAVE: Verificamos todas las llaves posibles de capítulos en JSON bíblicos
          // Si no encuentra 'chapter_number', intenta con 'chapter' o 'number'. Si todo falla, usa el índice del bucle + 1.
          final int numCapitulo = capituloData['chapter_number'] ?? 
                                  capituloData['chapter'] ?? 
                                  capituloData['number'] ?? 
                                  (c + 1);

          final List<dynamic> itemsVersiculos = capituloData['items'] ?? [];

          for (var item in itemsVersiculos) {
            if (item['type'] == 'verse') {
              final List<dynamic> numbersList = item['verse_numbers'] ?? [];
              if (numbersList.isEmpty) continue;
              
              final int numVerso = (numbersList.first as num).toInt();
              String textoLimpio = (item['lines'] as List).join(' ').trim();
              
              // Descodificador de acentos HTML decimales
              textoLimpio = textoLimpio.replaceAllMapped(
                RegExp(r'&#([0-9]+);'), 
                (Match m) => String.fromCharCode(int.parse(m.group(1)!))
              );
              
              // Comparamos quitando acentos a ambos lados
              final String textoEvaluar = _removerAcentostildes(textoLimpio);
              
              bool cumpleFiltros = true;
              for (var palabra in palabrasClave) {
                if (!textoEvaluar.contains(palabra)) { cumpleFiltros = false; break; }
              }

              if (cumpleFiltros) {
                resultadosFiltradosJson.add({
                  'libro_id': libroId,
                  'capitulo': numCapitulo, // 🟢 Ahora inyectará el número de capítulo real escaneado
                  'versiculo': numVerso,
                  'texto': textoLimpio,
                });
                if (resultadosFiltradosJson.length >= 50) return resultadosFiltradosJson;
              }
            }
          }
        }
      }
      return resultadosFiltradosJson;
    } catch (_) {}
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
      // 1. INTENTO REMOTO: Intenta traer todo desde Supabase en la nube
      final response = await _client
          .from('versiculos')
          .select('version_id, texto')
          .eq('libro_id', libroId)
          .eq('capitulo', capitulo)
          .eq('versiculo', versiculo);
      
      final resultadoNube = List<Map<String, dynamic>>.from(response);
      if (resultadoNube.isNotEmpty) return resultadoNube;
    } catch (e) {
      debugPrint('Servidor Supabase Cloud offline o lento para comparativa. Activando escaneo local: $e');
    }

    // 2. CONTINGENCIA LOCAL EXTENDIDA: Si está desconectado o en el celular físico,
    // recorremos todas las versiones en LOTES PARALELOS (4 a la vez) para no
    // congelar la tabla y evitar picos de RAM con 12 isolates simultáneos.
    List<Map<String, dynamic>> comparacionesLocales = [];

    // 🚀 ARREGLO COMPLETO ACTUALIZADO ACORDE A TU PUBSPEC.YAML:
    final versionesAComparar = [
      'RV1960', 'NVI', 'DHH', 'DHHS', 'LBLA',
      'NBLA', 'NTV', 'RVA2015', 'RVC', 'TLA', 'TLAI', 'NVIC'
    ];

    const int tamanoLote = 4;
    for (int inicio = 0; inicio < versionesAComparar.length; inicio += tamanoLote) {
      final finLote = inicio + tamanoLote > versionesAComparar.length
          ? versionesAComparar.length
          : inicio + tamanoLote;
      final lote = versionesAComparar.sublist(inicio, finLote);

      final resultadosLote = await Future.wait(
        lote.map((version) async {
          try {
            final capituloCompleto = await obtenerCapitulo(libroId, capitulo, versionId: version);

            final versoEspecifico = capituloCompleto.firstWhere(
              (v) => v['versiculo'] == versiculo,
              orElse: () => {},
            );

            if (versoEspecifico.isNotEmpty) {
              return <String, dynamic>{
                'version_id': version,
                'texto': versoEspecifico['texto'],
              };
            }
          } catch (_) {
            // Si el archivo JSON de alguna versión específica no existe o falla, se la salta sin romper las demás
          }
          return null;
        }),
      );

      for (final resultado in resultadosLote) {
        if (resultado != null) comparacionesLocales.add(resultado);
      }
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
          debugPrint('Almacenamiento SQLite purgado con éxito.');
        }
      } catch (e) {
        debugPrint('Error al vaciar tablas locales de SQLite: $e');
      }
    }
  }

  // Trae los bosquejos guardados desde Supabase
  // 🚀 REEMPLAZA ESTE MÉTODO EN TU BIBLIA_DB_HELPER.DART
  Future<List<Map<String, dynamic>>> obtenerHistorialBosquejos() async {
    try {
      final String? usuarioUid = _client.auth.currentUser?.id;
      if (usuarioUid == null) return [];

      // 🌐 CASO A: SI CORRE EN LA WEB (Depende 100% de la nube)
      if (kIsWeb) {
        final response = await _client
            .from('bosquejos')
            .select('*')
            .eq('usuario_id', usuarioUid)
            .order('updated_at', ascending: false);
        return List<Map<String, dynamic>>.from(response);
      } 
      
      // 📱 CASO B: SI CORRE EN EL DISPOSITIVO MÓVIL (Híbrido / Offline-First)
      else {
        try {
          // Intentamos descargar los últimos sermones actualizados desde Supabase
          final response = await _client
              .from('bosquejos')
              .select('*')
              .eq('usuario_id', usuarioUid)
              .order('updated_at', ascending: false)
              .timeout(const Duration(milliseconds: 1500)); // Timeout corto si la señal es mala
          
          final listNube = List<Map<String, dynamic>>.from(response);

          if (listNube.isNotEmpty) {
            // OPTATIVO: Aquí podrías guardar 'listNube' en tu _dbMobi local para actualizar la caché offline
            return listNube;
          }
        } catch (_) {
          // Si falló el internet en el celular, no pasa nada; salta al catch e intenta leer el disco local
        }

        // 💾 RESPALDO OFFLINE: Si no hay señal en el celular, lee la base de datos local SQLite
        final List<Map<String, dynamic>> locales = await _dbMobi.query(
          'bosquejos',
          orderBy: 'updated_at DESC',
        );
        return locales;
      }
    } catch (e) { 
      debugPrint('Error al obtener historial unificado: $e');
      return []; 
    }
  }

  // 🚀 A: MODIFICAR EL MÉTODO DE GUARDAR / ACTUALIZAR BOSQUEJO
  Future<bool> guardarBosquejo({required String id, required String titulo, required String contenidoJson}) async {
    try {
      final String? usuarioUid = _client.auth.currentUser?.id;
      if (usuarioUid == null) return false;

      await _client.from('bosquejos').upsert({
        'id': id,
        'usuario_id': usuarioUid, // 🚀 SE INYECTA EL ID AUTOMÁTICO DEL PASTOR
        'titulo': titulo,
        'contenido_json': contenidoJson,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error al guardar bosquejo multiusuario: $e');
      return false;
    }
  }

  /// 🚀 REGISTRO DE AVANCE DEVOCIONAL Y CÁLCULO DE RACHAS  
  // 🚀 REEMPLAZA TU FUNCIÓN EN BIBLIA_DB_HELPER.DART POR ESTA VERSIÓN INTEGRADA
  Future<bool> marcarCapituloComoLeido({
    required int libroId, 
    required int capitulo, 
    required int totalVersiculos,
    bool soloRegistrarVisita = false, // 🟢 1. Declaramos el parámetro opcional de control
  }) async {
    try {
      final String? usuarioUid = _client.auth.currentUser?.id;
      
      if (usuarioUid == null) {
        debugPrint('🔴 Intento de guardado devocional bloqueado: No hay una sesión de usuario activa.');
        return false;
      }

      final DateTime ahoraLocal = DateTime.now();
      final String fechaHoyPlana = "${ahoraLocal.year}-${ahoraLocal.month.toString().padLeft(2, '0')}-${ahoraLocal.day.toString().padLeft(2, '0')}";

      // 2. REGISTRO DEL CAPÍTULO: Esto se ejecuta SIEMPRE (manual o automático)
      await _client.from('progreso_lectura').upsert({
        'usuario_id': usuarioUid, 
        'libro_id': libroId,
        'capitulo': capitulo,
        'versiculos_leidos': totalVersiculos,
        'fecha_lectura': ahoraLocal.toIso8601String(),
      }, onConflict: 'usuario_id, libro_id, capitulo');

      // 🚀 3. EL FRENO DE MANO: Si es solo una visita o lectura automática,
      // guardamos el progreso y salimos de inmediato, SIN alterar el perfil de la racha.
      if (soloRegistrarVisita) {
        debugPrint('📊 Progreso de lectura guardado en silencio en Supabase.');
        return true; 
      }

      // 4. CÁLCULO DE RACHA PESADO: Solo se ejecuta si el pastor presiona el botón MANUALMENTE
      final perfil = await _client.from('perfiles_pastor').select('racha_actual, ultima_fecha_lectura').eq('id', usuarioUid).maybeSingle();
      int nuevaRacha = 1;

      if (perfil != null) {
        final int rachaActual = perfil['racha_actual'] ?? 0;
        final String? ultimaFechaRaw = perfil['ultima_fecha_lectura'];

        if (ultimaFechaRaw != null && ultimaFechaRaw.isNotEmpty) {
          // Solo intentamos analizar si trae al menos el formato YYYY-MM-DD (10 caracteres)
          final DateTime? fechaUltimaLectura = ultimaFechaRaw.length >= 10
              ? DateTime.tryParse(ultimaFechaRaw.substring(0, 10))
              : null;

          if (fechaUltimaLectura != null) {
            final DateTime fechaHoyCorte = DateTime.parse("$fechaHoyPlana 00:00:00");
            final int diferenciaDiasCalendario = fechaHoyCorte.difference(fechaUltimaLectura).inDays;

            if (diferenciaDiasCalendario == 1) {
              nuevaRacha = rachaActual + 1;
            } else if (diferenciaDiasCalendario == 0) {
              nuevaRacha = rachaActual;
            } else {
              nuevaRacha = 1;
            }
          }
        }
      }

      // Actualizamos el marcador del perfil del pastor utilizando su UUID
      await _client.from('perfiles_pastor').update({
        'racha_actual': nuevaRacha,
        'ultima_fecha_lectura': fechaHoyPlana,
      }).eq('id', usuarioUid);

      return true;
    } catch (e) {
      debugPrint('Error en cálculo de racha multiusuario: $e');
      return false;
    }
  }

  // 🚀 C: MODIFICAR EL MÉTODO DE ELIMINAR BOSQUEJO (Doble candado de seguridad)
  Future<bool> eliminarBosquejo(String id) async {
    try {
      final String? usuarioUid = _client.auth.currentUser?.id;
      if (usuarioUid == null) return false;

      await _client
          .from('bosquejos')
          .delete()
          .eq('id', id)
          .eq('usuario_id', usuarioUid); // 🚀 SEGURIDAD: Evita que un usuario borre un sermón ajeno
      return true;
    } catch (e) {
      debugPrint('Error al eliminar bosquejo: $e');
      return false;
    }
  }

  static const Map<int, int> _totalCapitulosPorLibro = {1: 50, 2: 40, 3: 27, 4: 36, 5: 34, 6: 24, 7: 21, 8: 4, 9: 31, 10: 24, 11: 22, 12: 25, 13: 29, 14: 36,15: 10, 16: 13, 17: 10, 18: 42, 19: 150, 20: 31, 21: 12, 22: 8, 23: 66, 24: 52, 25: 5, 26: 48, 27: 12,28: 14, 29: 3, 30: 9, 31: 1, 32: 4, 33: 7, 34: 3, 35: 3, 36: 3, 37: 2, 38: 14, 39: 4, 40: 28, 41: 16,42: 24, 43: 21, 44: 28, 45: 16, 46: 16, 47: 13, 48: 6, 49: 6, 50: 4, 51: 4, 52: 5, 53: 3, 54: 6, 55: 4,56: 3, 57: 1, 58: 13, 59: 5, 60: 5, 61: 3, 62: 5, 63: 1, 64: 1, 65: 1, 66: 22};

  int obtenerTotalCapitulos(int libroId) => _totalCapitulosPorLibro[libroId] ?? 1;

  // Añade este método al final de la clase BibliaDatabaseHelper en lib/database/biblia_db_helper.dart

  /// 📊 MOTOR ANALÍTICO: Calcula los 3 libros más predicados analizando las citas del editor
  Future<List<Map<String, dynamic>>> obtenerTopLibrosEstudiados() async {
    try {
      final List<Map<String, dynamic>> bosquejos = await obtenerHistorialBosquejos();
      if (bosquejos.isEmpty) return [];

      final Map<int, int> mapaFrecuencia = {};
      
      // Expresión regular robusta para interceptar libros con acentos y números de capítulos
      // final RegExp regExp = RegExp(r'\b([1-3]?\s?[A-Z][a-záéíóúÁÉÍÓÚñÑ]+)\s+([0-9]+):([0-9]+)\b');

      for (var b in bosquejos) {
        // Analizamos tanto el cuerpo JSON como el título del bosquejo por seguridad
        // 🚀 RECOMENDACIÓN: Modifica esta línea dentro de tu ciclo for para blindar el análisis:
        final String contenidoRaw = b['contenido_json'].toString();
        final String tituloRaw = b['titulo'].toString();

        // Reemplazamos caracteres de formato JSON comunes por espacios para no romper el RegExp
        final String textoLimpio = '$tituloRaw $contenidoRaw'
            .replaceAll(RegExp(r'[\{\}\[\]\(\)\"\,\\]'), ' ');

        // Y tu RegExp puede buscar de forma más libre en el texto limpio:
        final RegExp regExp = RegExp(r'([1-3]?\s?[A-Z][a-záéíóúÁÉÍÓÚñÑ]+)\s+([0-9]+)\s*:\s*([0-9]+)');
        final matches = regExp.allMatches(textoLimpio);

        for (var m in matches) {
          final int libroId = obtenerLibroId(m.group(1)!);
          if (libroId > 0) {
            mapaFrecuencia[libroId] = (mapaFrecuencia[libroId] ?? 0) + 1;
          }
        }
      }

      if (mapaFrecuencia.isEmpty) return [];

      // Ordenamos las entradas del mapa de mayor a menor frecuencia de referencias
      final listaOrdenada = mapaFrecuencia.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Mapeamos los 3 primeros resultados asignándoles su nombre canónico
      return listaOrdenada.take(3).map((e) => {
        'nombre': obtenerNombreLibro(e.key),
        'citas': e.value
      }).toList();
    } catch (e) {
      debugPrint('Aviso en el cálculo del Top 3 de libros base: $e');
      return [];
    }
  }
  // 🚀 EN TU BIBLIA DATABASE HELPER:
  Future<void> sincronizarResaltadoAnube(String llave, int colorHex) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return; // Si no está logueado, trabaja solo en local

      if (colorHex == 0) {
        // Si el color es cero, el pastor lo borró. Lo eliminamos de la nube.
        await _client
            .from('resaltados_biblia')
            .delete()
            .match({'user_id': user.id, 'llave_resaltado': llave});
            debugPrint('🗑️ Resaltado eliminado de la nube: $llave');
      } else {
        // Si seleccionó color, lo guardamos o actualizamos (Upsert)
        await _client.from('resaltados_biblia').upsert({
          'user_id': user.id,
          'llave_resaltado': llave,
          'color_hex': colorHex,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,llave_resaltado',
        );
        debugPrint('✨ Resaltado sincronizado exitosamente en Supabase: $llave (Color: $colorHex)');
      }
    } catch (e) {
      debugPrint('Aviso en sincronización de sombreado a Supabase: $e');
    }
  }

  // 📥 Cargar los resaltados de la nube al iniciar la app
  // Descarga solo los cambios posteriores al último sync (gt updated_at)
  // y los fusiona con la caché local previa. La primera vez trae todo.
  Future<Map<String, int>> descargarResaltadosDeNube() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return {};

      final prefs = await SharedPreferences.getInstance();
      final String? ultimoSyncRaw = prefs.getString('ultimo_sync_resaltados');
      final String? baseRaw = prefs.getString('biblioteca_resaltados');

      Map<String, dynamic> mapaLocal = {};
      if (baseRaw != null && baseRaw.isNotEmpty) {
        try {
          mapaLocal = jsonDecode(baseRaw) as Map<String, dynamic>;
        } catch (_) {}
      }

      var consulta = _client
          .from('resaltados_biblia')
          .select('llave_resaltado, color_hex, updated_at')
          .eq('user_id', user.id);
      if (ultimoSyncRaw != null && ultimoSyncRaw.isNotEmpty) {
        consulta = consulta.gt('updated_at', ultimoSyncRaw);
      }
      final List<dynamic> respuesta = await consulta;

      String? cursor = ultimoSyncRaw;
      for (var item in respuesta) {
        final String llave = item['llave_resaltado'].toString();
        final dynamic colorRaw = item['color_hex'];
        final int color = colorRaw is num ? colorRaw.toInt() : 0;

        if (color == 0) {
          mapaLocal.remove(llave);
        } else {
          mapaLocal[llave] = color;
        }

        final String? upd = item['updated_at']?.toString();
        if (upd != null && (cursor == null || upd.compareTo(cursor) > 0)) {
          cursor = upd;
        }
      }

      await prefs.setString('biblioteca_resaltados', jsonEncode(mapaLocal));
      if (cursor != null) await prefs.setString('ultimo_sync_resaltados', cursor);

      final Map<String, int> mapaDescargado = {};
      mapaLocal.forEach((k, v) => mapaDescargado[k] = v is num ? v.toInt() : 0);
      return mapaDescargado;
    } catch (e) {
      debugPrint('Error al descargar sombreados de Supabase: $e');
      return {};
    }
  }

  /// 📋 CONSULTA DE RACHAS: Trae los días continuos de lectura del pastor
  Future<int> obtenerRachaDevocional() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return 0; // Si está offline o sin loguear devuelve 0

      // Consulta tu tabla de estadísticas o perfiles en Supabase
      final datos = await _client
          .from('usuario_progreso')
          .select('racha_dias')
          .eq('user_id', user.id)
          .maybeSingle();

      return datos?['racha_dias'] ?? 0;
    } catch (e) {
      debugPrint('Aviso al obtener racha de Supabase: $e');
      return 0; // En caso de error o modo local, mantiene el contador en 0
    }
  }

  /// ⏳ CONSULTA DE TIEMPO: Trae los minutos invertidos en el editor/altar
  Future<int> obtenerMinutosInvertidosAltar() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return 0;

      final datos = await _client
          .from('usuario_progreso')
          .select('minutos_altar')
          .eq('user_id', user.id)
          .maybeSingle();

      return datos?['minutos_altar'] ?? 0;
    } catch (e) {
      debugPrint('Aviso al obtener tiempo de altar de Supabase: $e');
      return 0;
    }
  }

  // 🚀 EN TU BIBLIA_DB_HELPER (Al final del archivo)
  Future<Map<String, dynamic>> obtenerDashboardMetricasCompletas() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return {};

      // 1. Descargamos el registro completo de la tabla de progreso del usuario
      final datosProgreso = await _client
          .from('usuario_progreso')
          .select('racha_dias, total_capitulos_leidos, total_versiculos_leidos, minutos_semanales, minutos_mensuales, total_libros_completados')
          .eq('user_id', user.id)
          .maybeSingle();

      // 2. Descargamos el conteo de citas AT/NT si lo tienes en otra tabla o vista analítica
      final datosCitas = await _client
          .from('usuario_analitica_citas')
          .select('at_citas_count, nt_citas_count')
          .eq('user_id', user.id)
          .maybeSingle();

      // Devolvemos un solo mapa consolidado
      return {
        'racha_dias': datosProgreso?['racha_dias'] ?? 0,
        'total_capitulos_leidos': datosProgreso?['total_capitulos_leidos'] ?? 0,
        'total_versiculos_leidos': datosProgreso?['total_versiculos_leidos'] ?? 0,
        'minutos_semanales': datosProgreso?['minutos_semanales'] ?? 0,
        'minutos_mensuales': datosProgreso?['minutos_mensuales'] ?? 0,
        'total_libros_completados': datosProgreso?['total_libros_completados'] ?? 0,
        'at_citas_count': datosCitas?['at_citas_count'] ?? 0,
        'nt_citas_count': datosCitas?['nt_citas_count'] ?? 0,
      };
    } catch (e) {
      debugPrint('Aviso al recuperar métricas combinadas de Supabase: $e');
      return {};
    }
  }

  /// 📡 MOTOR DE TRANSMISIÓN MULTIMEDIA: Envía el versículo directo al proyector del templo
  Future<bool> proyectarPasajeEnVivo({
    required String ipComputadora, 
    required String plataforma, 
    required String cita, 
    required String textoVersiculo,
    required String contrasena,
    int puerto = 1112,
  }) async {
    try {
      final String mensajeCompleto = '"$textoVersiculo" \n— $cita';

      if (ipComputadora.isEmpty) {
        debugPrint('❌ No se indicó la IP de la computadora.');
        return false;
      }
      // 🎬 CONFIGURACIÓN A: SI LA IGLESIA UTILIZA OPENLP
      if (plataforma == "OpenLP") {
        final url = Uri.parse('http://$ipComputadora:1920/api/v1/alerts/text');
        // Enviamos el versículo como una Alerta de texto directo a la pantalla de OpenLP
        final response = await http.post(
          url,
          body: {'text': mensajeCompleto},
        ).timeout(const Duration(seconds: 3));
        debugPrint(
          'OpenLP respondió: '
          '${response.statusCode} - ${response.body}',
        );
        return response.statusCode >= 200 &&
          response.statusCode < 300;
      } 
      
      // 🎬 CONFIGURACIÓN B: SI LA IGLESIA UTILIZA QUELEA
      if (plataforma == 'Quelea') {
        // Quelea recibe comandos de alertas directas mediante su endpoint de control de pantalla
        final url = Uri.parse('http://$ipComputadora:$puerto/remote/html',);
        final String credencialesCifradas = base64Encode(utf8.encode(':$contrasena'));
        final response = await http.post(
          url,          
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Basic $credencialesCifradas',
          },
          body: jsonEncode({'text': mensajeCompleto,
              'cita': cita,
              'versiculo': textoVersiculo,}),
        ).timeout(const Duration(seconds: 3));
        debugPrint(
          'Quelea respondió: '
          '${response.statusCode} - ${response.body}',
        );
        return response.statusCode >= 200 && response.statusCode < 300;
      } 
      debugPrint('❌ Plataforma no reconocida: $plataforma');
      return false;     
    } catch (e) {
      debugPrint('❌ Error al proyectar pasaje: $e');
    return false;
    }
  }

    /// 📜 BITÁCORA CRONOLÓGICA: Extrae los capítulos leídos por el pastor para el modal del reloj
  Future<List<Map<String, dynamic>>> obtenerHistorialLectura() async {
    try {
      final String? usuarioUid = _client.auth.currentUser?.id;
      if (usuarioUid == null) {
        debugPrint('📜 Bitácora: sin sesión activa, se omite la consulta.');
        return [];
      }

      List<Map<String, dynamic>> registros;
      try {
        registros = await _consultarBitacoraRemota(usuarioUid);
      } catch (e) {
        // Primer intento falló (401 por token vencido en arranque en frío o red
        // lenta): se refresca la sesión y se reintenta una sola vez.
        debugPrint('📜 Primera consulta de bitácora falló ($e). Reintentando con token fresco...');
        try {
          await AuthService().asegurarSesionLista();
          registros = await _consultarBitacoraRemota(usuarioUid);
        } catch (retryError) {
          debugPrint('📜 Reintento de bitácora sin éxito: $retryError');
          return [];
        }
      }

      debugPrint('📜 Bitácora: ${registros.length} registros para el usuario $usuarioUid.');
      return registros;
    } catch (e) {
      debugPrint('Error al obtener la bitácora de lectura en el Helper: $e');
      return [];
    }
  }

  /// ⏳ Consulta con timeout tolerante a redes móviles lentas (4s).
  Future<List<Map<String, dynamic>>> _consultarBitacoraRemota(String usuarioUid) async {
    final response = await _client
        .from('progreso_lectura')
        .select('libro_id, capitulo, fecha_lectura')
        .eq('usuario_id', usuarioUid)
        .order('fecha_lectura', ascending: false)
        .timeout(const Duration(milliseconds: 4000));

    return List<Map<String, dynamic>>.from(response);
  }
}

// =====================================================================
// PARSERS TOP-LEVEL (aislables con compute): consumen mucho tiempo en la
// interfaz, por eso se ejecutan dentro de un isolate y nunca en el hilo UI.
// =====================================================================

const Map<String, String> _archivosJsonPorVersion = {
  'RV1960': 'rv1960', 'NVI': 'nvi128', 'RVC': 'rvc', 'RVA2015': 'rva2015',
  'TLA': 'tla', 'TLAI': 'tlai', 'NVIC': 'nvi1637', 'NTV': 'ntv',
  'NBLA': 'nbla', 'LBLA': 'lbla', 'DHH': 'dhh', 'DHHS': 'dhhs',
};

String _limpiarTextoHtml(String textoUnificado) {
  return textoUnificado
      .replaceAllMapped(RegExp(r'&#([0-9]+);'), (Match m) {
        return String.fromCharCode(int.parse(m.group(1)!));
      })
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Extrae un capítulo específico del JSON de una versión.
List<Map<String, dynamic>> _parsearCapituloDesdeJson(Map<String, Object> argumentos) {
  final String contenidoJsonCrudo = argumentos['contenido']! as String;
  final int libroId = argumentos['libroId']! as int;
  final int capitulo = argumentos['capitulo']! as int;
  final String versionId = argumentos['versionId']! as String;

  final Map<String, dynamic> objetoCampana = jsonDecode(contenidoJsonCrudo);
  final List<dynamic> librosJson = objetoCampana['books'] ?? [];
  final List<Map<String, dynamic>> textosOfflineJson = [];

  if (librosJson.isEmpty) return textosOfflineJson;
  if (libroId - 1 >= librosJson.length) return textosOfflineJson;

  final Map<String, dynamic> libroMap = librosJson[libroId - 1];
  final List<dynamic> capitulosJson = libroMap['chapters'] ?? [];

  if (capitulo - 1 >= capitulosJson.length) return textosOfflineJson;

  final Map<String, dynamic> capituloMap = capitulosJson[capitulo - 1];
  final List<dynamic> itemsVersiculos = capituloMap['items'] ?? [];

  for (var item in itemsVersiculos) {
    if (item['type'] == 'verse') {
      final List<dynamic> numerosVerso = item['verse_numbers'] ?? [];
      final List<dynamic> lineasTexto = item['lines'] ?? [];

      if (numerosVerso.isNotEmpty && lineasTexto.isNotEmpty) {
        textosOfflineJson.add({
          'libro_id': libroId,
          'capitulo': capitulo,
          'versiculo': numerosVerso.first as int,
          'texto': _limpiarTextoHtml(lineasTexto.join(' ')),
          'version_id': versionId,
        });
      }
    }
  }
  return textosOfflineJson;
}

/// Vuelca TODA una versión en filas planas [versionId, libroId, capitulo,
/// versiculo, texto] para insertarse por lote en cache_versiculos.
List<List<dynamic>> _parsearVersionJsonCompleta(Map<String, Object> argumentos) {
  final String contenidoJsonCrudo = argumentos['contenido']! as String;
  final String versionId = argumentos['versionId']! as String;

  final Map<String, dynamic> objetoCampana = jsonDecode(contenidoJsonCrudo);
  final List<dynamic> librosJson = objetoCampana['books'] ?? [];
  final List<List<dynamic>> filas = [];

  for (int idxLibro = 0; idxLibro < librosJson.length; idxLibro++) {
    final Map<String, dynamic> libroMap = librosJson[idxLibro];
    final List<dynamic> capitulosJson = libroMap['chapters'] ?? [];

    for (int idxCapitulo = 0; idxCapitulo < capitulosJson.length; idxCapitulo++) {
      final Map<String, dynamic> capituloMap = capitulosJson[idxCapitulo];
      final List<dynamic> itemsVersiculos = capituloMap['items'] ?? [];

      for (var item in itemsVersiculos) {
        if (item['type'] == 'verse') {
          final List<dynamic> numerosVerso = item['verse_numbers'] ?? [];
          final List<dynamic> lineasTexto = item['lines'] ?? [];

          if (numerosVerso.isNotEmpty && lineasTexto.isNotEmpty) {
            filas.add([
              versionId,
              idxLibro + 1,
              idxCapitulo + 1,
              numerosVerso.first as int,
              _limpiarTextoHtml(lineasTexto.join(' ')),
            ]);
          }
        }
      }
    }
  }
  return filas;
}
