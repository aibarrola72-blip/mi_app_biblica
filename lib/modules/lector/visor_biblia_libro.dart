// lib/modules/lector/visor_biblia_libro.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/biblia_db_helper.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../database/ajustes_config.dart';
import '../../database/canal_eventos.dart'; 
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; 

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
  // final AjustesConfig _ajustesGlobales = AjustesConfig();
  late final AjustesConfig _ajustesGlobales;

  @override
  void initState() {
    super.initState();
    _ajustesGlobales = AjustesConfig();
    _ajustesGlobales.cargarAjustes();
    _ajustesGlobales.addListener(() { if (mounted) setState(() {}); });
    // if (_ajustesGlobales.modoOscuroLectura) { 
    //       WakelockPlus.enable();
    //     } else {
    //       WakelockPlus.disable();
    //     }
    WakelockPlus.enable(); 
    _recuperarUltimoProgresoYTexto(); 
  }

  @override
  void dispose() {
    // 3. 🚀 LIBERA EL CONTROL DE LA PANTALLA AL SALIR PARA QUE EL CELULAR VUELVA A SU ESTADO NORMAL
    WakelockPlus.disable(); 
    super.dispose();
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
          
          IconButton(
            icon: const Icon(Icons.text_fields_rounded, size: 20),
            tooltip: 'Disminuir tamaño de letra',
            onPressed: () {
              if (_ajustesGlobales.tamanoLetra > 14.0) {
                // Restamos 2 puntos a la fuente y guardamos el estado de forma permanente
                _ajustesGlobales.guardarTamanoLetra(_ajustesGlobales.tamanoLetra - 2.0);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.text_fields_rounded, size: 26),
            tooltip: 'Aumentar tamaño de letra',
            onPressed: () {
              if (_ajustesGlobales.tamanoLetra < 30.0) {
                // Sumamos 2 puntos a la fuente y guardamos el estado de forma permanente
                _ajustesGlobales.guardarTamanoLetra(_ajustesGlobales.tamanoLetra + 2.0);
              }
            },
          ),

          // Añade esto en las 'actions: []' de tu AppBar en visor_biblia_libro.dart
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 24),
            tooltip: 'Buscar palabra clave',
            onPressed: _mostrarBuscadorGlobalFlotante, // Llamará a la interfaz que crearemos abajo
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 6.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              decoration: BoxDecoration(
                color: esOscuro ? Colors.grey.shade900 : const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: esOscuro ? Colors.grey.shade800 : Colors.black12,
                  width: 1,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _versionSeleccionada,
                  dropdownColor: colorAppBarFondo, 
                  iconEnabledColor: esOscuro ? Colors.blue.shade300 : Colors.blue.shade700, 
                  style: TextStyle(
                    color: esOscuro ? Colors.white : Colors.black87, 
                    fontSize: 15, 
                    fontWeight: FontWeight.bold
                  ),
                  // 🚀 ÍCONOS INTEGRADOS EN CADA TRADUCCIÓN:
                  items: [
                    _construirItemConIcono('RV1960', esOscuro),
                    _construirItemConIcono('NVI', esOscuro),
                    _construirItemConIcono('DHH', esOscuro),
                    _construirItemConIcono('DHHS', esOscuro),
                    _construirItemConIcono('LBLA', esOscuro),
                    _construirItemConIcono('NBLA', esOscuro),
                    _construirItemConIcono('NTV', esOscuro),
                    _construirItemConIcono('RVA2015', esOscuro),
                    _construirItemConIcono('RVC', esOscuro),
                    _construirItemConIcono('TLA', esOscuro),
                    _construirItemConIcono('TLAI', esOscuro),
                    _construirItemConIcono('NVIC', esOscuro),
                  ],
                  onChanged: (nuevaVersion) {
                    if (nuevaVersion != null) {
                      setState(() => _versionSeleccionada = nuevaVersion);
                      _cargarResaltadosYTexto();
                    }
                  },
                ),
              ),
            ),
          ),

        ],
      ),
      
      // Botones flotantes inferiores dinámicos (Aparecen solo en selección múltiple)
      bottomNavigationBar: _modoSeleccionMultiple && _versiculosSeleccionados.isNotEmpty
          ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(color: colorAppBarFondo,
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],),
            child: SafeArea(
              child: Wrap(
                spacing: 10.0,runSpacing: 10.0,alignment: WrapAlignment.spaceEvenly,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [Text('${_versiculosSeleccionados.length} marcados',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorAppBarTexto, fontSize: 14),),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, 
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  icon: const Icon(Icons.share, size: 18),label: const Text('Compartir', 
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),onPressed: () {
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
                
                ElevatedButton.icon(style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8), 
                  foregroundColor: Colors.white, 
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  icon: const Icon(Icons.send_and_archive, size: 18),
                  label: const Text('Insertar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
                
                ElevatedButton.icon(style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, 
                  foregroundColor: Colors.white, 
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  icon: const Icon(Icons.color_lens, size: 18),
                  label: const Text('Pintar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  onPressed: _mostrarPaletaColoresMultiple,
                ),
              ],
            ),
          ),
          )
          :null,
            
            // 🚀 NUEVO FLOATING ACTION BUTTON: Aparece si el pastor saltó mediante un enlace 🔗
          floatingActionButton: !_modoSeleccionMultiple && _historialNavegacionRegreso.isNotEmpty ? FloatingActionButton.extended(
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
                    // 🚀 MEJORA DE ACOPLAMIENTO: Colchón elástico inferior para liberar el último
                    itemCount: _versiculos.length+1,
                    itemBuilder: (context, index) {
                      if (index == _versiculos.length) {
                        return const SizedBox(height: 80); // Colchón elástico inferior
                      }
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
                                    style: TextStyle(fontSize: _ajustesGlobales.tamanoLetra, 
                                    color: colorTextoBiblico, 
                                    height: 1.45 + ((_ajustesGlobales.tamanoLetra - 14.0) * 0.0125), 
                                    fontFamily: _ajustesGlobales.tipoLetra == 'monospace' 
                                            ? 'monospace' 
                                            : (_ajustesGlobales.tipoLetra == 'serif' ? 'serif' : 'sans-serif'),
                                      ),
                                    children: [
                                      TextSpan(
                                        text: '$numVerso ', 
                                        style: TextStyle(fontWeight: FontWeight.bold, 
                                        color: Color(0xFF1A73E8), fontSize: _ajustesGlobales.tamanoLetra -3)
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

  void _mostrarBuscadorGlobalFlotante() {
    final TextEditingController controladorBusqueda = TextEditingController();
    List<Map<String, dynamic>> resultadosLocales = [];
    bool buscando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permite expandirse de forma cómoda con el teclado en pantalla
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder( // Permite refrescar de forma aislada la lista de resultados sin redibujar toda la Biblia de fondo
          builder: (BuildContext context, StateSetter modalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75, // Ocupa el 75% de la pantalla
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Buscador Global Concordancia',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 12),
                  
                  // Campo de Texto Estilizado con botón de disparo
                  // Reemplaza el TextField dentro de '_mostrarBuscadorGlobalFlotante' por este bloque:
                  TextField(
                    controller: controladorBusqueda,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    // 🚀 ESCUCHADOR EN TIEMPO REAL: Fuerza al modal a redibujarse para alternar los íconos de borrar/enviar
                    onChanged: (texto) {
                      modalState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'Ej: "Espíritu Santo", "gracia", "fe"...',
                      prefixIcon: const Icon(Icons.search),
                      // 🚀 SÚFIX ICON ADAPTATIVO:
                      suffixIcon: controladorBusqueda.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                              onPressed: () {
                                controladorBusqueda.clear(); // Vacía el controlador de texto
                                modalState(() {
                                  resultadosLocales.clear(); // Limpia los resultados de la pantalla
                                });
                              },
                            )
                          : IconButton(
                              icon: const Icon(Icons.arrow_circle_right_rounded, color: Color(0xFF1A73E8), size: 28),
                              onPressed: () async {
                                if (controladorBusqueda.text.trim().isEmpty) return;
                                modalState(() => buscando = true);
                                final datos = await _dbHelper.buscarPalabraClaveGlobal(controladorBusqueda.text);
                                modalState(() {
                                  resultadosLocales = datos;
                                  buscando = false;
                                });
                              },
                            ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onSubmitted: (val) async {
                      if (val.trim().isEmpty) return;
                      modalState(() => buscando = true);
                      final datos = await _dbHelper.buscarPalabraClaveGlobal(val);
                      modalState(() { resultadosLocales = datos; buscando = false; });
                    },
                  ),

                  const SizedBox(height: 10),
                  
                  // Lista de Resultados Dinámica
                  Expanded(
                    child: buscando
                        ? const Center(child: CircularProgressIndicator())
                        : resultadosLocales.isEmpty
                            ? const Center(
                                child: Text(
                                  'Ingresa una palabra para buscar en toda la Biblia.',
                                  style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                                ),
                              )
                            : // Reemplaza el ListView.builder dentro de '_mostrarBuscadorGlobalFlotante' por este bloque:
                              ListView.builder(
                                itemCount: resultadosLocales.length,
                                itemBuilder: (context, index) {
                                  final res = resultadosLocales[index];
                                  final int libroId = res['libro_id'];
                                  final int capNum = res['capitulo'];
                                  final int verNum = res['versiculo'];
                                  final String textoVerso = res['texto'] ?? '';
                                  final String nombreLibro = _dbHelper.obtenerNombreLibro(libroId);
                                  
                                  // Obtenemos el término crudo que escribió el usuario para segmentar el texto
                                  final String terminoBuscado = controladorBusqueda.text.trim();

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                    title: Padding(
                                      padding: const EdgeInsets.only(bottom: 4.0),
                                      child: Text(
                                        '$nombreLibro $capNum:$verNum',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold, 
                                          color: Color(0xFF1A73E8), 
                                          fontSize: 13, 
                                          fontFamily: 'sans-serif'
                                        ),
                                      ),
                                    ),
                                    subtitle: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                          color: Colors.black87, 
                                          fontSize: 14, 
                                          fontFamily: 'serif', 
                                          height: 1.4
                                        ),
                                        // 🚀 LLAMADA AL MOTOR DE RESALTADO DINÁMICO INSENSIBLE:
                                        children: _crearFragmentosResaltados(textoVerso, terminoBuscado),
                                      ),
                                    ),
                                    shape: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _histOriginalRegresoAlSaltar();
                                      setState(() {
                                        _libroSeleccionado = libroId;
                                        _capituloSeleccionado = capNum;
                                      });
                                      _cargarResaltadosYTexto();
                                    },
                                  );
                                },
                              )
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  List<TextSpan> _crearFragmentosResaltados(String textoOriginal, String terminoBusqueda) {
  if (terminoBusqueda.isEmpty) return [TextSpan(text: textoOriginal)];

  // Función helper interna para mapear letras a sus variantes con tildes en RegExp
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

    // Recorremos todas las coincidencias encontradas por la RegExp en el versículo
    for (final Match match in regex.allMatches(textoOriginal)) {
      // 1. Añadimos el texto previo que no coincide
      if (match.start > indiceActual) {
        fragmentos.add(TextSpan(text: textoOriginal.substring(indiceActual, match.start)));
      }
      
      // 2. Añadimos el término exacto encontrado con fondo amarillo fosforescente
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

    // 3. Añadimos el remanente del versículo si quedó algo
    if (indiceActual < textoOriginal.length) {
      fragmentos.add(TextSpan(text: textoOriginal.substring(indiceActual)));
    }

    return fragmentos;
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
  DropdownMenuItem<String> _construirItemConIcono(String version, bool modoOscuro) {
    return DropdownMenuItem<String>(
      value: version,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.book_rounded, 
            size: 16, 
            color: modoOscuro ? Colors.blue.shade300 : Colors.blue.shade700
          ),
          const SizedBox(width: 8),
          Text(version),
        ],
      ),
    );
  }

}    