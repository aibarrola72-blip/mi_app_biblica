// lib/modules/lector/visor_biblia_libro.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/biblia_db_helper.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../database/ajustes_config.dart';
import '../../database/canal_eventos.dart';
// import 'package:supabase_flutter/supabase_flutter.dart'; 
import 'package:share_plus/share_plus.dart';

class VisorBibliaLibro extends StatefulWidget {
  const VisorBibliaLibro({super.key});

  @override
  State<VisorBibliaLibro> createState() => _VisorBibliaLibroState();
}

class _VisorBibliaLibroState extends State<VisorBibliaLibro> {
  final BibliaDatabaseHelper _dbHelper = BibliaDatabaseHelper();
  
  String _versionSeleccionada = 'RV1960';
  int _libroSeleccionado = 1; 
  int _capituloSeleccionado = 1;
  
  List<Map<String, dynamic>> _versiculos = [];
  bool _cargando = true;
  Map<String, int> _resaltadosLocales = {};

  // 🚀 HISTORIAL: Guarda el rastro de lectura para poder regresar. Ej: [{'libro': 1, 'capitulo': 1}]
  final List<Map<String, int>> _historialNavegacionRegreso = [];
  
  // 🚀 CONECTORES: Almacena qué versículos del capítulo actual tienen enlaces para ponerles el ícono 🔗
  final Set<int> _versiculosConReferenciasCargados = {};
  
  final Set<int> _versiculosSeleccionados = {};
  bool _modoSeleccionMultiple = false;
  final AjustesConfig _ajustesGlobales = AjustesConfig();

  @override
  void initState() {
    super.initState();
    _ajustesGlobales.cargarAjustes();
    _ajustesGlobales.addListener(() { if (mounted) setState(() {}); });
    _recuperarUltimoProgresoYTexto(); 
  }

  // 🚀 MOTOR DE PERSISTENCIA DE LECTURA (Guarda dónde se quedó el pastor)
  void _guardarPuntoDeLecturaActual() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ultima_version_leida', _versionSeleccionada);
      await prefs.setInt('ultimo_libro_leido', _libroSeleccionado);
      await prefs.setInt('ultimo_capitulo_leido', _capituloSeleccionado);
    } catch (e) {
      print('Aviso de guardado de progreso: $e');
    }
  }

  // Carga inicial optimizada con recuperación de memoria histórica
  void _recuperarUltimoProgresoYTexto() async {
    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _versionSeleccionada = prefs.getString('ultima_version_leida') ?? 'RV1960';
      _libroSeleccionado = prefs.getInt('ultimo_libro_leido') ?? 1;
      _capituloSeleccionado = prefs.getInt('ultimo_capitulo_leido') ?? 1;
    });

    _cargarResaltadosYTexto(); 
  }

  // 🚀 REEMPLAZA ESTA FUNCIÓN EN TU VISOR_BIBLIA_LIBRO.DART
  void _mostrarDialogoComparativaVersiones(int versiculoIndividual) { // <-- Cambiado el parámetro para que coincida
    final String nombreLibro = _dbHelper.obtenerNombreLibro(_libroSeleccionado);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Comparativa: $nombreLibro $_capituloSeleccionado:$versiculoIndividual',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  // Consumimos el helper usando el nombre de variable correcto
                  future: _dbHelper.compararVersiculoEnVersiones(_libroSeleccionado, _capituloSeleccionado, versiculoIndividual),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text('No hay otras versiones cargadas en la base de datos para este texto.'));
                    }

                    final comparaciones = snapshot.data!;
                    return ListView.builder(
                      itemCount: comparaciones.length,
                      itemBuilder: (context, idx) {
                        final comp = comparaciones[idx];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Píldora visual de la versión (NVI, TLA, RV1960)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  comp['version_id'] ?? 'RV1960',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue),
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Texto bíblico en esa traducción específica
                              Text(
                                comp['texto'] ?? '',
                                style: const TextStyle(fontSize: 16, color: Colors.black87, fontFamily: 'serif'),
                              ),
                              const Divider(color: Colors.black12, height: 20),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _cargarResaltadosYTexto() async {
    if (mounted) setState(() => _cargando = true);
    _versiculosSeleccionados.clear();
    _modoSeleccionMultiple = false;

    // 1. Cargamos marcas de resaltados de la memoria flash del teléfono
    final prefs = await SharedPreferences.getInstance();
    final String? resaltadosRaw = prefs.getString('biblioteca_resaltados');
    if (resaltadosRaw != null) {
      final Map<String, dynamic> decoded = jsonDecode(resaltadosRaw);
      _resaltadosLocales = decoded.map((key, value) => MapEntry(key, value as int));
    }

    // 2. NIVEL HÍBRIDO (Supabase con caída automática a SQLite Local)
    List<Map<String, dynamic>> datos = await _dbHelper.obtenerCapitulo(
      _libroSeleccionado,
      _capituloSeleccionado,
      versionId: _versionSeleccionada,
    );

    // 3. 🚀 SQUELCH DE CONTINGENCIA ABSOLUTO (Modo Avión sin caché previa)
    // Si Supabase falló Y SQLite está en blanco, extraemos la información del JSON local
    if (datos.isEmpty) {
      try {
        final Map<String, String> mapeoArchivosJson = {
          'RV1960': 'rv1960', 'NVI': 'nvi128', 'RVC': 'rvc', 'RVA2015': 'rva2015',
          'TLA': 'tla', 'TLAI': 'tlai', 'NVIC': 'nvi1637', 'NTV': 'ntv',
          'NBLA': 'nbla', 'LBLA': 'lbla', 'DHH': 'dhh', 'DHHS': 'dhhs',
        };

        final String nombreArchivo = mapeoArchivosJson[_versionSeleccionada] ?? 'rv1960';
        
        // Abrimos el JSON real de tus carpetas assets
        final String contenidoJsonCrudo = await rootBundle.loadString('assets/biblias/$nombreArchivo.json');
        final Map<String, dynamic> objetoBiblia = jsonDecode(contenidoJsonCrudo);
        final List<dynamic> librosJson = objetoBiblia['books'] ?? [];

        if (librosJson.length >= _libroSeleccionado) {
          final Map<String, dynamic> libroMap = librosJson[_libroSeleccionado - 1];
          final List<dynamic> capitulosJson = libroMap['chapters'] ?? [];

          if (capitulosJson.length >= _capituloSeleccionado) {
            final Map<String, dynamic> capituloMap = capitulosJson[_capituloSeleccionado - 1];
            final List<dynamic> itemsVersiculos = capituloMap['items'] ?? [];
            
            List<Map<String, dynamic>> textosOfflineJson = [];

            for (var item in itemsVersiculos) {
              if (item['type'] == 'verse') {
                final List<dynamic> numerosVerso = item['verse_numbers'] ?? [];
                final List<dynamic> lineasTexto = item['lines'] ?? [];

                if (numerosVerso.isNotEmpty && lineasTexto.isNotEmpty) {
                  textosOfflineJson.add({
                    'versiculo': numerosVerso.first as int,
                    'texto': lineasTexto.first.toString().trim(),
                  });
                }
              }
            }
            datos = textosOfflineJson; // Asignamos los datos del JSON local
          }
        }
      } catch (e) {
        print('Error en lectura de archivos JSON físicos: $e');
      }
    }

    // 4. Renderizamos los datos finales obtenidos en la pantalla
    if (mounted) {
      setState(() { 
        _versiculos = datos; 
        _cargando = false; 
      });
      _guardarPuntoDeLecturaActual();
    }

    // Consulta aislada de enlaces si hay red disponible
    try {
      // 🚀 SOLUCIÓN: Declaramos explícitamente que la respuesta es un Set de enteros <int>
      final Set<int> vinculos = await _dbHelper.obtenerVersiculosConReferenciasEnCapitulo(_libroSeleccionado, _capituloSeleccionado);
      if (mounted) {
        setState(() {
          _versiculosConReferenciasCargados.clear();
          _versiculosConReferenciasCargados.addAll(vinculos); // ¡Ahora el compilador lo acepta al 100%!
        });
      }
    } catch (_) {}
  }

  void _alternarResaltadoVersiculo(int versiculo, int colorHex) async {
    final llave = '${_versionSeleccionada}_${_libroSeleccionado}_${_capituloSeleccionado}_$versiculo';
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      if (_resaltadosLocales.containsKey(llave) && _resaltadosLocales[llave] == colorHex) {
        _resaltadosLocales.remove(llave); 
      } else {
        _resaltadosLocales[llave] = colorHex; 
      }
    });

    await prefs.setString('biblioteca_resaltados', jsonEncode(_resaltadosLocales));
  }

  @override
  Widget build(BuildContext context) {
    String nombreLibro = _dbHelper.obtenerNombreLibro(_libroSeleccionado);
    
    final bool esOscuro = _ajustesGlobales.modoOscuroLectura;
    final Color colorFondoPantalla = esOscuro ? const Color(0xFF121212) : const Color(0xFFFDFBF7);
    final Color colorTextoBiblico = esOscuro ? const Color(0xFFE0E0E0) : const Color(0xFF1A1A1A);
    final Color colorAppBarFondo = esOscuro ? const Color(0xFF1E1E1E) : Colors.white;
    final Color colorAppBarTexto = esOscuro ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: colorFondoPantalla,
      appBar: AppBar(
        backgroundColor: colorAppBarFondo,
        foregroundColor: colorAppBarTexto,
        elevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nombreLibro, 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: colorAppBarTexto)
            ),
            Text(
              'Capítulo $_capituloSeleccionado', 
              style: const TextStyle(fontSize: 13, color: Colors.grey)
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              esOscuro ? Icons.wb_sunny : Icons.nightlight_round,
              color: esOscuro ? Colors.amber : Colors.blueGrey,
            ),
            tooltip: esOscuro ? 'Cambiar a Modo Claro' : 'Cambiar a Modo Oscuro',
            onPressed: () {
              _ajustesGlobales.cambiarModoOscuroLectura(!esOscuro);
            },
          ),
          
          IconButton(
            icon: Icon(
              _modoSeleccionMultiple ? Icons.playlist_add_check : Icons.playlist_add,
              color: _modoSeleccionMultiple ? Colors.green : Colors.blueGrey,
              size: 26,
            ),
            tooltip: 'Activar Selección Múltiple',
            onPressed: () {
              setState(() {
                _modoSeleccionMultiple = !_modoSeleccionMultiple;
                if (!_modoSeleccionMultiple) {
                  _versiculosSeleccionados.clear();
                }
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_modoSeleccionMultiple 
                    ? '📥 Modo Selección Múltiple Activo. Toca los versículos.' 
                    : 'Modo Selección Múltiple Desactivado.'),
                  duration: const Duration(seconds: 2),
                )
              );
            },
          ),
          
          DropdownButton<String>(
            value: _versionSeleccionada,
            dropdownColor: colorAppBarFondo, 
            underline: const SizedBox(),
            iconEnabledColor: esOscuro ? Colors.white : Colors.black87, 
            style: TextStyle(
              color: esOscuro ? Colors.white : Colors.black87, 
              fontSize: 16, 
              fontWeight: FontWeight.w500
            ),
            items: const [
              DropdownMenuItem(value: 'RV1960', child: Text('RV1960 ')),
              DropdownMenuItem(value: 'NVI', child: Text('NVI ')),
              DropdownMenuItem(value: 'DHH', child: Text('DHH ')),
              DropdownMenuItem(value: 'DHHS', child: Text('DHHS ')),
              DropdownMenuItem(value: 'LBLA', child: Text('LBLA ')),
              DropdownMenuItem(value: 'NBLA', child: Text('NBLA ')),
              DropdownMenuItem(value: 'NTV', child: Text('NTV ')),
              DropdownMenuItem(value: 'RVA2015', child: Text('RVA2015 ')),
              DropdownMenuItem(value: 'RVC', child: Text('RVC ')),
              DropdownMenuItem(value: 'TLA', child: Text('TLA ')),
              DropdownMenuItem(value: 'TLAI', child: Text('TLAI ')),
              DropdownMenuItem(value: 'NVIC', child: Text('NVIC ')),
            ],
            onChanged: (nuevaVersion) {
              if (nuevaVersion != null) {
                setState(() => _versionSeleccionada = nuevaVersion);
                _cargarResaltadosYTexto();
              }
            },
          ),
        ],
      ),
      
      // Botones flotantes inferiores dinámicos (Aparecen solo en selección múltiple)
      floatingActionButton: _modoSeleccionMultiple && _versiculosSeleccionados.isNotEmpty
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 🚀 NUEVO BOTÓN FLOTANTE: Compartir Bloque Completo en Redes/Mensajería
                FloatingActionButton(
                  heroTag: 'btn_compartir_lote',
                  backgroundColor: Colors.teal,
                  child: const Icon(Icons.share, color: Colors.white),
                  onPressed: () {
                    final String nombreLibro = _dbHelper.obtenerNombreLibro(_libroSeleccionado);
                    final List<int> listaOrdenada = _versiculosSeleccionados.toList()..sort();
                    
                    StringBuffer textoCompletoBloque = StringBuffer();
                    
                    // Extraemos y concatenamos los textos de cada versículo seleccionado
                    for (int numV in listaOrdenada) {
                      final vData = _versiculos.firstWhere((element) => element['versiculo'] == numV);
                      textoCompletoBloque.write('[$numV] ${vData['texto']}\n');
                    }

                    final int primerVerso = listaOrdenada.first;
                    final int ultimoVerso = listaOrdenada.last;
                    final String citaRango = primerVerso == ultimoVerso 
                        ? '$nombreLibro $_capituloSeleccionado:$primerVerso'
                        : '$nombreLibro $_capituloSeleccionado:$primerVerso-$ultimoVerso';

                    final String mensajeFinal = '$textoCompletoBloque— $citaRango ($_versionSeleccionada)';
                    
                    Share.share(mensajeFinal); // Comparte la cadena completa estructurada
                    setState(() { _versiculosSeleccionados.clear(); _modoSeleccionMultiple = false; });
                  },
                ),
                
                const SizedBox(width: 12),
                
                // 🚀 NUEVO BOTÓN FLOANTE: Enviar Rango de Bloque al Sermón
                FloatingActionButton.extended(
                  heroTag: 'btn_enviar_sermon_lote',
                  backgroundColor: const Color(0xFF1A73E8), // Azul institucional
                  icon: const Icon(Icons.send_and_archive, color: Colors.white),
                  label: const Text(
                    'Insertar en Sermón', 
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                  ),
                  onPressed: () {
                    final String nombreLibro = _dbHelper.obtenerNombreLibro(_libroSeleccionado);                 
                    // Ordenamos matemáticamente el Set de versículos de menor a mayor
                    final List<int> listaOrdenada = _versiculosSeleccionados.toList()..sort();
                    final int primerVerso = listaOrdenada.first;
                    final int ultimoVerso = listaOrdenada.last;
                    
                    String citaRango = '';
                    if (primerVerso == ultimoVerso) {
                      citaRango = '$nombreLibro $_capituloSeleccionado:$primerVerso';
                    } else {
                      citaRango = '$nombreLibro $_capituloSeleccionado:$primerVerso-$ultimoVerso';
                    }
                    // Transmitimos el rango al canal. El editor recibirá el puntero y tu Lector Contextual
                    // del panel derecho reaccionará abriendo el capítulo completo al procesar la primera cifra.
                    CanalEventos().enviarCitaAlEditor(citaRango);

                    // Limpiamos los estados de selección múltiple tras el envío
                    setState(() {
                      _versiculosSeleccionados.clear();
                      _modoSeleccionMultiple = false;
                    });
                  },
                ),
                
                const SizedBox(width: 12), // Espaciador limpio entre botones 

                // Tu botón original de pintar (Le añadimos una heroTag única para evitar errores de navegación en Flutter)
                FloatingActionButton.extended(
                  heroTag: 'btn_pintar_lote',
                  backgroundColor: Colors.green,
                  icon: const Icon(Icons.color_lens, color: Colors.white),
                  label: Text(
                    'Pintar (${_versiculosSeleccionados.length})', 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                  ),
                  onPressed: _mostrarPaletaColoresMultiple,
                ),
              ],
            )
            
            // 🚀 NUEVO FLOATING ACTION BUTTON: Aparece si el pastor saltó mediante un enlace 🔗
          : _historialNavegacionRegreso.isNotEmpty 
              ? FloatingActionButton.extended(
                  heroTag: 'btn_regresar_historial_biblia',
                  backgroundColor: Colors.blueGrey.shade800,
                  icon: const Icon(Icons.arrow_circle_left_outlined, color: Colors.white),
                  label: const Text('Volver a la lectura anterior', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    // Extraemos el último punto del historial (Lógica LIFO - Pila)
                    final ultimoPunto = _historialNavegacionRegreso.removeLast();
                    
                    setState(() {
                      _libroSeleccionado = ultimoPunto['libro']!;
                      _capituloSeleccionado = ultimoPunto['capitulo']!;
                    });
                    _cargarResaltadosYTexto(); // Lo regresa al pasaje original
                  },
                )
              : null,
          
      body: Column(
        children: [
          _construirBarraNavegacionRapida(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                    itemCount: _versiculos.length,
                    itemBuilder: (context, index) {
                      final v = _versiculos[index];
                      final numVerso = v['versiculo'] ?? 1;
                      final llaveResaltado = '${_versionSeleccionada}_${_libroSeleccionado}_${_capituloSeleccionado}_$numVerso';
                      final int? colorHex = _resaltadosLocales[llaveResaltado];
                      final bool estaEnSeleccionTemporal = _versiculosSeleccionados.contains(numVerso);
                      
                      // 🚀 NUEVO: Evalúa si este versículo específico tiene enlaces mapeados
                      final bool tieneReferencia = _versiculosConReferenciasCargados.contains(numVerso);

                      return GestureDetector(
                        // ... Tu onTap existente de selección múltiple e individual
                        onTap: () {
                          if (_modoSeleccionMultiple) {
                            setState(() {
                              if (estaEnSeleccionTemporal) {
                                _versiculosSeleccionados.remove(numVerso);
                              } else {
                                _versiculosSeleccionados.add(numVerso);
                              }
                            });
                            } else {
                              _mostrarPaletaColoresIndividual(numVerso);
                            }
                          },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 🚀 NUEVO: Si tiene conector, muestra el eslabón interactivo antes del número
                              if (tieneReferencia && !_modoSeleccionMultiple)
                                const Padding(
                                    padding: EdgeInsets.only(right: 6.0, top: 3.0),
                                    child: Icon(Icons.link, size: 16, color: Colors.blue),
                                  ),
                                Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(fontSize: 18, color: colorTextoBiblico, height: 1.5, fontFamily: 'serif'),
                                    children: [
                                      TextSpan(
                                        text: '$numVerso ', 
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A73E8), fontSize: 15)
                                      ),
                                      TextSpan(
                                        text: v['texto'] ?? '',
                                        style: TextStyle(
                                          backgroundColor: estaEnSeleccionTemporal
                                              ? Colors.blue.withOpacity(0.25) 
                                              : (colorHex != null ? Color(colorHex).withOpacity(0.35) : Colors.transparent),
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
                    },
                  ),
          ),
          
          // Barra de información inferior persistente
          Container(
            width: double.infinity,
            color: const Color(0xFF1A73E8),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
              'Leyendo: $nombreLibro Capítulo $_capituloSeleccionado — Versión $_versionSeleccionada',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // MODO INDIVIDUAL: Pinta un solo texto
  void _mostrarPaletaColoresIndividual(int versiculo) {
    _mostrarPaletaBase(
      'Sombrear versículo $versiculo:', 
      (colorValue) {
        _alternarResaltadoVersiculo(versiculo, colorValue);
        Navigator.pop(context); 
      },
      () {
        _alternarResaltadoVersiculo(versiculo, 0); 
        Navigator.pop(context); 
      },
      versiculoIndividual: versiculo, // 🚀 PASAMOS EL ID DEL VERSO AL CONSTRUCTOR
    );
  }

  // 🚀 MODO MULTIPLE: Pinta todos los versículos seleccionados al mismo tiempo
  void _mostrarPaletaColoresMultiple() {
    _mostrarPaletaBase(
      'Selecciona un color para el bloque marcado:', 
      (colorValue) {
        // Recorremos el bloque seleccionado y aplicamos el color a cada uno
        for (var verso in _versiculosSeleccionados) {
          _alternarResaltadoVersiculoEnLote(verso, colorValue);
        }
        setState(() {
          _versiculosSeleccionados.clear(); // Limpiamos la selección
          _modoSeleccionMultiple = false;   // Desactivamos el modo
        });
        Navigator.pop(context); // Cierra la paleta de bloque
        _guardarResaltadosEnDisco(); // Guarda la biblioteca de forma permanente
      },
      () {
        for (var verso in _versiculosSeleccionados) {
          _alternarResaltadoVersiculoEnLote(verso, 0); // Borra el sombreado en bloque
        }
        setState(() { _versiculosSeleccionados.clear(); _modoSeleccionMultiple = false; });
        Navigator.pop(context);
        _guardarResaltadosEnDisco();
      },
    );
  }

  // MÉTODO BASE: Eleva la paleta sobre los botones de Android de forma limpia
  void _mostrarPaletaBase(String titulo, Function(int) onColorElegido, VoidCallback onLimpiar, {int? versiculoIndividual}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      barrierColor: Colors.transparent, // Permite seguir tocando el texto de atrás
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 8),
          child: Container(
            padding: const EdgeInsets.all(16),
            // Ajustamos la altura si viene con el panel de referencias cruzadas activo
            height: versiculoIndividual != null ? 210 : 125,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // 🚀 NUEVO BOTÓN: Enviar Cita al Editor de Sermones (Aparece si viene de Modo Individual)
                    if (versiculoIndividual != null)...[
                      IconButton(
                        icon: const Icon(Icons.rate_review_outlined, color: Color(0xFF1A73E8), size: 28),
                        tooltip: 'Enviar cita al sermón',
                        onPressed: () {
                        //   // 1. Obtenemos el nombre del libro de forma limpia
                           final String nombreLibro = _dbHelper.obtenerNombreLibro(_libroSeleccionado);
                          
                        //   // 2. Estructuramos el string de la cita exacta: "1 Corintios 14:3"
                           final String citaFormateada = '$nombreLibro $_capituloSeleccionado:$versiculoIndividual';
                          
                        //   // 3. Emitimos la señal de radio al editor por el Canal Global
                           CanalEventos().enviarCitaAlEditor(citaFormateada);
                          
                        //   // 4. Cerramos el menú contextual automáticamente
                           Navigator.pop(context);
                         },
                      ),

                      // 🚀 NUEVO BOTÓN: Compartir Versículo Individual
                      IconButton(
                        icon: const Icon(Icons.share, color: Colors.teal, size: 28),
                        tooltip: 'Compartir pasaje',
                        onPressed: () {
                          final String nombreLibro = _dbHelper.obtenerNombreLibro(_libroSeleccionado);
                          // Buscamos el texto del versículo actual en la lista local
                          final vData = _versiculos.firstWhere((element) => element['versiculo'] == versiculoIndividual);
                          final String textoVerso = vData['texto'] ?? '';

                          final String mensajeACompartir = '"$textoVerso" — $nombreLibro $_capituloSeleccionado:$versiculoIndividual ($_versionSeleccionada)';
                          
                          // Disparamos la hoja de compartir nativa de Android/iOS/Web
                          Share.share(mensajeACompartir);
                          Navigator.pop(context);
                        },
                      ),

                      // 🚀 BOTÓN DE COMPARAR TRADUCCIONES CORREGIDO
                      IconButton(
                        icon: const Icon(Icons.compare, color: Colors.indigo, size: 28),
                        tooltip: 'Comparar traducciones',
                        onPressed: () {
                          Navigator.pop(context); // Cierra la paleta de colores
                          
                          // 🚀 SEGURO: Le pasamos la variable que la paleta recibió en su declaración
                          _mostrarDialogoComparativaVersiones(versiculoIndividual);
                        },
                      ),
                    ],                        
                    _circuloPaleta(Colors.yellow.value, onColorElegido),
                    _circuloPaleta(Colors.green.value, onColorElegido),
                    _circuloPaleta(Colors.blue.value, onColorElegido),
                    _circuloPaleta(Colors.pink.value, onColorElegido),
                    IconButton(icon: const Icon(Icons.layers_clear, color: Colors.red), onPressed: onLimpiar)
                  ],
                ),
                // 🚀 EFECTO DOMINÓ DESDE EL FUTUREBUILDER INTEGRADO PERFECTAMENTE
                if (versiculoIndividual != null) ...[
                  const Divider(height: 20),
                  const Text('🔗 Pasajes Relacionados (Efecto Dominó):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blueGrey)
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _dbHelper.obtenerReferenciasCruzadas(
                        _libroSeleccionado, 
                        _capituloSeleccionado, 
                        versiculoIndividual),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: SizedBox(width: 20, height: 20, 
                            child: CircularProgressIndicator(strokeWidth: 2)
                            )
                            );
                          }
                          final referencias = snapshot.data ?? [];
                          if (referencias.isEmpty) {
                            return const Text('No se encontraron citas marginales.', style: TextStyle(fontSize: 12, color: 
                            Colors.grey, fontStyle: FontStyle.italic));
                          }
                        return ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: referencias.length,
                          itemBuilder: (context, idx) {
                            final Map<String, dynamic> ref = referencias[idx];
                            final String nombreDestino = ref['libros']['nombre'] ?? 'Libro';
                            final int capDestino = ref['destino_capitulo'] as int;
                            final int verDestino = ref['destino_versiculo'] as int;
                            final String citaCompleta = '$nombreDestino $capDestino:$verDestino';
                          
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0, bottom: 4.0),
                            child: ActionChip(
                              elevation: 0.5,
                              backgroundColor: Colors.blue.shade50,
                              label: Text(citaCompleta, style: const TextStyle(color: Colors.blue, 
                              fontWeight: FontWeight.bold, fontSize: 13)),
                            onPressed: () {
                              Navigator.pop(context); // Cierra la paleta
                            // Almacenamos el rastro en la pila para el botón Volver
                            _histOriginalRegresoAlSaltar();
                            
                            setState(() {
                              _libroSeleccionado = ref['destino_libro_id'] as int;
                              _capituloSeleccionado = capDestino;});
                              
                            _cargarResaltadosYTexto();
                            },
                            ),
                          );
                          },
                        );
                        },
                    ),
                  ),
                ]
              ],
            ),
          ),
        );
      },
    );
  }
  // Método modular para guardar el rastro de lectura antes del salto
  void _histOriginalRegresoAlSaltar() {
    _historialNavegacionRegreso.add({
      'libro': _libroSeleccionado,
     'capitulo': _capituloSeleccionado,
    });
  }  

  Widget _circuloPaleta(int colorValue, Function(int) onTap) {
    return InkWell(
      onTap: () => onTap(colorValue),
      child: CircleAvatar(backgroundColor: Color(colorValue), radius: 16),
    );
  }

  // Métodos de persistencia optimizados para lotes masivos
  void _alternarResaltadoVersiculoEnLote(int versiculo, int colorHex) {
    final llave = '${_versionSeleccionada}_${_libroSeleccionado}_${_capituloSeleccionado}_$versiculo';
    if (colorHex == 0) {
      _resaltadosLocales.remove(llave);
    } else {
      _resaltadosLocales[llave] = colorHex;
    }
  }

  void _guardarResaltadosEnDisco() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('biblioteca_resaltados', jsonEncode(_resaltadosLocales));
    setState(() {}); // Fuerza el redibujo final
  }

  Widget _construirBarraNavegacionRapida() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: _capituloSeleccionado > 1 
                ? () { setState(() => _capituloSeleccionado--); _cargarResaltadosYTexto(); }
                : null,
          ),
          TextButton.icon(
            onPressed: _mostrarSelectorLibroYCapitulo,
            icon: const Icon(Icons.unfold_more, size: 16),
            label: Text(_dbHelper.obtenerNombreLibro(_libroSeleccionado), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 18),
            onPressed: () { 
            setState(() => _capituloSeleccionado++); 
            _cargarResaltadosYTexto(); // <-- CORRECCIÓN: Nombre de método correcto
            },
          ),
        ],
      ),
    );
  }

  // Cuadro de diálogo modal rápido para saltar directo a cualquier libro de la Biblia
    void _mostrarSelectorLibroYCapitulo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permite expandir el menú para ver cómodamente los libros
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8, // Ocupa el 80% de la pantalla
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selecciona un Libro de la Biblia',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A73E8)),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: 66, // Los 66 libros del canon
                  itemBuilder: (context, index) {
                    final int libroId = index + 1;
                    final String nombreLibro = _dbHelper.obtenerNombreLibro(libroId);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        child: Text('$libroId', style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(nombreLibro, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      onTap: () {
                        Navigator.pop(context); // Cierra la lista de libros
                        _mostrarSelectorCapitulosDialog(libroId, nombreLibro); // Abre el selector de capítulos
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // MÉTODO AUXILIAR: Muestra un diálogo rápido para elegir el capítulo del libro seleccionado
  // CORRECCIÓN DEFINITIVA: Despliega una cuadrícula con los capítulos reales del libro
  void _mostrarSelectorCapitulosDialog(int libroId, String nombreLibro) {
    // Consultamos al helper cuántos capítulos tiene este libro de forma matemática exacta
    final int maxCapitulos = _dbHelper.obtenerTotalCapitulos(libroId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6, // Ocupa el 60% de la pantalla
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Capítulos disponibles de $nombreLibro',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
              const Text('Selecciona el número que deseas estudiar:', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const Divider(),
              Expanded(
                // GridView: Dibuja una rejilla estética de botones numéricos
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5, // 5 botones por fila en el celular
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: maxCapitulos,
                  itemBuilder: (context, index) {
                    final int capNum = index + 1;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _libroSeleccionado = libroId;
                          _capituloSeleccionado = capNum;
                        });
                        _cargarResaltadosYTexto();
                        Navigator.pop(context); // Cierra la rejilla de capítulos
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Center(
                          child: Text(
                            '$capNum',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}    