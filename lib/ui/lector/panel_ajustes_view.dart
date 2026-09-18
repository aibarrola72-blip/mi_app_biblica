// lib/modules/lector/panel_ajustes_view.dart

import 'package:flutter/material.dart';
import 'package:mi_app_biblica/data/ajustes_config.dart';
import 'package:mi_app_biblica/data/biblia_db_helper.dart';

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

                    // 🚀 AGREGA ESTE BLOQUE DENTRO DEL LIGAR DE WIDGETS DE TU PANELAJUSTESVIEW
                    const Divider(height: 30),
                    const Text(
                      'Conexión Multimedia del Templo', 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        // 1. Selector de Plataforma (Dropdown)
                        Expanded(
                          flex: 4,
                          child: DropdownButtonFormField<String>(
                            initialValue: widget.ajustes.softwareProyeccion,
                            decoration: InputDecoration(
                              labelText: 'Software',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'OpenLP', child: Text('OpenLP')),
                              DropdownMenuItem(value: 'Quelea', child: Text('Quelea')),
                            ],
                            onChanged: (nuevoSoftware) {
                              if (nuevoSoftware != null) {
                                widget.ajustes.guardarConfiguracionProyector(
                                  widget.ajustes.ipProyeccion, 
                                  nuevoSoftware,
                                  widget.ajustes.contrasenaProyeccion
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        
                        // 2. Caja de texto para ingresar la IP de la Iglesia
                        Expanded(
                          flex: 6,
                          child: TextFormField(
                            initialValue: widget.ajustes.ipProyeccion,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Dirección IP de la PC',
                              hintText: 'Ej: 192.168.1.50',
                              prefixIcon: const Icon(Icons.lan_rounded, size: 18),
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onChanged: (nuevaIp) {
                              // Guardamos el cambio de IP en SharedPreferences en tiempo real
                              widget.ajustes.guardarConfiguracionProyector(
                                nuevaIp.trim(), 
                                widget.ajustes.softwareProyeccion,
                                widget.ajustes.contrasenaProyeccion
                              );
                            },
                          ),
                        ),                        
                      ],
                    ),

                    // 🚀 AGREGA ESTE WIDGET DEBAJO DEL TEXTFORMFIELD DE LA IP EN TU PANELAJUSTESVIEW
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: widget.ajustes.contrasenaProyeccion,
                          obscureText: true, // Oculta la contraseña por privacidad pastoral
                          decoration: InputDecoration(
                            labelText: 'Contraseña de Quelea / OpenLP',
                            hintText: 'Ingrese la clave configurada en la PC',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (nuevaClave) {
                            // Guardamos la contraseña en tiempo real junto con la IP y el Software actual
                            widget.ajustes.guardarConfiguracionProyector(
                              widget.ajustes.ipProyeccion,
                              widget.ajustes.softwareProyeccion,
                              nuevaClave.trim(),
                            );
                          },
                        ),
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
