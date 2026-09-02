import 'dart:convert';
import 'dart:io';

void main() async {
  // 1. Ruta del archivo CSV generado
  final rutaCSV = 'referencias.csv'; 
  final fileInput = File(rutaCSV);

  if (!await fileInput.exists()) {
    print('Error: No se encontró el archivo referencias.csv');
    return;
  }

  // 2. Archivo SQL de salida
  final archivoSalida = File('importacion_referencias.sql');
  final sink = archivoSalida.openWrite();

  print('Procesando 432,949 filas en modo Stream de alta velocidad...');
  
  // Limpieza inicial de la tabla por seguridad
  sink.writeln('TRUNCATE TABLE public.referencias_cruzadas RESTART IDENTITY CASCADE;\n');

  List<String> loteActual = [];
  final int tamanoLote = 5000; 
  int filasProcesadas = 0;
  bool esPrimeraLinea = true;

  // Leemos línea por línea de manera eficiente sin sobrecargar la RAM
  final lineas = fileInput.openRead().transform(utf8.decoder).transform(const LineSplitter());

  await for (final linea in lineas) {
    // Saltamos la fila de encabezados del CSV
    if (esPrimeraLinea) {
      esPrimeraLinea = false;
      continue;
    }

    if (linea.trim().isEmpty) continue;

    try {
      // El separador estándar de Excel suele ser la coma (,) o el punto y coma (;)
      // Si tu archivo usa punto y coma, cambia ',' por ';'
      final columnas = linea.split(','); 

      // Mapeo exacto omitiendo la primera columna del ID:
      // Col 1: origen_libro_id, Col 2: origen_capitulo, Col 3: origen_versiculo
      // Col 4: destino_libro_id, Col 5: destino_capitulo, Col 6: destino_versiculo
      // Col 7: llave_unica
      final int origenLibroId   = int.parse(columnas[1].trim());
      final int origenCapitulo  = int.parse(columnas[2].trim());
      final int origenVersiculo = int.parse(columnas[3].trim());
      
      final int destinoLibroId  = int.parse(columnas[4].trim());
      final int destinoCapitulo = int.parse(columnas[5].trim());
      final int destinoVersiculo= int.parse(columnas[6].trim());
      
      final String llaveUnica   = columnas[7].trim().replaceAll("'", ""); // Limpiamos comillas si existen

      loteActual.add("($origenLibroId, $origenCapitulo, $origenVersiculo, $destinoLibroId, $destinoCapitulo, $destinoVersiculo, '$llaveUnica')");

      if (loteActual.length >= tamanoLote) {
        sink.writeln('INSERT INTO public.referencias_cruzadas (origen_libro_id, origen_capitulo, origen_versiculo, destino_libro_id, destino_capitulo, destino_versiculo, llave_unica) VALUES');
        sink.writeln('${loteActual.join(',\n')}\nON CONFLICT (llave_unica) DO NOTHING;\n');
        filasProcesadas += loteActual.length;
        loteActual.clear();
      }
    } catch (e) {
      // Ignora filas mal formateadas o vacías silenciosamente
    }
  }

  // Escribir los registros restantes
  if (loteActual.isNotEmpty) {
    sink.writeln('INSERT INTO public.referencias_cruzadas (origen_libro_id, origen_capitulo, origen_versiculo, destino_libro_id, destino_capitulo, destino_versiculo, llave_unica) VALUES');
    sink.writeln('${loteActual.join(',\n')}\nON CONFLICT (llave_unica) DO NOTHING;\n');
    filasProcesadas += loteActual.length;
  }

  // Optimización de rendimiento para Supabase
  sink.writeln('VACUUM ANALYZE public.referencias_cruzadas;');

  await sink.close();
  print('¡Éxito rotundo! Archivo "importacion_referencias.sql" generado con $filasProcesadas filas.');
}
