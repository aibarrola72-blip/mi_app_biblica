import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  final rutaCSV = 'referencias.csv'; 
  final fileInput = File(rutaCSV);

  if (!await fileInput.exists()) {
    print('Error: No se encontró el archivo referencias.csv');
    return;
  }

  print('Conectando directamente a la nube de Supabase...');
  
  // Conexión segura usando tus credenciales de red IPv4 (Pooler)
  final conn = await Connection.open(
    Endpoint(
      host: 'aws-0-us-east-1.pooler.supabase.com',
      database: 'postgres',
      username: 'postgres.qvbojzmtdbrrahtewrrr',
      password: 'vvtUNkdnclNPzpZk',
      port: 5432,
    ),
    settings: ConnectionSettings(
      sslMode: SslMode.require,
      // Añadimos tiempo de espera extra por si la red de internet es lenta
      queryTimeout: Duration(minutes: 5), 
    ),
  );

  print('¡Conectado con éxito! Limpiando tabla antes de la carga...');
  await conn.execute('TRUNCATE TABLE public.referencias_cruzadas RESTART IDENTITY CASCADE;');

  List<List<dynamic>> loteActual = [];
  final int tamanoLote = 3000; // Bloques óptimos para no saturar la red en la nube
  int filasProcesadas = 0;
  bool esPrimeraLinea = true;

  print('Iniciando subida masiva de las 432,949 filas a la nube...');

  final lineas = fileInput.openRead().transform(utf8.decoder).transform(const LineSplitter());

  await for (final linea in lineas) {
    if (esPrimeraLinea) {
      esPrimeraLinea = false;
      continue;
    }

    if (linea.trim().isEmpty) continue;

    try {
      final columnas = linea.split(','); // Si tu CSV usa punto y coma, cambia ',' por ';'

      final int origenLibroId   = int.parse(columnas[1].trim());
      final int origenCapitulo  = int.parse(columnas[2].trim());
      final int origenVersiculo = int.parse(columnas[3].trim());
      
      final int destinoLibroId  = int.parse(columnas[4].trim());
      final int destinoCapitulo = int.parse(columnas[5].trim());
      final int destinoVersiculo= int.parse(columnas[6].trim());
      
      final String llaveUnica   = columnas[7].trim().replaceAll("'", "");

      loteActual.add([
        origenLibroId,
        origenCapitulo,
        origenVersiculo,
        destinoLibroId,
        destinoCapitulo,
        destinoVersiculo,
        llaveUnica
      ]);

      if (loteActual.length >= tamanoLote) {
        await _subirLote(conn, loteActual);
        filasProcesadas += loteActual.length;
        print('-> Progreso: $filasProcesadas filas subidas a Supabase...');
        loteActual.clear();
      }
    } catch (e) {
      // Ignora errores visuales de filas vacías
    }
  }

  // Subir el remanente final
  if (loteActual.isNotEmpty) {
    await _subirLote(conn, loteActual);
    filasProcesadas += loteActual.length;
  }

  print('\n¡Éxito rotundo! Optimizando índices con VACUUM ANALYZE...');
  await conn.execute('VACUUM ANALYZE public.referencias_cruzadas;');

  await conn.close();
  print('¡Proceso terminado! Tus 432,949 referencias ya viven en Supabase.');
}

// Función encargada de inyectar el bloque de datos a PostgreSQL
  Future<void> _subirLote(Connection conn, List<List<dynamic>> lote) async {
    final String placeholders = lote.map((_) => '(?, ?, ?, ?, ?, ?, ?)').join(', ');
    
    final String query = '''
      INSERT INTO public.referencias_cruzadas 
      (origen_libro_id, origen_capitulo, origen_versiculo, destino_libro_id, destino_capitulo, destino_versiculo, llave_unica)
      VALUES $placeholders
      ON CONFLICT (llave_unica) DO NOTHING;
    ''';

    // Aplana la lista de listas en una sola lista continua de parámetros
    final List<dynamic> parametrosAplanados = lote.expand((fila) => fila).toList();

    // El método .execute() nativo de la v3 acepta el Query string y los parámetros directamente
    await conn.execute(
      query,
      parameters: parametrosAplanados,
    );
  }
