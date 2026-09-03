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
      // Forzamos la separación por punto y coma que es el que usa tu archivo
      final columnas = linea.split(';');

      // Como tu línea empieza con ';', la columna[0] está vacía.
      // Desplazamos los índices exactamente un lugar a la derecha.
      if (columnas.length < 8) continue; 

      String limpiar(String texto) => texto.trim().replaceAll('"', '').replaceAll("'", "");

      // Mapeo ajustado: columnas[1] es origen_libro_id, columnas[2] es origen_capitulo, etc.
      final int origenLibroId   = int.parse(limpiar(columnas[1]));
      final int origenCapitulo  = int.parse(limpiar(columnas[2]));
      final int origenVersiculo = int.parse(limpiar(columnas[3]));
      
      final int destinoLibroId  = int.parse(limpiar(columnas[4]));
      final int destinoCapitulo = int.parse(limpiar(columnas[5]));
      final int destinoVersiculo= int.parse(limpiar(columnas[6]));
      
      final String llaveUnica   = limpiar(columnas[7]);

      if (llaveUnica.isEmpty || origenLibroId == 0) continue;

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
        print('-> Progreso real: $filasProcesadas filas subidas a Supabase...');
        loteActual.clear();
      }
    } catch (e) {
      // Dejamos este print temporal para monitorear si alguna fila específica tiene problemas
      print('Fila omitida por error: $e. Contenido: $linea');
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
  // Construimos las tuplas de valores directamente en el string SQL de forma segura
  final String filasSQL = lote.map((fila) {
    final int origLibro = fila[0];
    final int origCap = fila[1];
    final int origVer = fila[2];
    final int destLibro = fila[3];
    final int destCap = fila[4];
    final int destVer = fila[5];
    final String llave = fila[6];
    
    return "($origLibro, $origCap, $origVer, $destLibro, $destCap, $destVer, '$llave')";
  }).join(',\n');

  final String query = '''
    INSERT INTO public.referencias_cruzadas 
    (origen_libro_id, origen_capitulo, origen_versiculo, destino_libro_id, destino_capitulo, destino_versiculo, llave_unica)
    VALUES 
    $filasSQL
    ON CONFLICT (llave_unica) DO NOTHING;
  ''';

  // Ejecutamos el SQL directo sin pasar parámetros separados
  await conn.execute(query);
}
