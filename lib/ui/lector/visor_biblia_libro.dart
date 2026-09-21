// lib/modules/lector/visor_biblia_libro.dart
import 'dart:async'; 
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mi_app_biblica/data/biblia_db_helper.dart';

import 'package:mi_app_biblica/data/ajustes_config.dart';
import 'package:mi_app_biblica/core/canal_eventos.dart'; 
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
   final List<int> _versiculosSeleccionados = [];
  
  List<Map<String, dynamic>> _versiculos = [];
  bool _cargando = true;
  Map<String, int> _resaltadosLocales = {};

  // 🚀 HISTORIAL: Guarda el rastro de lectura para poder regresar. Ej: [{'libro': 1, 'capitulo': 1}]
  final List<Map<String, int>> _historialNavegacionRegreso = [];
  
  // 🚀 CONECTORES: Almacena qué versículos del capítulo actual tienen enlaces para ponerles el ícono 🔗
  final Set<int> _versiculosConReferenciasCargados = {};
  
  bool _modoSeleccionMultiple = false;
  // final AjustesConfig _ajustesGlobales = AjustesConfig();
  late final AjustesConfig _ajustesGlobales;

  @override
  void initState() {
    super.initState();
    _ajustesGlobales = AjustesConfig();
    _ajustesGlobales.cargarAjustes();
    _ajustesGlobales.addListener(() { if (mounted) setState(() {}); });
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
      debugPrint('Aviso de guardado de progreso: $e');
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

    // 2. NIVEL HÍBRIDO (Supabase con caída automática a SQLite Local y JSON en isolate)
    List<Map<String, dynamic>> datos = [];
    try {
      datos = await _dbHelper.obtenerCapitulo(
        _libroSeleccionado,
        _capituloSeleccionado,
        versionId: _versionSeleccionada,
      );
    } catch (e) {
      debugPrint('Error al cargar el capítulo: $e');
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
    try {
      if (_versiculos.isNotEmpty) {
        _dbHelper.marcarCapituloComoLeido(
          libroId: _libroSeleccionado,
          capitulo: _capituloSeleccionado,
          totalVersiculos: _versiculos.length,
          soloRegistrarVisita: true, // 💡 Bandera lógica para que tu helper guarde en silencio sin mostrar SnackBars
        );
      }
    } catch (e) {
      debugPrint('Aviso en el registro automático de actividad: $e');
    }
  }

  // Método auxiliar matemático para agrupar citas correlativas
  String _formatearVersiculosCita(List<int> lista) {
    if (lista.isEmpty) return '';
    List<String> segmentos = [];
    int inicio = lista[0];
    int fin = lista[0];

    for (int i = 1; i < lista.length; i++) {
      if (lista[i] == fin + 1) {
        fin = lista[i];
      } else {
        if (inicio == fin) {
          segmentos.add('$inicio');
        } else {
          segmentos.add('$inicio-$fin');
        }
        inicio = lista[i];
        fin = lista[i];
      }
    }
    if (inicio == fin) {
      segmentos.add('$inicio');
    } else {
      segmentos.add('$inicio-$fin');
    }
    return segmentos.join(', ');
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
        leading: IconButton( 
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Regresar al inicio',
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        titleSpacing: 0,
        // 🚀 LIMPIEZA DE BARRA: Ahora la AppBar solo muestra el nombre del Libro estético y nítido
        title: 
            Text(
              nombreLibro, 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: colorAppBarTexto)
            ),            
        actions: [
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.58,
            child: SingleChildScrollView(scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),child: 
            Row(children: [
              IconButton(
                icon: Icon(
                  esOscuro ? Icons.wb_sunny : Icons.nightlight_round,
                  color: esOscuro ? Colors.amber : Colors.blueGrey,
                ),
                tooltip: esOscuro ? 'Modo Claro' : 'Modo Oscuro',
                onPressed: () {
                  _ajustesGlobales.cambiarModoOscuroLectura(!esOscuro);
                },
              ),
                        
              IconButton(
                icon: const Icon(Icons.text_fields_rounded),
                tooltip: 'Achicar letra',
                onPressed: () {
                  if (_ajustesGlobales.tamanoLetra > 14.0) {
                    // Restamos 2 puntos a la fuente y guardamos el estado de forma permanente
                    _ajustesGlobales.guardarTamanoLetra(_ajustesGlobales.tamanoLetra - 2.0);
                  }
                },
              ),

              IconButton(
                icon: const Icon(Icons.text_fields_rounded),
                tooltip: 'Agrandar letra',
                onPressed: () {
                  if (_ajustesGlobales.tamanoLetra < 30.0) {
                    // Sumamos 2 puntos a la fuente y guardamos el estado de forma permanente
                    _ajustesGlobales.guardarTamanoLetra(_ajustesGlobales.tamanoLetra + 2.0);
                  }
                },
              ),

          // Añade esto en las 'actions: []' de tu AppBar en visor_biblia_libro.dart
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Buscar palabra o frase en toda la Biblia',
                onPressed: _mostrarBuscadorGlobalFlotante, // Llamará a la interfaz que crearemos abajo
              ),

              IconButton(
                    icon: const Icon(Icons.history_rounded), // Ícono de reloj con sentido de retorno
                    tooltip: 'Ver historial de lecturas anteriores',
                    onPressed: _mostrarHistorialLecturaModal, // Despliega el panel de registros
                  ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 6.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              decoration: BoxDecoration(
                color: esOscuro ? Colors.grey.shade900 : const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: esOscuro ? Colors.grey.shade800 : Colors.black12,
                  width: 1,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton(
                  value: _versionSeleccionada,
                  dropdownColor: colorAppBarFondo, 
                  iconEnabledColor: esOscuro ? Colors.blue.shade300 : Colors.blue.shade700, 
                  style: TextStyle(
                    color: esOscuro ? Colors.white : Colors.black87, 
                    fontSize: 13, fontWeight: FontWeight.bold
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
    ),
          ),
        ],
      ),
      
      bottomNavigationBar: null,
        
            // 🚀 NUEVO FLOATING ACTION BUTTON: Aparece si el pastor saltó mediante un enlace 🔗
          floatingActionButton: !_modoSeleccionMultiple && _historialNavegacionRegreso.isNotEmpty 
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
                      _versiculosSeleccionados.clear(); // Restaura el foco visual del versículo
                     if (ultimoPunto['versiculo'] != null) {
                        _versiculosSeleccionados.add(ultimoPunto['versiculo']!);
                        _modoSeleccionMultiple = true;
                      }
                    });
                    _cargarResaltadosYTexto(); // Lo regresa al pasaje original
                  },
                )
              : null,
          
      body: Stack(
        children: [
          Column(
            children: [
            _construirBarraNavegacionRapida(),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                      // 🚀 MEJORA DE ACOPLAMIENTO: Colchón elástico inferior para liberar el último
                      itemCount: _versiculos.length+2,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                        return Padding(padding: const EdgeInsets.only(top: 10.0, bottom: 24.0),
                          child: Center(
                            child: Column(
                              children: [
                                Text('CAPÍTULO $_capituloSeleccionado',style: TextStyle(fontSize: _ajustesGlobales.tamanoLetra + 4, // Crece proporcionalmente según los ajustes
                                fontWeight: FontWeight.bold,letterSpacing: 2.0,color: const Color(0xFF1A73E8),fontFamily: 'sans-serif',),),
                                const SizedBox(height: 6),Container(width: 45,height: 2.5,color: Colors.blueGrey.withValues(alpha: 0.3),
                                ),
                              ],
                            ),
                          ),
                        );
                      }                     // Colchón elástico inferior
                  
                    // CASO 2: ÍTEM FINAL (Transformado en botón verificador de progreso devocional)
                    if (index == _versiculos.length + 1) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                        child: Column(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A73E8),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(50), // Botón amplio fácil de pulsar
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 1,
                              ),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 22),
                              label: const Text(
                                'Marcar capítulo como leído', 
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.3)
                              ),
                              onPressed: () async {
                                // Desplegar un micro-loader de red circular flotante
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => const Center(child: CircularProgressIndicator()),
                                );

                                // Despachamos el conteo exacto de versículos de este capítulo al helper
                                bool exito = await _dbHelper.marcarCapituloComoLeido(
                                  libroId: _libroSeleccionado,
                                  capitulo: _capituloSeleccionado,
                                  totalVersiculos: _versiculos.length,
                                );

                                if (context.mounted) {
                                  Navigator.pop(context); // Cierra el loader de red

                                  if (exito) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('🎉 ¡Progreso guardado! Su racha y estadísticas han sido actualizadas.'),
                                        backgroundColor: Colors.green,
                                        duration: Duration(seconds: 3),
                                      ),
                                    );
                                    
                                    // 🚀 MOTOR DE SALTO INTELIGENTE:
                                    setState(() {
                                      // Consulta cuántos capítulos tiene el libro actual en tu base de datos
                                      final int totalCapitulosDelLibro = _dbHelper.obtenerTotalCapitulos(_libroSeleccionado);

                                      if (_capituloSeleccionado < totalCapitulosDelLibro) {
                                        // Caso A: Aún quedan capítulos en este libro. Avanzamos al siguiente.
                                        _capituloSeleccionado++;
                                      } else {
                                        // Caso B: Llegamos al límite (ej: Salmo 150). Saltamos al siguiente libro.
                                        if (_libroSeleccionado < 66) { 
                                          _libroSeleccionado++;
                                          _capituloSeleccionado = 1; // Reinicia al capítulo 1 (ej: Proverbios 1)
                                        } else {
                                          // Caso C: Llegamos a Apocalipsis 22 (Fin de la Biblia). Reinicia al Génesis.
                                          _libroSeleccionado = 1; 
                                          _capituloSeleccionado = 1;
                                        }
                                      }
                                    });

                                    // Recargamos el contenido del nuevo capítulo/libro saltado
                                    _cargarResaltadosYTexto();
                                    
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('⚠️ No se pudo sincronizar en la nube. Se guardará localmente.'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                            const SizedBox(height: 60), // Mantiene el colchón elástico inferior para liberar la barra
                          ],
                        ),
                      );
                    }

                  // CASO 3: RENDERIZADO NORMAL DE VERSÍCULOS (Ajustamos el índice restando el desfase del título)
                      final v = _versiculos[index -1];
                      final numVerso = v['versiculo'] ?? v['num_versiculo'] ?? v['verse'] ?? index; // 👈 Blindaje definitivo
                      final llaveResaltado = '${_versionSeleccionada}_${_libroSeleccionado}_${_capituloSeleccionado}_$numVerso';
                      final int? colorHex = _resaltadosLocales[llaveResaltado];                                            
                      // 🚀 NUEVO: Evalúa si este versículo específico tiene enlaces mapeados
                      final bool tieneReferencia = _versiculosConReferenciasCargados.contains(numVerso);
                      // Validación directa contra la lista dinámica
                      final bool estaMarcadoActual = _versiculosSeleccionados.contains(numVerso);

                      return InkWell(
                        onTap: () {
                          setState(() {
                            // 1. Si no hay nada seleccionado, marcamos el inicio
                            if (estaMarcadoActual) {
                              _versiculosSeleccionados.remove(numVerso);
                            } else {
                              _versiculosSeleccionados.add(numVerso);
                            }
                            _modoSeleccionMultiple = _versiculosSeleccionados.isNotEmpty;
                          });
                        },
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,                        
                        child: Container(
                          color: Colors.transparent, 
                          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 🚀 Muestra el eslabón interactivo si tiene referencias y no hay selección activa
                              if (tieneReferencia && _versiculosSeleccionados.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6.0, top: 3.0),
                                  child: Icon(Icons.link, size: 16, color: Colors.blue),
                                ),
                              Expanded(
                                child: RichText(
                                      text: TextSpan(
                                        style: TextStyle(
                                          fontSize: _ajustesGlobales.tamanoLetra, 
                                          color: colorTextoBiblico, 
                                          height: 1.45 + ((_ajustesGlobales.tamanoLetra - 14.0) * 0.0125), 
                                          fontFamily: _ajustesGlobales.tipoLetra == 'monospace' 
                                              ? 'monospace' 
                                              : (_ajustesGlobales.tipoLetra == 'serif' ? 'serif' : 'sans-serif'),
                                        ),
                                        children: [
                                          TextSpan(
                                            text: '$numVerso ', 
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold, 
                                              color: const Color(0xFF1A73E8), 
                                              fontSize: _ajustesGlobales.tamanoLetra - 3,
                                            ),
                                          ),
                                          TextSpan(
                                            text: v['texto'] ?? '',
                                            style: TextStyle(
                                              // Prioridad al sombreado de selección azul fluido, si no, respeta el color pintado de la BD
                                              backgroundColor: estaMarcadoActual
                                                  ? Colors.blue.withValues(alpha: 0.25) 
                                                  : (colorHex != null ? Color(colorHex).withValues(alpha: 0.35) : Colors.transparent),
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
      
      // 🚀 NUEVA BARRA ESTILO TOOLBAR SUPERIOR (Aparece de forma flotante e idéntica a tus controles)
      if (_versiculosSeleccionados.isNotEmpty)
        Positioned(left: 14.0,right: 14.0,bottom: MediaQuery.of(context).
          padding.bottom + 45.0, // Posicionado justo arriba de la barra azul informativa
          child: Row(mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: MediaQuery.of(context).size.width * 0.92,height: 48, // Ajuste idéntico a la altura estándar de un renglón de acciones
                decoration: BoxDecoration(
                  color: colorAppBarFondo,borderRadius: BorderRadius.circular(24.0), // Cápsula delgada estilizada
                  border: Border.all(color: esOscuro ? Colors.grey.shade800 : Colors.black12,width: 1,),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26,blurRadius: 8,spreadRadius: 1,offset: Offset(0, 3),)
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24.0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [// 1. Indicador textual de citas seleccionadas
                        Builder(builder: (context) {
                          List<int> ordenados = List.from(_versiculosSeleccionados)..sort();
                          String versiculosFormateados = _formatearVersiculosCita(ordenados);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0),
                            child: Text('$nombreLibro $_capituloSeleccionado:$versiculosFormateados',
                              style: TextStyle(fontWeight: FontWeight.bold, color: colorAppBarTexto, fontSize: 13),
                            ),
                          );
                        },),// Divisor vertical idéntico a tus estándares estéticos
                        VerticalDivider(color: esOscuro ? Colors.grey.shade800 : Colors.black12, width: 16, thickness: 1, indent: 10, endIndent: 10),
                        // 2. PALETA DIRECTA DE ACCIÓN RÁPIDA (Usando tu widget _circuloPaleta original)
                        ...[Colors.yellow.toARGB32(), Colors.green.toARGB32(), Colors.blue.toARGB32(), Colors.pink.toARGB32()].map((int colorValue) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3.0),
                              child: _circuloPaleta(
                                colorValue, (int colorElegido) async {
                                  final List<int> loteAProcesar = List.from(_versiculosSeleccionados);
                                  for (int numV in loteAProcesar) {
                                    _alternarResaltadoVersiculoEnLote(numV, colorElegido);
                                    // Estructuramos la llave exacta de forma idéntica a tu persistencia
                                    final String llaveVersiculo = '${_versionSeleccionada}_${_libroSeleccionado}_${_capituloSeleccionado}_$numV';
                                    await _dbHelper.sincronizarResaltadoAnube(llaveVersiculo, colorElegido);
                                  }
                                  await _guardarResaltadosEnDisco();
                                  setState(() {
                                    _versiculosSeleccionados.clear();_modoSeleccionMultiple = false;
                                    }
                                  );
                                }
                              ),
                            );
                          }
                        ),
                  
                        // Botón rápido para borrar el sombreado del lote (Envía un 0 al motor de persistencia)
                        IconButton(padding: EdgeInsets.zero,constraints: const BoxConstraints(),
                          icon: const Icon(Icons.layers_clear, color: Colors.red, size: 20),
                          tooltip: 'Borrar sombreados',
                          onPressed: () async {
                            final List<int> loteALimpiar = List.from(_versiculosSeleccionados);
                            for (int numV in loteALimpiar) {_alternarResaltadoVersiculoEnLote(numV, 0);
                              final String llaveVersiculo = '${_versionSeleccionada}_${_libroSeleccionado}_${_capituloSeleccionado}_$numV';
                              await _dbHelper.sincronizarResaltadoAnube(llaveVersiculo, 0);
                            }
                            await _guardarResaltadosEnDisco();
                            setState(() {_versiculosSeleccionados.clear();_modoSeleccionMultiple = false;
                            });
                          },
                        ),
                        VerticalDivider(color: esOscuro ? Colors.grey.shade800 : Colors.black12, width: 16, thickness: 1, indent: 10, endIndent: 10),
                
                        // 3. NUEVO BOTÓN: Comparar traducciones en lote
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.compare_arrows_rounded, color: esOscuro ? Colors.purple.shade300 : Colors.purple.shade700, size: 22),
                          tooltip: 'Comparar versiones',onPressed: () {
                            List<int> ordenados = List.from(_versiculosSeleccionados)..sort();
                            if (ordenados.isNotEmpty) {_mostrarDialogoComparativaVersiones(ordenados.first);}
                          },
                        ),
                        const SizedBox(width: 14),
                    
                        // 4. BOTÓN: Compartir bloque de texto con firma de la Aplicación
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.share, color: esOscuro ? Colors.teal.shade300 : Colors.teal.shade700, size: 20),
                          tooltip: 'Compartir pasajes',
                          onPressed: () {
                            List<int> ordenados = List.from(_versiculosSeleccionados)..sort();
                            StringBuffer textoCompletoBloque = StringBuffer();
                            
                            for (int numV in ordenados) {
                              final vData = _versiculos.firstWhere((element) => element['versiculo'] == numV, orElse: () => {});
                              if (vData.isNotEmpty) {
                                textoCompletoBloque.write('[$numV] ${vData['texto']}\n');
                              }
                            }
                            
                            String versiculosFormateados = _formatearVersiculosCita(ordenados);
                            
                            // ⚙️ CONFIGURACIÓN FUTURA DE TIENDAS:
                            // En cuanto subas la app, cambia este String vacío por tu package name (Ej: 'com.misitioweb.bibliapredicador')
                            const String packageStoreName = ''; 

                            // Generamos la firma de marca con estilos enriquecidos para WhatsApp (* = Negrita, _ = Cursiva)
                            StringBuffer firmaEstructurada = StringBuffer();
                            firmaEstructurada.write('\n📖 Compartido desde la app *_Biblia del Predicador_*');
                            firmaEstructurada.write('\n✨ _Herramientas avanzadas para el ministerio pastoral_');
                            
                            // Si la variable del paquete tiene texto, el enlace se añade automáticamente al mensaje
                            if (packageStoreName.isNotEmpty) {
                              firmaEstructurada.write('\n🔗 Descárgala en Google Play: https://google.com');
                            }

                            // Unimos los versículos compactos, la cita formal y la firma dinámica
                            final String message = '$textoCompletoBloque— $nombreLibro $_capituloSeleccionado:$versiculosFormateados ($_versionSeleccionada)\n$firmaEstructurada';
                            
                            SharePlus.instance.share(ShareParams(text: message)); 
                            
                            setState(() {
                              _versiculosSeleccionados.clear();
                              _modoSeleccionMultiple = false;
                            });
                          },
                        ),

                        const SizedBox(width: 14),
              
                        // 5. BOTÓN: Enviar al Editor de sermones
                        IconButton(padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),icon: const Icon(Icons.send_and_archive, color: Color(0xFF1A73E8), size: 20),
                          tooltip: 'Insertar en el sermón',
                          onPressed: () {List<int> ordenados = List.from(_versiculosSeleccionados)..sort();
                            String versiculosFormateados = _formatearVersiculosCita(ordenados);
                            final String citaRango = '$nombreLibro $_capituloSeleccionado:$versiculosFormateados';
                            CanalEventos().enviarCitaAlEditor(citaRango);
                            setState(() {_versiculosSeleccionados.clear();_modoSeleccionMultiple = false;});
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),),),),],),),
        ],
      ),
    );
  }

  // Busca y reemplaza este método exacto en lib/modules/lector/visor_biblia_libro.dart
  void _mostrarBuscadorGlobalFlotante() {
    final TextEditingController controladorBusqueda = TextEditingController();
    List<Map<String, dynamic>> resultadosLocales = [];
    bool buscando = false;
    
    // 🚀 DEBOUNCER LOCAL: Controla el flujo de peticiones automáticas
    Timer? debounceTimerModal;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalState) {
            final String terminoBuscado = controladorBusqueda.text.trim();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Buscador Global Concordancia',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 12),
                  
                  // Campo de Entrada Automatizado y Reactivo
                  TextField(
                    controller: controladorBusqueda,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    
                    // 🚀 DISPARADOR AUTOMÁTICO EN TIEMPO REAL:
                    onChanged: (texto) {
                      // Actualiza de inmediato la UI interna para alternar el botón de borrar/buscar
                      modalState(() {});

                      // Evita peticiones innecesarias a Supabase si el texto es muy corto
                      if (texto.trim().length < 3) {
                        modalState(() => resultadosLocales = []);
                        return;
                      }

                      // Reinicia el temporizador si el usuario sigue escribiendo rápido
                      if (debounceTimerModal?.isActive ?? false) debounceTimerModal!.cancel();
                      
                      // Espera 600ms de inactividad antes de lanzar la consulta automática
                      debounceTimerModal = Timer(const Duration(milliseconds: 600), () async {
                        modalState(() => buscando = true);

                        final datos = await _dbHelper.buscarPalabraClaveGlobal(texto);

                        modalState(() {
                          resultadosLocales = datos;
                          buscando = false;
                        });
                      });
                    },
                    
                    decoration: InputDecoration(
                      hintText: 'Ej: "Espíritu Santo", "gracia", "fe"...',
                      prefixIcon: const Icon(Icons.search, color: Colors.blue),
                      suffixIcon: controladorBusqueda.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                              onPressed: () {
                                if (debounceTimerModal?.isActive ?? false) debounceTimerModal!.cancel();
                                controladorBusqueda.clear();
                                modalState(() {
                                  resultadosLocales.clear();
                                });
                              },
                            )
                          : IconButton(
                              icon: const Icon(Icons.arrow_circle_right_rounded, color: Color(0xFF1A73E8), size: 28),
                              onPressed: () async {
                                if (controladorBusqueda.text.trim().isEmpty) return;
                                if (debounceTimerModal?.isActive ?? false) debounceTimerModal!.cancel();
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
                      if (debounceTimerModal?.isActive ?? false) debounceTimerModal!.cancel();
                      modalState(() => buscando = true);
                      final datos = await _dbHelper.buscarPalabraClaveGlobal(val);
                      modalState(() { resultadosLocales = datos; buscando = false; });
                    },
                  ),
                  const SizedBox(height: 10),
                  
                  // Lista de Resultados con Fragmentos Resaltados
                  Expanded(
                    child: buscando
                        ? const Center(child: CircularProgressIndicator())
                        : resultadosLocales.isEmpty
                            ? const Center(
                                child: Text(
                                  'Escribe al menos 3 letras para buscar de forma automática...',
                                  style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                                ),
                              )
                            : ListView.builder(
                                itemCount: resultadosLocales.length,
                                itemBuilder: (context, index) {
                                  final res = resultadosLocales[index];
                                  final int libroId = res['libro_id'] ?? 1;
                                  final int capNum = res['capitulo'] ?? 1;
                                  final int verNum = res['versiculo'] ?? 1;
                                  final String textoVerso = res['texto'] ?? '';
                                  final String nombreLibro = _dbHelper.obtenerNombreLibro(libroId);

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
                                        children: _crearFragmentosResaltados(textoVerso, terminoBuscado),
                                      ),
                                    ),
                                    shape: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
                                    onTap: () {
                                      if (debounceTimerModal?.isActive ?? false) debounceTimerModal!.cancel();
                                      Navigator.pop(context); // Cierra el modal
                                      _histOriginalRegresoAlSaltar();
                                      setState(() {
                                        _libroSeleccionado = libroId;
                                        _capituloSeleccionado = capNum;
                                      });
                                      _cargarResaltadosYTexto();
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
      },
    ).then((_) {
      // 🚀 LIMPIEZA ADICIONAL AL CERRAR: Cancela el timer por si el pastor cierra el modal antes de los 600ms
      debounceTimerModal?.cancel();
    });
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

  // Método modular para guardar el rastro de lectura antes del salto
  void _histOriginalRegresoAlSaltar({int? versiculo}) {
    _historialNavegacionRegreso.add({
      'libro': _libroSeleccionado,
     'capitulo': _capituloSeleccionado,
     'versiculo': versiculo ?? (_versiculosSeleccionados.isNotEmpty ?
     _versiculosSeleccionados.first : 1),
    });
  }  

  Widget _circuloPaleta(int colorValue, Function(int) onTap) {
    return InkWell(
      onTap: () => onTap(colorValue),
      child: CircleAvatar(backgroundColor: Color(colorValue), radius: 16),
    );
  }

  // 💾 MOTOR DE PERSISTENCIA: Guarda o elimina los resaltados directamente en SharedPreferences
  void _alternarResaltadoVersiculoEnLote(int versiculo, int colorHex) {
    final llave = '${_versionSeleccionada}_${_libroSeleccionado}_${_capituloSeleccionado}_$versiculo';

    setState(() {
      if (colorHex == 0) {
        // Si el color es 0, el pastor seleccionó "Borrar sombreado" desde la paleta
        _resaltadosLocales.remove(llave);
      } else {
        // De lo contrario, asigna o actualiza el color seleccionado al versículo
        _resaltadosLocales[llave] = colorHex;
      }
    });
  }

  // 🚀 FUNCIÓN COMPLEMENTARIA: Guarda el mapa completo en el disco de forma asíncrona
  Future<void> _guardarResaltadosEnDisco() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('biblioteca_resaltados', jsonEncode(_resaltadosLocales));
    } catch (e) {
      debugPrint('Aviso al persistir la paleta de sombreados en disco: $e');
    }
  }

  Widget _construirBarraNavegacionRapida() {
    final int totalCapitulosDelLibro = _dbHelper.obtenerTotalCapitulos(_libroSeleccionado);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: (_capituloSeleccionado > 1 || _libroSeleccionado > 1) 
                ? () { 
                   _histOriginalRegresoAlSaltar(); 
                  setState(() {
                      if (_capituloSeleccionado > 1) {
                        // Caso A: Retrocede un capítulo en el mismo libro
                        _capituloSeleccionado--;
                      } else {
                        // Caso B: Llegó al capítulo 1, retrocede al libro anterior y va a su último capítulo
                        _libroSeleccionado--;
                        _capituloSeleccionado = _dbHelper.obtenerTotalCapitulos(_libroSeleccionado);
                      }
                    });
                    _cargarResaltadosYTexto();
                  }
                : null,
          ),
          TextButton.icon(
            onPressed: _mostrarSelectorLibroYCapitulo,
            icon: const Icon(Icons.unfold_more, size: 16),
            label: Text(_dbHelper.obtenerNombreLibro(_libroSeleccionado), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 18),
            onPressed: (_capituloSeleccionado < totalCapitulosDelLibro || _libroSeleccionado < 66) 
            ? () {
               _histOriginalRegresoAlSaltar(); 
              setState(() {
                      if (_capituloSeleccionado < totalCapitulosDelLibro) {
                        // Caso A: Avanza un capítulo en el mismo libro
                        _capituloSeleccionado++;
                      } else {
                        // Caso B: Llegó al límite del libro, salta al capítulo 1 del siguiente libro
                        _libroSeleccionado++;
                        _capituloSeleccionado = 1;
                      }
                    });
                    _cargarResaltadosYTexto(); // <-- CORRECCIÓN: Nombre de método correcto
            }
            : null, // Se apaga por completo si está en Apocalipsis 22 (Fin de la Biblia)
          ),
        ],
      ),
    );
  }

  // Cuadro de diálogo modal rápido para saltar directo a cualquier libro de la Biblia
  // LA MEJOR OPCIÓN: Selector unificado con pestañas (TabBar) integradas
  void _mostrarSelectorLibroYCapitulo() {
    // Inicializamos variables temporales con lo que el usuario está leyendo actualmente
    int libroIdTemporal = _libroSeleccionado;
    String nombreLibroTemporal = _dbHelper.obtenerNombreLibro(_libroSeleccionado);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        // DefaultTabController maneja el estado de las pestañas automáticamente
        // Si ya hay un libro, inicia en la pestaña 1 (Capítulos). Si no, en la 0 (Libros).
        final int indiceInicial = ( _libroSeleccionado > 0) ? 1 : 0;

        return DefaultTabController(
          length: 2,
          initialIndex: indiceInicial,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.85, // Un poco más alto para las pestañas
                padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
                child: Column(
                  children: [
                    // DISEÑO DE PESTAÑAS (TABBAR)
                    TabBar(
                      labelColor: const Color(0xFF1A73E8),
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: const Color(0xFF1A73E8),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      tabs: [
                        const Tab(text: 'LIBROS'),
                        Tab(text: 'CAPÍTULOS ($nombreLibroTemporal)'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // CONTENIDO DE LAS PESTAÑAS
                    Expanded(
                      child: TabBarView(
                        children: [
                          
                          // PESTAÑA 0: Lista de Libros
                          ListView.builder(
                            itemCount: 66,
                            itemBuilder: (context, index) {
                              final int libroId = index + 1;
                              final String nombreLibro = _dbHelper.obtenerNombreLibro(libroId);
                              final bool esLibroActual = libroId == _libroSeleccionado;

                              return ListTile(
                                selected: esLibroActual,
                                selectedTileColor: Colors.blue.shade50.withValues(alpha: 0.4),
                                leading: CircleAvatar(
                                  backgroundColor: esLibroActual ? Colors.blue : Colors.blue.shade50,
                                  child: Text('$libroId', style: TextStyle(fontSize: 12, color: esLibroActual ? Colors.white : Colors.blue, fontWeight: FontWeight.bold)),
                                ),
                                title: Text(nombreLibro, style: TextStyle(fontWeight: esLibroActual ? FontWeight.bold : FontWeight.w600, fontSize: 16)),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                                onTap: () {
                                  // Al tocar un libro, actualizamos el estado interno del modal
                                  setModalState(() {
                                    libroIdTemporal = libroId;
                                    nombreLibroTemporal = nombreLibro;
                                  });
                                  // Cambiamos automáticamente a la pestaña de capítulos
                                  DefaultTabController.of(context).animateTo(1);
                                },
                              );
                            },
                          ),

                          // PESTAÑA 1: Cuadrícula de Capítulos
                          GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: _dbHelper.obtenerTotalCapitulos(libroIdTemporal),
                            itemBuilder: (context, index) {
                              final int capNum = index + 1;
                              final bool esCapituloActual = libroIdTemporal == _libroSeleccionado && capNum == _capituloSeleccionado;

                              return InkWell(
                                onTap: () {
                                  // Guardamos la selección definitiva en la pantalla principal
                                  setState(() {
                                    _libroSeleccionado = libroIdTemporal;
                                    _capituloSeleccionado = capNum;
                                  });
                                  _cargarResaltadosYTexto();
                                  Navigator.pop(context); // Cierra el modal
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: esCapituloActual ? Colors.blue : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: esCapituloActual ? Colors.blue : Colors.black12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$capNum',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: esCapituloActual ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
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

    // 🚀 INTERFAZ MODAL: Muestra la bitácora de lectura con opción de re-lectura inmediata
  void _mostrarHistorialLecturaModal() {
    final bool esOscuro = _ajustesGlobales.modoOscuroLectura;
    final Color colorFondoM = esOscuro ? const Color(0xFF1E1E1E) : Colors.white;
    final Color colorTextoM = esOscuro ? Colors.white : Colors.black87;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colorFondoM,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.70,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '📜 Bitácora de Lectura Devocional',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: esOscuro ? Colors.blue.shade300 : const Color(0xFF1A73E8)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const Divider(height: 10),
              const SizedBox(height: 8),
              
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  // 💡 Consulta al Helper de la base de datos tu tabla de registros históricos
                  future: _dbHelper.obtenerHistorialLectura(), 
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final registros = snapshot.data ?? [];
                    if (registros.isEmpty) {
                      return const Center(
                        child: Text(
                          'Aún no registras capítulos completados.\n¡Tus lecturas aparecerán aquí!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: registros.length,
                      itemBuilder: (context, index) {
                        final reg = registros[index];
                        final int libId = reg['libro_id'] ?? 1;
                        final int capNum = reg['capitulo'] ?? 1;
                        final String fecha = reg['fecha_lectura'] ?? reg['created_at'] ?? '';
                        final String nombreLibroHist = _dbHelper.obtenerNombreLibro(libId);

                        // Formateo visual discreto de la fecha (extrae YYYY-MM-DD si viene con hora)
                        final String fechaLimpia = fecha.length >= 10 ? fecha.substring(0, 10) : fecha;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF1A73E8).withValues(alpha: 0.1),
                            child: const Icon(Icons.menu_book_rounded, color: Color(0xFF1A73E8), size: 20),
                          ),
                          title: Text(
                            '$nombreLibroHist Capítulo $capNum',
                            style: TextStyle(fontWeight: FontWeight.bold, color: colorTextoM, fontSize: 15),
                          ),
                          subtitle: Text(
                            'Completado el: $fechaLimpia',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                          shape: Border(bottom: BorderSide(color: esOscuro ? Colors.grey.shade800 : Colors.grey.shade200, width: 0.5)),
                          onTap: () {
                            Navigator.pop(context); // Cierra el historial
                            
                            // Guardamos la lectura actual en la pila de retorno antes de saltar
                            _histOriginalRegresoAlSaltar();
                            
                            setState(() {
                              _libroSeleccionado = libId;
                              _capituloSeleccionado = capNum;
                            });
                            
                            _cargarResaltadosYTexto(); // Salta al capítulo histórico seleccionado
                          },
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
}    