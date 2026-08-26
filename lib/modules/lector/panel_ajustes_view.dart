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
      // Se eliminó el 'height: 400' fijo para permitir un crecimiento dinámico
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min, // Se adapta al tamaño del contenido
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Línea estética superior para indicar que es un panel deslizable
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Text(
                'Ajustes del Editor y Púlpito', 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
            ),
            const Divider(height: 1),
            
            // Contenedor dinámico y desplazable para evitar desbordamientos
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          onChanged: (val) => setState(() => widget.ajustes.guardarTipoLetra(val!)),
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
                          onChanged: (val) => setState(() => widget.ajustes.guardarTamanoLetra(val)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 3. Selector de Color de Fondo
                    const Text('Color de Fondo de Lectura:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _circuloColor(0xFFFFFFFF, 'Blanco'),
                        _circuloColor(0xFFF4ECD8, 'Sepia'),
                        _circuloColor(0xFFF5F5F5, 'Gris Suave'),
                        _circuloColor(0xFFE8F0FE, 'Azul Claro'),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 15.0),
                      child: Divider(),
                    ),

                    // 4. Herramientas Avanzadas (Migración y Limpieza)
                    Card(
                      elevation: 0,
                      color: Colors.grey[50],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.hub_rounded, color: Colors.purpleAccent),
                            title: const Text(
                              'MIGRAR REFERENCIAS DESDE RV1960.JSON', 
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purpleAccent),
                            ),
                            subtitle: const Text('Escanea las etiquetas de notas del HTML local y las inyecta en Supabase.', style: TextStyle(fontSize: 12)),
                            onTap: () async {
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => const Center(child: CircularProgressIndicator()),
                              );

                              try {
                                final supabase = Supabase.instance.client;
                                final dbHelper = BibliaDatabaseHelper();

                                final String contenidoJsonCrudo = await DefaultAssetBundle.of(context)
                                    .loadString('assets/biblias/rv1960.json');
                                
                                final Map<String, dynamic> objetoBiblia = jsonDecode(contenidoJsonCrudo);
                                final List<dynamic> librosJson = objetoBiblia['books'] ?? [];

                                List<Map<String, dynamic>> loteReferencias = [];
                                int contadorTotal = 0;

                                final RegExp regExpVersiculoBlock = RegExp(r'class="verse\s+v([0-9]+)"[^>]*>(.*?)<\/span>\s*<\/span>', dotAll: true);
                                final RegExp regExpNotaCruzada = RegExp(r'class="body">(.*?)<\/span>', dotAll: true);

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

                                      if (bloqueInternoHtml.contains('class="note x"')) {
                                        final matchesNotas = regExpNotaCruzada.allMatches(bloqueInternoHtml);
                                        
                                        for (var matchN in matchesNotas) {
                                          String textoNotaRaw = matchN.group(1)!
                                              .replaceAll(RegExp(r'<[^>]*>'), '')
                                              .trim();

                                          List<String> citasIndividuales = textoNotaRaw.split(';');

                                          for (var cita in citasIndividuales) {
                                            String citaLimpia = cita.replaceAll(RegExp(r'\.$'), '').trim();
                                            
                                            final RegExp regexParseo = RegExp(r'([1-3]?\s?[A-Za-z\s\.]+)\s+([0-9]+)\.([0-9]+)');
                                            final matchParseo = regexParseo.firstMatch(citaLimpia);

                                            if (matchParseo != null) {
                                              String nombreLibroDestino = matchParseo.group(1)!.trim().replaceAll('.', '');
                                              int destCap = int.parse(matchParseo.group(2)!);
                                              int destVer = int.parse(matchParseo.group(3)!);

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

                          const Divider(height: 1),
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
