// lib/ui/lector/repasador_resaltados_view.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    // La fusión con la nube y el armado de la lista corren en paralelo:
    // ya no se serializan (antes: 1 select por versículo + espera total).
    final Future<void> sincronizacion = _sincronizarResaltadosConNube();
    await Future.wait([sincronizacion, _recuperarYProcesarMarcas()]);
    // Refleja lo que haya bajado la fusión con la nube (caché ya tibia)
    if (mounted) await _recuperarYProcesarMarcas();
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

  Future<void> _recuperarYProcesarMarcas() async {
    if (mounted) setState(() => _cargando = true);

    final prefs = await SharedPreferences.getInstance();
    final String? resaltadosRaw = prefs.getString('biblioteca_resaltados');

    if (resaltadosRaw == null || resaltadosRaw.isEmpty) {
      if (mounted) setState(() { _versosCargados = []; _cargando = false; });
      return;
    }

    final Map<String, dynamic> mapaDecodificado = jsonDecode(resaltadosRaw);

    // 1) Índices en memoria (sin I/O): metadatos por llave y llaves agrupadas
    //    por capítulo → UNA sola llamada a la capa Data por capítulo.
    final Map<String, Map<String, dynamic>> metaPorLlave = {};
    final Map<String, List<String>> llavesPorCapitulo = {};

    for (final entrada in mapaDecodificado.entries) {
      final partes = entrada.key.split('_');
      if (partes.length < 4) continue;

      final String versionId = partes[0];
      final int? libroId = int.tryParse(partes[1]);
      final int? capitulo = int.tryParse(partes[2]);
      final int? versiculo = int.tryParse(partes[3]);
      final int colorHex = entrada.value is num ? (entrada.value as num).toInt() : 0;
      if (libroId == null || capitulo == null || versiculo == null) continue;
      if (colorHex == 0) continue; // borrado lógico: ya no se representa

      metaPorLlave[entrada.key] = {
        'cita': '${_dbHelper.obtenerNombreLibro(libroId)} $capitulo:$versiculo ($versionId)',
        'color': colorHex,
      };
      llavesPorCapitulo
          .putIfAbsent('${versionId}_${libroId}_$capitulo', () => [])
          .add(entrada.key);
    }

    // 2) Texto por capítulo vía Data (nube → SQLite cache_versiculos → JSON en
    //    isolate, con caché en memoria). Antes: 1 select remoto + 1 parseo TXT
    //    COMPLETO por cada versículo marcardo.
    final Map<String, String> textosPorLlave = {};
    for (final grupo in llavesPorCapitulo.entries) {
      final partes = grupo.key.split('_');
      final String versionId = partes[0];
      final int libroId = int.parse(partes[1]);
      final int capitulo = int.parse(partes[2]);

      final Map<int, String> llavePorNumero = {};
      for (final llave in grupo.value) {
        final int? numero = int.tryParse(llave.split('_')[3]);
        if (numero != null) llavePorNumero[numero] = llave;
      }

      try {
        final List<Map<String, dynamic>> versiculos =
            await _dbHelper.obtenerCapitulo(libroId, capitulo, versionId: versionId);
        for (final v in versiculos) {
          final int? numero = int.tryParse('${v['versiculo']}');
          final String? texto = v['texto']?.toString();
          final String? llave = numero == null ? null : llavePorNumero[numero];
          if (llave != null && texto != null) textosPorLlave[llave] = texto;
        }
      } catch (e) {
        debugPrint('Sin texto disponible para $versionId $libroId:$capitulo — $e');
      }
    }

    // 3) Armado final preservando el orden original de prefs
    final List<Map<String, dynamic>> listaTemporal = [];
    for (final entrada in mapaDecodificado.entries) {
      final Map<String, dynamic>? meta = metaPorLlave[entrada.key];
      final String? texto = textosPorLlave[entrada.key];
      if (meta == null || texto == null) continue;
      listaTemporal.add({
        'llave': entrada.key,
        'cita': meta['cita'],
        'texto': texto,
        'color': meta['color'],
      });
    }

    if (mounted) {
      setState(() {
        _versosCargados = listaTemporal;
        _cargando = false;
      });
    }
  }

  Future<void> _removerMarcado(String llave) async {
    final prefs = await SharedPreferences.getInstance();
    final String? resaltadosRaw = prefs.getString('biblioteca_resaltados');
    if (resaltadosRaw != null) {
      Map<String, dynamic> mapa = jsonDecode(resaltadosRaw);
      mapa.remove(llave);
      await prefs.setString('biblioteca_resaltados', jsonEncode(mapa));
    }

    // Única ruta de escritura en nube (capa Data): borrado LÓGICO color_hex = 0,
    // que sí se propaga a otros dispositivos por el cursor gt(updated_at).
    unawaited(_dbHelper.sincronizarResaltadoAnube(llave, 0));

    await _recuperarYProcesarMarcas(); // Recarga la lista de forma reactiva
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