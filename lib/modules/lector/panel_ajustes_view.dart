// lib/modules/lector/panel_ajustes_view.dart

import 'package:flutter/material.dart';
import '../../database/ajustes_config.dart';
import '../../database/biblia_db_helper.dart';

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
