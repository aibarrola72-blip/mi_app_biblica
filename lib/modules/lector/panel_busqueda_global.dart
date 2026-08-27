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
    // Forzamos el redibujo inmediato del TextField para alternar el botón Clear reactivo
    setState(() {});

    if (consulta.trim().length < 3) {
      setState(() => _resultados = []);
      return;
    }

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

  /// 🎯 MOTOR DE RESALTADO DINÁMICO E INSENSIBLE A TILDES
  List<TextSpan> _crearFragmentosResaltados(String textoOriginal, String terminoBusqueda) {
    if (terminoBusqueda.isEmpty) return [TextSpan(text: textoOriginal)];

    // Mapeador interno para interceptar variantes con o sin acento de forma bidireccional
    String mapearRegExpIncentiva(String texto) {
      return texto
          .replaceAll(RegExp(r'[aáÁ]'), '[aáÁ]')
          .replaceAll(RegExp(r'[eéÉ]'), '[eéÉ]')
          .replaceAll(RegExp(r'[iíÍ]'), '[iíÍ]')
          .replaceAll(RegExp(r'[oóÓ]'), '[oóÓ]')
          .replaceAll(RegExp(r'[uúÚ]'), '[uúÚ]');
    }

    final String patronRegExp = mapearRegExpIncentiva(RegExp.escape(terminoBusqueda));
    final RegExp regex = RegExp(patronRegExp, caseSensitive: false);
    final List<TextSpan> fragmentos = [];
    int indiceActual = 0;

    for (final Match match in regex.allMatches(textoOriginal)) {
      if (match.start > indiceActual) {
        fragmentos.add(TextSpan(text: textoOriginal.substring(indiceActual, match.start)));
      }
      fragmentos.add(
        TextSpan(
          text: textoOriginal.substring(match.start, match.end),
          style: TextStyle(
            backgroundColor: Colors.yellow.shade300,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      );
      indiceActual = match.end;
    }

    if (indiceActual < textoOriginal.length) {
      fragmentos.add(TextSpan(text: textoOriginal.substring(indiceActual)));
    }

    return fragmentos;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _busquedaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String terminoBuscado = _busquedaController.text.trim();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          // Campo de texto de búsqueda optimizado con botón adaptativo Clear
          TextField(
            controller: _busquedaController,
            onChanged: _onTextoCambiado,
            decoration: InputDecoration(
              hintText: 'Buscar concepto (ej: "gracia amor")',
              prefixIcon: const Icon(Icons.search, color: Colors.blue),
              // 🚀 ÍCONO CLEAR RECTIVO COMPARTIDO:
              suffixIcon: _busquedaController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                      onPressed: () {
                        _busquedaController.clear();
                        setState(() => _resultados = []);
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          
          // Renderizado de estados y resultados con coincidencia de pintura fosforescente
          Expanded(
            child: _buscando
                ? const Center(child: CircularProgressIndicator())
                : _resultados.isEmpty
                    ? Center(
                        child: Text(
                          _busquedaController.text.length < 3
                              ? 'Escribe al menos 3 letras para buscar...'
                              : 'No se encontraron versículos.',
                          style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
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
                            elevation: 0.5,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey.shade200, width: 0.5),
                            ),
                            child: ListTile(
                              title: Text(
                                '$nombreLibro $cap:$ver',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A73E8), fontSize: 13),
                              ),
                              // 🚀 SUBTÍTULO ADAPTADO CON TEXTSPANS DE PINTURA MARCADORA:
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(color: Colors.black87, fontSize: 14, fontFamily: 'serif', height: 1.4),
                                    children: _crearFragmentosResaltados(v['texto'] ?? '', terminoBuscado),
                                  ),
                                ),
                              ),
                              onTap: () {
                                final String nombreLibroCita = _dbHelper.obtenerNombreLibro(libroId);
                                final String citaFormateada = '$nombreLibroCita $cap:$ver';

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
                                              Expanded(
                                                child: ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A73E8), foregroundColor: Colors.white),
                                                  icon: const Icon(Icons.rate_review_outlined),
                                                  label: const Text('Insertar en Sermón'),
                                                  onPressed: () {
                                                    CanalEventos().enviarCitaAlEditor(citaFormateada);
                                                    Navigator.pop(context);
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  icon: const Icon(Icons.menu_book),
                                                  label: const Text('Ir al Lector'),
                                                  onPressed: () {
                                                    Navigator.pop(context);
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
