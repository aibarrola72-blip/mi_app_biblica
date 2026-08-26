// lib/modules/lector/panel_ajustes_view.dart

import 'package:flutter/material.dart';
import '../../database/ajustes_config.dart';
import '../../database/biblia_db_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

class PanelAjustesView extends StatefulWidget {
  final AjustesConfig ajustes;

  const PanelAjustesView({super.key, required this.ajustes});

  @override
  State<PanelAjustesView> createState() => _PanelAjustesViewState();
}

class _PanelAjustesViewState extends State<PanelAjustesView> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      height: 400,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ajustes del Editor y Púlpito', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const Divider(),
          const SizedBox(height: 10),
          
          // 1. Selector de Tipo de Letra
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tipo de Letra:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              DropdownButton<String>(
                value: widget.ajustes.tipoLetra,
                items: const [
                  DropdownMenuItem(value: 'sans-serif', child: Text('Sans Serif (Moderna)')),
                  DropdownMenuItem(value: 'serif', child: Text('Serif (Libro Tradicional)')),
                  DropdownMenuItem(value: 'monospace', child: Text('Monospace (Notas)')),
                ],
                onChanged: (val) => widget.ajustes.guardarTipoLetra(val!),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // 2. Selector de Tamaño de Letra
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tamaño de Texto Base: ${widget.ajustes.tamanoLetra.toInt()} pt', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              Slider(
                value: widget.ajustes.tamanoLetra,
                min: 14.0,
                max: 30.0,
                divisions: 8,
                label: widget.ajustes.tamanoLetra.toString(),
                onChanged: (val) => widget.ajustes.guardarTamanoLetra(val),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 🚀 INYECTOR ADAPTADO: Lee, extrae las notas x del HTML de rv1960 y las sube a la nube
          ListTile(
            leading: const Icon(Icons.hub_rounded, color: Colors.purpleAccent),
            title: const Text(
              'MIGRAR REFERENCIAS DESDE RV1960.JSON', 
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purpleAccent),
            ),
            subtitle: const Text('Escanea las etiquetas de notas del HTML local y las inyecta en Supabase.'),
            onTap: () async {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator()),
              );

              try {
                final supabase = Supabase.instance.client;
                final dbHelper = BibliaDatabaseHelper();

                // 1. Cargamos el archivo JSON real de tu app en la notebook
                final String contenidoJsonCrudo = await DefaultAssetBundle.of(context)
                    .loadString('assets/biblias/rv1960.json');
                
                final Map<String, dynamic> objetoBiblia = jsonDecode(contenidoJsonCrudo);
                final List<dynamic> librosJson = objetoBiblia['books'] ?? [];

                List<Map<String, dynamic>> loteReferencias = [];
                int contadorTotal = 0;

                // Expresiones regulares para capturar el versículo actual y aislar sus notas cruzadas
                final RegExp regExpVersiculoBlock = RegExp(r'class="verse\s+v([0-9]+)"[^>]*>(.*?)<\/span>\s*<\/span>', dotAll: true);
                final RegExp regExpNotaCruzada = RegExp(r'class="body">(.*?)<\/span>', dotAll: true);

                // 2. Recorremos los libros y capítulos canónicos del archivo
                for (int i = 0; i < librosJson.length; i++) {
                  final int origenLibroId = i + 1;
                  final List<dynamic> capitulosJson = librosJson[i]['chapters'] ?? [];

                  for (var capData in capitulosJson) {
                    final int origenCapitulo = capData['chapter_number'] ?? 1;
                    final String htmlContenido = capData['chapter_html'] ?? '';

                    // Buscamos todos los bloques de versículos en el HTML
                    final matchesVersos = regExpVersiculoBlock.allMatches(htmlContenido);
                    
                    for (var matchV in matchesVersos) {
                      final int origenVersiculo = int.parse(matchV.group(1)!);
                      final String bloqueInternoHtml = matchV.group(2)!;

                      // Si el bloque de este versículo contiene una nota de referencia cruzada (#)
                      if (bloqueInternoHtml.contains('class="note x"')) {
                        final matchesNotas = regExpNotaCruzada.allMatches(bloqueInternoHtml);
                        
                        for (var matchN in matchesNotas) {
                          // Texto crudo de la nota (Ej: "2 Co. 4.6." o "Mt. 19.4; Mr. 10.6.")
                          String textoNotaRaw = matchN.group(1)!
                              .replaceAll(RegExp(r'<[^>]*>'), '') // Limpieza de tags
                              .trim();

                          // Separamos por punto y coma por si vienen múltiples citas en la misma nota
                          List<String> citasIndividuales = textoNotaRaw.split(';');

                          for (var cita in citasIndividuales) {
                            // Limpiamos la cita individual (Ej: "2 Co. 4.6")
                            String citaLimpia = cita.replaceAll(RegExp(r'\.$'), '').trim();
                            
                            // Analizamos la nomenclatura para extraer libro, capítulo y versículo de destino
                            final RegExp regexParseo = RegExp(r'([1-3]?\s?[A-Za-z\s\.]+)\s+([0-9]+)\.([0-9]+)');
                            final matchParseo = regexParseo.firstMatch(citaLimpia);

                            if (matchParseo != null) {
                              String nombreLibroDestino = matchParseo.group(1)!.trim().replaceAll('.', '');
                              int destCap = int.parse(matchParseo.group(2)!);
                              int destVer = int.parse(matchParseo.group(3)!);

                              // Traducimos la abreviatura del libro a su ID numérico correspondiente
                              int destinoLibroId = dbHelper.obtenerLibroId(nombreLibroDestino);

                              loteReferencias.add({
                                'origen_libro_id': origenLibroId,
                                'origen_capitulo': origenCapitulo,
                                'origen_versiculo': origenVersiculo,
                                'destino_libro_id': destinoLibroId,
                                'destino_capitulo': destCap,
                                'destino_versiculo': destVer,
                              });

                              contadorTotal++;

                              // Subida controlada en lotes de 2000 filas para evitar caídas por timeout
                              if (loteReferencias.length >= 2000) {
                                await supabase.from('referencias_cruzadas').insert(loteReferencias);
                                print('📤 Sincronizados $contadorTotal registros relacionales con la nube...');
                                loteReferencias.clear();
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }

                // Enviamos el remanente final de datos
                if (loteReferencias.isNotEmpty) {
                  await supabase.from('referencias_cruzadas').insert(loteReferencias);
                }

                if (context.mounted) {
                  Navigator.pop(context); // Cierra el indicador de carga
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('🎉 ¡Sincronizadas $contadorTotal referencias cruzadas con Supabase!'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (context.mounted) Navigator.pop(context);
                print('Error al procesar el HTML interno de rv1960: $e');
              }
            },
          ),

          ListTile(
            leading: const Icon(Icons.cleaning_services_rounded, color: Colors.redAccent),
            title: const Text(
              'Limpiar Caché de la Aplicación', 
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            subtitle: const Text('Borra versículos y búsquedas guardadas localmente.'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () async {
              // 1. Desplegar indicador de carga rápida
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator()),
              );

              // 2. Ejecutar la purga de memoria
              await BibliaDatabaseHelper().vaciarCacheCompleta();

              // 3. Cerrar indicador de carga y el menú inferior
              if (context.mounted) {
                Navigator.pop(context); // Cierra el indicador de carga
                Navigator.pop(context); // Cierra el modal de ajustes
                
                // 4. Mostrar confirmación visual en pantalla
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🧹 Memoria caché liberada. La aplicación se sincronizará de nuevo al leer.'),
                    backgroundColor: Colors.black87,
                  ),
                );
              }
            },
          ),
          // 3. Selector de Color de Fondo
          const Text('Color de Fondo de Lectura:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _circuloColor(0xFFFFFFFF, 'Blanco'),
              _circuloColor(0xFFF4ECD8, 'Sepia'),
              _circuloColor(0xFFF5F5F5, 'Gris Suave'),
              _circuloColor(0xFFE8F0FE, 'Azul Claro'),
            ],
          )
        ],
      ),
    );
  }

  Widget _circuloColor(int colorHex, String etiqueta) {
    bool seleccionado = widget.ajustes.colorFondoHex == colorHex;
    return GestureDetector(
      onTap: () => widget.ajustes.guardarColorFondo(colorHex),
      child: CircleAvatar(
        backgroundColor: Color(colorHex),
        radius: 20,
        child: seleccionado ? const Icon(Icons.check, color: Colors.blueGrey, size: 20) : null,
      ),
    );
  }
}
