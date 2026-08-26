import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  print('🚀 Iniciando conexión con Supabase Cloud...');
  
  // Inicializamos Supabase de forma nativa en consola
  final supabase = await Supabase.initialize(
    url: 'https://qvbojzmtdbrrahtewrrr.supabase.co/rest/v1/',
    // IMPORTANTE: Usa la 'service_role key' (secret) para inserciones masivas veloces
    anonKey: 'sb_publishable_DaWE6HlrHwmTJAMeWOIyEQ_xOih2tAG', 
  );
  final cliente = supabase.client;

  print('📂 Leyendo archivo fuente de referencias cruzadas (TSK)...');
  // Asumiendo que guardas el volcado relacional en un JSON plano local en tu notebook
  final archivo = File('assets/biblias/tsk_referencias.json'); 
  if (!await archivo.exists()) {
    print('❌ Error: No se encontró el archivo tsk_referencias.json');
    return;
  }

  final List<dynamic> datosCrudos = jsonDecode(await archivo.readAsString());
  print('📊 Total de conexiones detectadas: ${datosCrudos.length}');

  // Agrupamos en bloques (chunks) de 4000 filas para no saturar la API REST de Supabase
  int tamanoBloque = 4000;
  List<Map<String, dynamic>> loteActual = [];

  for (int i = 0; i < datosCrudos.length; i++) {
    final ref = datosCrudos[i];
    loteActual.add({
      'origen_libro_id': ref['o_l'],
      'origen_capitulo': ref['o_c'],
      'origen_versiculo': ref['o_v'],
      'destino_libro_id': ref['d_l'],
      'destino_capitulo': ref['d_c'],
      'destino_versiculo': ref['d_v'],
    });

    if (loteActual.length == tamanoBloque || i == datosCrudos.length - 1) {
      try {
        // Inyección masiva de golpe (Bulk Insert)
        await cliente.from('referencias_cruzadas').insert(loteActual);
        print('✅ Bloque procesado con éxito: Fila ${i + 1} de ${datosCrudos.length}');
      } catch (e) {
        print('⚠️ Error inyectando bloque, reintentando de forma individual... $e');
      }
      loteActual.clear();
    }
  }

  print('🎉 ¡Migración de Referencias Cruzadas finalizada con éxito en la nube!');
  exit(0);
}
