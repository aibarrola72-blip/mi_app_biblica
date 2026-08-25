// lib/modules/lector/panel_busqueda_global.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../database/biblia_db_helper.dart';
import '../../database/pasaje_biblico_model.dart';
import '../../database/canal_eventos.dart';

class PanelBusquedaGlobal extends StatefulWidget {
  final ValueChanged<PasajeBiblico> onPasajeSeleccionado;

  const PanelBusquedaGlobal({super.key, required this.onPasajeSeleccionado});

  @override
  State<PanelBusquedaGlobal> createState() => _PanelBusquedaGlobalState();
}

class _PanelBusquedaGlobalState extends State<PanelBusquedaGlobal> {
  final BibliaDatabaseHelper _dbHelper = BibliaDatabaseHelper();
  final TextEditingController _busquedaController = TextEditingController();
  
  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  Timer? _debounceTimer;

  void _onTextoCambiado(String consulta) {
    // Evitamos peticiones innecesarias si el usuario borra el texto
    if (consulta.trim().length < 3) {
      setState(() => _resultados = []);
      return;
    }

    // Patrón Debouncer: Espera 600ms antes de disparar la búsqueda en Supabase
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() => _buscando = true);

      final datos = await _dbHelper.buscarPalabraClaveGlobal(consulta);

      if (!mounted) return;
      setState(() {
        _resultados = datos;
        _buscando = false;
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _busquedaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          // Campo de texto de búsqueda optimizado
          TextField(
            controller: _busquedaController,
            onChanged: _onTextoCambiado,
            decoration: InputDecoration(
              hintText: 'Buscar concepto (ej: "gracia amor")',
              prefixIcon: const Icon(Icons.search, color: Colors.blue),
              suffixIcon: _busquedaController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _busquedaController.clear();
                        setState(() => _resultados = []);
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          
          // Renderizado de estados y resultados
          Expanded(
            child: _buscando
                ? const Center(child: CircularProgressIndicator())
                : _resultados.isEmpty
                    ? Center(
                        child: Text(
                          _busquedaController.text.length < 3
                              ? 'Escribe al menos 3 letras para buscar...'
                              : 'No se encontraron versículos.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _resultados.length,
                        itemBuilder: (context, index) {
                          final v = _resultados[index];
                          final int libroId = v['libro_id'] ?? 43;
                          final int cap = v['capitulo'] ?? 1;
                          final int ver = v['versiculo'] ?? 1;
                          final String nombreLibro = _dbHelper.obtenerNombreLibro(libroId);

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(
                                '$nombreLibro $cap:$ver',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(v['texto'] ?? '', style: const TextStyle(color: Colors.black87)),
                              ),
                              onTap: () {
                                final String nombreLibro = _dbHelper.obtenerNombreLibro(libroId);
                                final String citaFormateada = '$nombreLibro $cap:$ver';

                                // 🚀 INTERACCIÓN EXPANDIDA: Menú contextual rápido de decisión
                                showModalBottomSheet(
                                  context: context,
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                                  builder: (context) {
                                    return Container(
                                      padding: const EdgeInsets.all(16),
                                      height: 160,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Pasaje: $citaFormateada', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              // Opción A: Mandar el texto/cita directo al editor Quill
                                              Expanded(
                                                child: ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A73E8), foregroundColor: Colors.white),
                                                  icon: const Icon(Icons.rate_review_outlined),
                                                  label: const Text('Insertar en Sermón'),
                                                  onPressed: () {
                                                    // Transmitimos por el canal de radio en segundo plano
                                                    CanalEventos().enviarCitaAlEditor(citaFormateada);
                                                    Navigator.pop(context); // Cierra el modal
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              // Opción B: Tu lógica original de saltar a la pantalla del lector
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  icon: const Icon(Icons.menu_book),
                                                  label: const Text('Ir al Lector'),
                                                  onPressed: () {
                                                    Navigator.pop(context); // Cierra el modal
                                                    widget.onPasajeSeleccionado(PasajeBiblico(
                                                      libroId: libroId,
                                                      capitulo: cap,
                                                      versiculo: ver,
                                                      textoOriginal: citaFormateada,
                                                    ));
                                                  },
                                                ),
                                              ),
                                            ],
                                          )
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
