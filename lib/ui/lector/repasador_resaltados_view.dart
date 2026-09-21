// lib/ui/lector/repasador_resaltados_view.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mi_app_biblica/data/biblia_db_helper.dart';

class RepasadorResaltadosView extends StatefulWidget {
  const RepasadorResaltadosView({super.key});

  @override
  State<RepasadorResaltadosView> createState() => _RepasadorResaltadosViewState();
}

class _RepasadorResaltadosViewState extends State<RepasadorResaltadosView> {
  final BibliaDatabaseHelper _dbHelper = BibliaDatabaseHelper();
  List<Map<String, dynamic>> _versosCargados = [];
  bool _cargando = true;

  // Lista canónica indexada requerida para el mapeo fuera de línea
  static const List<String> _librosLista = [
    'genesis', 'exodo', 'levitico', 'numeros', 'deuteronomio', 'josue', 'jueces', 'rut',
    '1_samuel', '2_samuel', '1_reyes', '2_reyes', '1_cronicas', '2_cronicas', 'esdras', 'nehemias',
    'ester', 'job', 'salmos', 'proverbios', 'eclesiastes', 'cantares', 'isaias', 'jeremias',
    'lamentaciones', 'ezequiel', 'daniel', 'oseas', 'joel', 'amos', 'abdias', 'jonas',
    'miqueas', 'nahum', 'habacuc', 'sofonias', 'hageo', 'zacarias', 'malaquias', 'mateo',
    'marcos', 'lucas', 'juan', 'hechos', 'romanos', '1_corintios', '2_corintios', 'galatas',
    'efesios', 'filipenses', 'colosenses', '1_tesalonicenses', '2_tesalonicenses', '1_timoteo',
    '2_timoteo', 'tito', 'filemon', 'hebreos', 'santiago', '1_pedro', '2_pedro', '1_juan',
    '2_juan', '3_juan', 'judas', 'apocalipsis'
  ];

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    await _sincronizarResaltadosConNube();
    if (mounted) _recuperarYProcesarMarcas();
  }

  // Si el pastor está autenticado, trae los resaltados de la tabla remota
  // resaltados_biblia y los fusiona con la caché local antes de armar la lista.
  Future<void> _sincronizarResaltadosConNube() async {
    final String? userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final List<dynamic> respuesta = await Supabase.instance.client
          .from('resaltados_biblia')
          .select('llave_resaltado, color_hex')
          .eq('user_id', userId);

      final prefs = await SharedPreferences.getInstance();
      final String? resaltadosRaw = prefs.getString('biblioteca_resaltados');

      Map<String, dynamic> mapaLocal = {};
      if (resaltadosRaw != null && resaltadosRaw.isNotEmpty) {
        try {
          mapaLocal = jsonDecode(resaltadosRaw) as Map<String, dynamic>;
        } catch (_) {}
      }

      for (var item in respuesta) {
        final String llave = item['llave_resaltado'].toString();
        final int color = (item['color_hex'] as num).toInt();
        if (color == 0) {
          mapaLocal.remove(llave);
        } else {
          mapaLocal[llave] = color;
        }
      }

      await prefs.setString('biblioteca_resaltados', jsonEncode(mapaLocal));
    } catch (e) {
      debugPrint('Error al sincronizar resaltados desde la nube: $e');
    }
  }

  void _recuperarYProcesarMarcas() async {
    if (mounted) setState(() => _cargando = true);
    
    final prefs = await SharedPreferences.getInstance();
    final String? resaltadosRaw = prefs.getString('biblioteca_resaltados');

    if (resaltadosRaw == null || resaltadosRaw.isEmpty) {
      if (mounted) setState(() { _versosCargados = []; _cargando = false; });
      return;
    }

    final Map<String, dynamic> mapaDecodificado = jsonDecode(resaltadosRaw);
    List<Map<String, dynamic>> listaTemporal = [];

    for (var entrada in mapaDecodificado.entries) {
      final partes = entrada.key.split('_');
      if (partes.length < 4) continue;

      final String versionId = partes[0];
      final int libroId = int.parse(partes[1]);
      final int capitulo = int.parse(partes[2]);
      final int versiculo = int.parse(partes[3]);
      final int colorHex = entrada.value as int;
      final String nombreLibro = _dbHelper.obtenerNombreLibro(libroId);
      final String citaFormateada = '$nombreLibro $capitulo:$versiculo ($versionId)';

      try {
        // 1. Intentar jalar el texto desde la base de datos de la PC (Supabase)
        final response = await Supabase.instance.client
            .from('versiculos')
            .select('texto')
            .eq('version_id', versionId)
            .eq('libro_id', libroId)
            .eq('capitulo', capitulo)
            .eq('versiculo', versiculo)
            .maybeSingle();

        if (response != null && response['texto'] != null) {
          listaTemporal.add({
            'llave': entrada.key, 'cita': citaFormateada, 'texto': response['texto'], 'color': colorHex,
          });
          continue; // Salta al siguiente versículo si hubo éxito online
        }
        throw 'Offline mode required';
      } catch (_) {
        // 2. CONTINGENCIA TOTAL OFFLINE: Lee el versículo desde los archivos .txt internos del teléfono
        try {
          final String nombreArchivo = _librosLista[libroId - 1];
          final String carpeta = versionId == 'RV1960' ? 'rvr1960' : 'nvi';
          final String data = await rootBundle.loadString('assets/$carpeta/$nombreArchivo.txt');
          
          final RegExp regExpTupla = RegExp(r"\(\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*'(.*)'\s*\)");
          final List<String> lineas = data.replaceAll('\r', '').split('\n');

          for (var linea in lineas) {
            final match = regExpTupla.firstMatch(linea.trim());
            if (match != null) {
              final int cap = int.parse(match.group(2)!);
              final int ver = int.parse(match.group(3)!);
              if (cap == capitulo && ver == versiculo) {
                listaTemporal.add({
                  'llave': entrada.key,
                  'cita': citaFormateada,
                  'texto': match.group(4)!.replaceAll(r"\'", "'").trim(),
                  'color': colorHex,
                });
                break;
              }
            }
          }
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _versosCargados = listaTemporal;
        _cargando = false;
      });
    }
  }

  void _removerMarcado(String llave) async {
    final prefs = await SharedPreferences.getInstance();
    final String? resaltadosRaw = prefs.getString('biblioteca_resaltados');
    if (resaltadosRaw != null) {
      Map<String, dynamic> mapa = jsonDecode(resaltadosRaw);
      mapa.remove(llave);
      await prefs.setString('biblioteca_resaltados', jsonEncode(mapa));
    }

    // Sincronización remota: elimina la fila correspondiente en la nube
    // usando el usuario actual para cumplir con las políticas RLS.
    final String? userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        await Supabase.instance.client
            .from('resaltados_biblia')
            .delete()
            .eq('user_id', userId)
            .eq('llave_resaltado', llave);
      } catch (e) {
        debugPrint('Error al eliminar resaltado de la nube: $e');
      }
    }

    _recuperarYProcesarMarcas(); // Recarga la lista de forma reactiva
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Marcas y Notas de Estudio', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _versosCargados.isEmpty
              ? const Center(child: Text('No hay versículos resaltados en tu biblioteca.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12.0),
                  itemCount: _versosCargados.length,
                  itemBuilder: (context, index) {
                    final item = _versosCargados[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(left: BorderSide(color: Color(item['color']), width: 6)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(14),
                          title: Text(item['cita'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(item['texto'], style: const TextStyle(fontSize: 16, color: Colors.black87, height: 1.4, fontFamily: 'serif')),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _removerMarcado(item['llave']),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}