import 'package:mi_app_biblica/database/migrador_biblico.dart';
import 'dart:async'; // Requerido para el Timer (Debouncer)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:mi_app_biblica/database/biblia_db_helper.dart';
import 'package:mi_app_biblica/modules/lector/vista_lector.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:mi_app_biblica/database/pasaje_biblico_model.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mi_app_biblica/modules/lector/panel_busqueda_global.dart';
import 'package:mi_app_biblica/modules/lector/visor_biblia_libro.dart';
import '../../database/ajustes_config.dart';
import '../lector/panel_ajustes_view.dart';
import '../lector/repasador_resaltados_view.dart';
import 'package:mi_app_biblica/database/canal_eventos.dart';
import 'package:speech_to_text/speech_to_text.dart' as speech_to_text;

class VistaEditorBosquejo extends StatefulWidget {
  const VistaEditorBosquejo({super.key});

  @override
  State<VistaEditorBosquejo> createState() => _VistaEditorBosquejoState();
}

class _VistaEditorBosquejoState extends State<VistaEditorBosquejo> {
  final quill.QuillController _controller = quill.QuillController.basic();
  final TextEditingController _tituloController = TextEditingController(text: 'Título del sermon');
  
  // SOLUCIÓN AL RENDIMIENTO DEL EDITOR: Mantener instancias fijas en memoria
  final FocusNode _editorFocusNode = FocusNode();
  final FocusNode _predicacionFocusNode = FocusNode();
  Timer? _debouncer; // Temporizador para retrasar el escaneo de citas bíblicas
  // NUEVO: Controlador para el desplazamiento del sermón en el púlpito
  final ScrollController _scrollPredicacionController = ScrollController();
  // Dentro de tu _VistaEditorBosquejoState:
  final AjustesConfig _ajustesGlobales = AjustesConfig(); 

  // 🚀 VARIABLES PARA DICTADO POR VOZ
  final speech_to_text.SpeechToText _speechToText = speech_to_text.SpeechToText();
  bool _discursoInicializado = false;
  bool _estaGrabandoPorVoz = false;
  
  StreamSubscription? _suscripcionEventosBiblia;
  List<PasajeBiblico> _pasajesDetectados = [];
  PasajeBiblico? _pasajeSeleccionado;
  List<Map<String, dynamic>> _historialSermones = [];
  bool _guardando = false;
  bool _modoPredicacion = false;
  quill.QuillController? _predicacionController;
  bool _mostrarBuscadorEnTablet = false; // Controla el panel derecho en pantallas grandes


  @override
  void initState() {
    super.initState();
    _controller.addListener(_manejarCambioTextoConDebounce);
    _ajustesGlobales.cargarAjustes(); // Carga las preferencias del disco duro
    // Escucha cuando el usuario cambia un ajuste para redibujar el editor
    _ajustesGlobales.addListener(() => setState(() {})); 
    _cargarHistorial();
    
    // 🚀 ACTIVAR SINCRONIZACIÓN AUTOMÁTICA EN SEGUNDO PLANO
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> resultados) {
      if (resultados.isNotEmpty && resultados.first != ConnectivityResult.none) {
        _sincronizarBorradoresLocalesAnube();
      }
    });

    _suscripcionEventosBiblia = CanalEventos().alRecibirCita.listen((String cita) {
      _inyectarCitaEnCursor(cita);
    });
  }

  @override
  void dispose() {
    _suscripcionEventosBiblia?.cancel(); // Cancelamos la antena global de radio
    _ajustesGlobales.removeListener(() => setState(() {}));
    _controller.removeListener(_manejarCambioTextoConDebounce);
    _debouncer?.cancel();
    _editorFocusNode.dispose();
    _predicacionFocusNode.dispose();
    _scrollPredicacionController.dispose();
    _tituloController.dispose();
    _controller.dispose();
    _predicacionController?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _cargarHistorial() async {
    final datosNube = await BibliaDatabaseHelper().obtenerHistorialBosquejos();
    List<Map<String, dynamic>> listaCombinada = List.from(datosNube);

    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> borradoresRaw = prefs.getStringList('borradores_locales') ?? [];

      for (var raw in borradoresRaw) {
        listaCombinada.insert(0, jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}

    if (mounted) {
      setState(() { _historialSermones = listaCombinada; });
    }
  }

  void _inicializarDictadoPorVoz() {
    if (_discursoInicializado) return;

    try {
      // 🚀 SOLUCIÓN: Quitamos 'await'. Al invocarlo de forma directa, 
      // a Dart ya no le importa si la función devuelve un bool, un Future o un void.
      _speechToText.initialize(
        onStatus: (status) {
          if (status == 'notListening' && mounted) {
            setState(() => _estaGrabandoPorVoz = false);
          }
        },
        onError: (errorNotification) => print('Error dictado: $errorNotification'),
      );
      
      // Cambiamos el estado asumiendo disponibilidad del plugin nativo
      if (mounted) {
        setState(() {
          _discursoInicializado = true;
        });
      }
    } catch (e) {
      print('Excepción al inicializar micrófono: $e');
      if (mounted) {
        setState(() {
          _discursoInicializado = false;
        });
      }
    }
  }

  void _alternarDictadoPorVoz() {
    // Inicializamos sin retener el flujo lineal (sin await)
    _inicializarDictadoPorVoz();

    if (_estaGrabandoPorVoz) {
      // 🚀 SOLUCIÓN: Detener la grabación de forma directa sin expresiones asíncronas
      _speechToText.stop(); 
      
      if (mounted) {
        setState(() => _estaGrabandoPorVoz = false);
      }
    } else {
      if (!_discursoInicializado) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, concede permisos de micrófono en los ajustes del teléfono.'), 
            backgroundColor: Colors.red
          )
        );
        return;
      }

      if (mounted) {
        setState(() => _estaGrabandoPorVoz = true);
      }
      
      int indexCursorInicial = _controller.selection.baseOffset;
      if (indexCursorInicial < 0) indexCursorInicial = _controller.document.length - 1;

      String textoPrevioDictado = '';

      // 🚀 SOLUCIÓN DEFINITIVA: Removemos 'await' de la llamada a .listen()
      // Esto elimina de raíz la alerta de expresión de tipo 'void' en cualquier entorno de Flutter.
      _speechToText.listen(
        localeId: 'es_ES', 
        onResult: (result) {
          if (mounted) {
            setState(() {
              String nuevoTextoDictado = result.recognizedWords;
              
              if (nuevoTextoDictado.length > textoPrevioDictado.length) {
                String fragmentoNuevo = nuevoTextoDictado.substring(textoPrevioDictado.length);
                
                // Inserción limpia en tu editor Quill
                _controller.document.insert(indexCursorInicial, fragmentoNuevo);
                
                indexCursorInicial += fragmentoNuevo.length;
                _controller.updateSelection(
                  TextSelection.collapsed(offset: indexCursorInicial),
                  quill.ChangeSource.local,
                );
                
                textoPrevioDictado = nuevoTextoDictado;
              }
            });
          }
        },
      );
    }
  }
  
  // Método optimizado para insertar solo la nomenclatura de la cita
  void _inyectarCitaEnCursor(String cita) {
    final indexCursor = _controller.selection.baseOffset;
    final String textoAInsertar = ' $cita '; 

    if (indexCursor >= 0) {
      _controller.document.insert(indexCursor, textoAInsertar);
      _controller.updateSelection(
        TextSelection.collapsed(offset: indexCursor + textoAInsertar.length),
        quill.ChangeSource.local,
      );
    } else {
      final int longitudDocumento = _controller.document.length;
      _controller.document.insert(longitudDocumento - 1, textoAInsertar);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📖 Cita sincronizada en el sermón: $cita'),
        backgroundColor: const Color(0xFF2D1B10),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _cargarSermonEnEditor(Map<String, dynamic> sermon) {
    setState(() {
      _tituloController.text = sermon['titulo'] ?? '';
      final jsonDelta = jsonDecode(sprintClean(sermon['contenido_json']));
      _controller.document = quill.Document.fromJson(jsonDelta);
      Navigator.pop(context); 
    });
  }

  String sprintClean(dynamic input) => input is String ? input : jsonEncode(input);

  void _manejarCambioTextoConDebounce() {
    if (_debouncer?.isActive ?? false) _debouncer!.cancel();
    _debouncer = Timer(const Duration(milliseconds: 500), () {
      _analizarTextoConRegEx();
    });
  }

  void _analizarTextoConRegEx() async {
    final textoPlano = _controller.document.toPlainText();
    final regExp = RegExp(r'\b([1-3]?\s?[A-Z][a-záéíóúÁÉÍÓÚñÑ]+)\s+([0-9]+):([0-9]+)\b');
    final matches = regExp.allMatches(textoPlano);
    
    if (matches.isEmpty && _pasajesDetectados.isEmpty) return;

    List<PasajeBiblico> nuevosPasajes = [];
    final dbHelper = BibliaDatabaseHelper();

    const Map<String, int> diccionarioLocalEditor = {
      'gn': 1, 'ex': 2, 'lv': 3, 'nm': 4, 'dt': 5, 'jos': 6, 'jue': 7, 'rt': 8,
      '1 sm': 9, '1sm': 9, '2 sm': 10, '2sm': 10, '1 r': 11, '1r': 11, '2 r': 12, '2r': 12, 
      '1 cr': 13, '1cr': 13, '2 cr': 14, '2cr': 14, 'esd': 15, 'neh': 16, 'est': 17, 'job': 18, 
      'sal': 19, 'pr': 20, 'ec': 21, 'cnt': 22, 'is': 23, 'jr': 24, 'lam': 25, 'ez': 26, 
      'dn': 27, 'os': 28, 'jl': 29, 'am': 30, 'abd': 31, 'jon': 32, 'mi': 33, 'nah': 34, 
      'hab': 35, 'sof': 36, 'hag': 37, 'zac': 38, 'mal': 39, 'mt': 40, 'mr': 41, 'lc': 42, 
      'jn': 43, 'hch': 44, 'ro': 45, '1 co': 46, '1co': 46, '1 cor': 46, '2 co': 47, '2co': 47, 
      'ga': 48, 'ef': 49, 'flp': 50, 'col': 51, '1 ts': 52, '1ts': 52, '2 ts': 53, '2ts': 53, 
      '1 ti': 54, '1ti': 54, '2 ti': 55, '2ti': 55, 'ti': 56, 'flm': 57, 'heb': 58, 'stg': 59, 
      '1 p': 60, '1p': 60, '2 p': 61, '2p': 61, '1 jn': 62, '1jn': 62, '2 jn': 63, '2jn': 63, 
      '3 jn': 64, '3jn': 64, 'jud': 65, 'ap': 66
    };

    for (var match in matches) {
      final String nombreLibroRaw = match.group(1)!.trim();
      final String nombreLibroMinuscula = nombreLibroRaw.toLowerCase();
      
      int libroId = 0;

      if (diccionarioLocalEditor.containsKey(nombreLibroMinuscula)) {
        libroId = diccionarioLocalEditor[nombreLibroMinuscula]!;
      } else {
        libroId = dbHelper.obtenerLibroId(nombreLibroRaw);
      }
      
      if (libroId == 0) continue;
      
      nuevosPasajes.add(PasajeBiblico(
        libroId: libroId, 
        capitulo: int.parse(match.group(2)!),
        versiculo: int.parse(match.group(3)!), 
        textoOriginal: match.group(0)!,
      ));
    }

    if (nuevosPasajes.length != _pasajesDetectados.length) {
      if (mounted) {
        setState(() { _pasajesDetectados = nuevosPasajes; });
      }
    }
  }

  void _activarModoPredicacion() {
    WakelockPlus.enable(); 
    setState(() {
      _predicacionController = quill.QuillController(
        document: quill.Document.fromDelta(_controller.document.toDelta()),
        selection: const TextSelection.collapsed(offset: 0),
      );
      _modoPredicacion = true;
    });
  }

  Future<void> _guardarBosquejoEnNube() async {
    final tituloLimpio = _tituloController.text.trim();
    if (tituloLimpio.isEmpty) return;

    setState(() { _guardando = true; });
    final jsonString = jsonEncode(_controller.document.toDelta().toJson());

    try {
      await Supabase.instance.client.from('bosquejos').insert({
        'titulo': tituloLimpio, 
        'contenido_json': jsonString,
      });

      _cargarHistorial();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Guardado en la nube con éxito!'), backgroundColor: Colors.green)
        );
      }
    } catch (errorDeRed) {
      try {
        final prefs = await SharedPreferences.getInstance();
        
        final mapaLocal = {
          'titulo': '$tituloLimpio (Sin Sincronizar)',
          'contenido_json': jsonString,
          'updated_at': DateTime.now().toIso8601String(),
        };

        List<String> borradoresLocales = prefs.getStringList('borradores_locales') ?? [];
        borradoresLocales.add(jsonEncode(mapaLocal));
        
        await prefs.setStringList('borradores_locales', borradoresLocales);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sin conexión. Guardado localmente en el dispositivo de emergencia.'), 
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            )
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fallo crítico de almacenamiento: $e'), backgroundColor: Colors.red)
          );
        }
      }
    } finally { 
      if (mounted) setState(() { _guardando = false; }); 
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si está activo el modo predicación, ejecutamos la vista de púlpito optimizada anteriormente
    if (_modoPredicacion && _predicacionController != null) {
      return _construirPantallaPredicacion(); // Mueve tu scaffold de predicación aquí para mantener limpio el código
    }

    // LAYOUTBUILDER: Analiza el ancho en tiempo real de la pantalla del dispositivo
    return LayoutBuilder(
      builder: (context, constraints) {
        // Estándar de diseño: Si el ancho es mayor a 768px se considera Tablet/iPad o Web
        final esPantallaAncha = constraints.maxWidth > 768;

        return Scaffold(
          appBar: AppBar(title: const Text('Mi Biblioteca de Predicación')),
          drawer: _construirMenuHistorial(), // Tu Drawer existente
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _guardando ? null : _guardarBosquejoEnNube,
            label: _guardando 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                : const Text('Guardar'),
            icon: const Icon(Icons.cloud_upload),
          ),
          // DISEÑO ADAPTABLE
          body: esPantallaAncha 
              ? _construirDisenoTabletYWeb() 
              : _construirDisenoCelular(),
        );
      },
    );
  }
    // MÉTODO EXTRAÍDO: Contiene toda la lógica visual optimizada para el púlpito
    Widget _construirPantallaPredicacion() {
    // 1. Obtenemos las configuraciones de diseño base de tu versión de flutter_quill
    final estilosBase = quill.DefaultStyles.getInstance(context);

    // 2. Modificamos el parágrafo usando SU PROPIO método copyWith (Evita el error en DefaultStyles)
    final estiloParrafoModificado = estilosBase.paragraph?.copyWith(
      style: const TextStyle(
        fontSize: 24.0,           // Texto grande para el púlpito
        height: 1.6,              // Espaciado entre líneas para evitar perder la lectura
        color: Color(0xFF2D1B10), // Color marrón oscuro suave para los ojos
      ),
    );

    // 3. Creamos un contenedor de estilos asignando el parágrafo personalizado
    final configuracionEstilosPulpito = quill.DefaultStyles(
      paragraph: estiloParrafoModificado,
      // Conservamos las configuraciones estructurales de los demás bloques por defecto
      h1: estilosBase.h1,
      h2: estilosBase.h2,
      h3: estilosBase.h3,
      lists: estilosBase.lists,
      quote: estilosBase.quote,
      code: estilosBase.code,
      link: estilosBase.link,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF4ECD8), // Color sepia premium
      appBar: AppBar(
        backgroundColor: const Color(0xFFEADCB9),
        elevation: 0,
        title: Text(
          _tituloController.text, 
          style: const TextStyle(color: Color(0xFF3E2723), fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3E2723),
                foregroundColor: Colors.white,
              ),
              onPressed: () => setState(() => _modoPredicacion = false), 
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Editar Bosquejo'),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: quill.QuillEditor(
            controller: _predicacionController!,
            focusNode: _predicacionFocusNode,
            scrollController: _scrollPredicacionController, 
            config: quill.QuillEditorConfig(
              scrollable: true,
              autoFocus: false,
              expands: true,
              padding: const EdgeInsets.all(16),
              enableInteractiveSelection: false, 
              showCursor: false, 
              // Pasamos nuestro contenedor de estilos corregido
              customStyles: configuracionEstilosPulpito,
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirMenuHistorial() {
    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado del Menú Lateral
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF1A73E8)),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, color: Colors.blue, size: 35)),
            accountName: const Text('Biblioteca Pastoral', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            accountEmail: const Text('Modo Estudio Activo'),
          ),
          
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.blueGrey, size: 26),
            title: const Text('Ajustes Visuales', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: const Text('Personaliza el tamaño, fuente y colores'),
            onTap: () {
              Navigator.pop(context); // Cierra el menú lateral
              // Abre la paleta inferior de ajustes
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (context) => PanelAjustesView(ajustes: _ajustesGlobales),
              );
            },
          ),

          // 🚀 ACCESO AL NUEVO LECTOR INDEPENDIENTE (MODO LIBRO)
          ListTile(
            leading: const Icon(Icons.chrome_reader_mode, color: Colors.indigo, size: 26),
            title: const Text('Modo Lectura (Biblia Completa)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: const Text('Lee la Biblia y resalta tus textos de estudio'),
            onTap: () {
              Navigator.pop(context); // Cierra el menú lateral
              Navigator.push(context, MaterialPageRoute(builder: (context) => const VisorBibliaLibro()),
              );
            },
          ),
          // 🚀 ENLACE EN LIMPIO: Abre la nueva vista del recopilador de versículos marcados
          ListTile(
            leading: const Icon(Icons.bookmark_added, color: Colors.amber, size: 26),
            title: const Text('Marcas y Notas de Estudio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: const Text('Repasa todos tus versículos sombreados'),
            onTap: () {
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (context) => const RepasadorResaltadosView()));
            },
          ),
          const Divider(thickness: 1),
          
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('Mis Bosquejos Recientes:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          
          // Tu lista existente de ListView.builder con los sermones históricos
          Expanded(
            child: _historialSermones.isEmpty
                ? const Center(child: Text('No hay sermones guardados.'))
                : ListView.builder(
                    itemCount: _historialSermones.length,
                    itemBuilder: (context, index) {
                      final s = _historialSermones[index];
                      return ListTile(
                        leading: const Icon(Icons.description, color: Colors.blue),
                        title: Text(s['titulo'] ?? 'Sin título'),
                        onTap: () => _cargarSermonEnEditor(s),
                      );
                    },
                  ),
          ),
          const Divider(),
          // 🚀 BOTÓN TEMPORAL DE MIGRACIÓN: Se elimina una vez cargada la base de datos
                    Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(45),
              ),
              icon: const Icon(Icons.download_for_offline),
              label: const Text('Completar y Cargar Biblias'),
              onPressed: () async {
                // 1. Creamos el notificador nativo con el mensaje inicial
                final ValueNotifier<String> progresoNotifier = ValueNotifier<String>('Iniciando migrador...');

                // 2. Desplegamos el modal gráfico bloqueado
                showDialog(
                  context: context,
                  barrierDismissible: false, // Protege la transacción impidiendo cerrar el modal al tocar afuera
                  builder: (context) {
                    return AlertDialog(
                      title: const Row(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(width: 15),
                          Text('Carga Masiva Activa'),
                        ],
                      ),
                      // ValueListenableBuilder: Redibuja ÚNICAMENTE el texto cuando el valor cambia,
                      // logrando un rendimiento óptimo de 60 FPS en el celular sin tocar la UI principal.
                      content: ValueListenableBuilder<String>(
                        valueListenable: progresoNotifier,
                        builder: (context, valorProgreso, child) {
                          return Text(valorProgreso, style: const TextStyle(fontSize: 15));
                        },
                      ),
                    );
                  },
                );

                // 3. Ejecutamos el migrador asíncrono pasándole las actualizaciones al notificador
                                try {
                  final migrador = MigradorBiblico();

                  // 🚀 DICCIONARIO DE VERSIONES COMPLETO:
                  // Aquí puedes añadir o quitar de golpe todas las versiones que descargaste en la carpeta
                  final List<Map<String, String>> versionesAMigrar = [
                    {'id': 'RV1960', 'archivo': 'rv1960'},
                    {'id': 'RVC', 'archivo': 'rvc'},
                    {'id': 'RVA2015', 'archivo': 'rva2015'},
                    {'id': 'TLA', 'archivo': 'tla'},
                    {'id': 'TLAI', 'archivo': 'tlai'},
                    {'id': 'NVI', 'archivo': 'nvi128'},
                    {'id': 'NVIC', 'archivo': 'nvi1637'},
                    {'id': 'NTV', 'archivo': 'ntv'},
                    {'id': 'NBLA', 'archivo': 'nbla'},
                    {'id': 'LBLA', 'archivo': 'lbla'},
                    {'id': 'DHH', 'archivo': 'dhh'},
                    {'id': 'DHHS', 'archivo': 'dhhs'}, // Recuerda poner el nombre exacto de tu archivo .json
                  ];

                  // Bucle automatizado: Procesa e inyecta cada versión secuencialmente
                  for (var version in versionesAMigrar) {
                    await migrador.cargarVersionDesdeJsonLocal(
                      version['id']!, 
                      version['archivo']!, 
                      (msg) => progresoNotifier.value = '📖 ${version['id']}:\n$msg'
                    );
                    
                    // Pequeña pausa de estabilización de 300ms entre archivos para el procesador
                    await Future.delayed(const Duration(milliseconds: 300));
                  }

                  // 4. Proceso terminado con éxito total
                  if (context.mounted) {
                    Navigator.pop(context); // Cierra el cuadro de diálogo de carga
                    progresoNotifier.dispose(); // Liberamos la memoria del notificador
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('🎉 ¡Inyección masiva local completada con éxito! Todas las versiones están en tu servidor.'), 
                        backgroundColor: Colors.green
                      )
                    );
                  }
                } catch (error) {
                             
                }
              }
            ),
          )
        ],
      ),
    );
  }

  // 🏛️ DISEÑO TABLET/PC TOTALMENTE LIMPIO: Removida la barra de herramientas para máxima concentración
  Widget _construirDisenoTabletYWeb() {
    // 1. Obtenemos las configuraciones de diseño base de tu versión de flutter_quill
    final estilosBaseEditor = quill.DefaultStyles.getInstance(context);

    // 2. Modificamos el parágrafo usando SU PROPIO método copyWith (Evita errores de Spacing manuales)
    final estiloParrafoPersonalizado = estilosBaseEditor.paragraph?.copyWith(
      style: TextStyle(
        fontSize: _ajustesGlobales.tamanoLetra, // Tamaño dinámico del Slider de Ajustes
        fontFamily: _ajustesGlobales.tipoLetra, // Tipo de letra del Dropdown de Ajustes
        color: const Color(0xFF2D1B10),         // Color marrón suave
        height: 1.5,
      ),
    );

    // 3. Creamos el contenedor de estilos completo heredando los demás formatos
    final configuracionEstilosEditor = quill.DefaultStyles(
      paragraph: estiloParrafoPersonalizado,
      h1: estilosBaseEditor.h1,
      h2: estilosBaseEditor.h2,
      h3: estilosBaseEditor.h3,
      lists: estilosBaseEditor.lists,
      quote: estilosBaseEditor.quote,
      code: estilosBaseEditor.code,
      link: estilosBaseEditor.link,
    );

    // 4. Renderizamos la estructura multipanel de forma limpia
    return Row(
      children: [
        // COLUMNA IZQUIERDA: Área de Redacción del Sermón (70% del ancho)
        Expanded(
          flex: 7,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: TextField(controller: _tituloController, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _activarModoPredicacion, 
                      icon: const Icon(Icons.play_arrow), 
                      label: const Text('Predicar'),
                    ),
                  ],
                ),
                
                const Divider(), // Línea divisoria limpia debajo del título
                
                // 🚀 OPTIMIZACIÓN UX: Lienzo de escritura amplio a pantalla completa.
                // Se eliminó QuillSimpleToolbar para maximizar el espacio de redacción en PC/Tablet.
                Expanded(
                  child: Container(
                    color: Color(_ajustesGlobales.colorFondoHex), // Fondo dinámico (Sepia, Blanco, etc.)
                    child: quill.QuillEditor.basic(
                      controller: _controller, 
                      focusNode: _editorFocusNode,
                      config: quill.QuillEditorConfig(
                        customStyles: configuracionEstilosEditor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const VerticalDivider(width: 1),
        
        // COLUMNA DERECHA DINÁMICA: Lector Bíblico o Buscador Global (30% del ancho)
        Expanded(
          flex: 3,
          child: Container(
            color: const Color(0xFFF5F5F5),
            child: Column(
              children: [
                // Selector de herramienta superior para el estudio del pastor
                Container(
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => setState(() => _mostrarBuscadorEnTablet = false),
                          icon: Icon(Icons.menu_book, color: !_mostrarBuscadorEnTablet ? Colors.blue : Colors.grey),
                          label: Text('Lector', style: TextStyle(color: !_mostrarBuscadorEnTablet ? Colors.blue : Colors.grey)),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => setState(() => _mostrarBuscadorEnTablet = true),
                          icon: Icon(Icons.search, color: _mostrarBuscadorEnTablet ? Colors.blue : Colors.grey),
                          label: Text('Buscador', style: TextStyle(color: _mostrarBuscadorEnTablet ? Colors.blue : Colors.grey)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                
                // Renderizado condicional del panel derecho
                Expanded(
                  child: _mostrarBuscadorEnTablet 
                      ? PanelBusquedaGlobal(
                          onPasajeSeleccionado: (pasaje) {
                            setState(() {
                              _pasajeSeleccionado = pasaje;
                              _mostrarBuscadorEnTablet = false; // Cambia automáticamente al lector para desplegar el texto completo
                            });
                          },
                        )
                      : _construirPanelLectorBiblico(),
                ),
              ],
            ),
          ),
        )
      ],
    );
  }
 
  // 📱 DISEÑO CELULAR: Expandido a 3 pestañas independientes con editor adaptado a los Ajustes Visuales
  Widget _construirDisenoCelular() {
    // 1. Obtenemos las configuraciones de diseño base de tu versión de flutter_quill
    final estilosBaseEditor = quill.DefaultStyles.getInstance(context);

    // 2. Modificamos el parágrafo usando SU PROPIO método copyWith (Evita errores de Spacing manuales)
    final estiloParrafoPersonalizado = estilosBaseEditor.paragraph?.copyWith(
      style: TextStyle(
        fontSize: _ajustesGlobales.tamanoLetra, // Tamaño dinámico del Slider de Ajustes
        fontFamily: _ajustesGlobales.tipoLetra, // Tipo de letra del Dropdown de Ajustes
        color: const Color(0xFF2D1B10),         // Color marrón suave
        height: 1.5,
      ),
    );

    // 3. Creamos el contenedor de estilos completo heredando los demás formatos
    final configuracionEstilosEditor = quill.DefaultStyles(
      paragraph: estiloParrafoPersonalizado,
      h1: estilosBaseEditor.h1,
      h2: estilosBaseEditor.h2,
      h3: estilosBaseEditor.h3,
      lists: estilosBaseEditor.lists,
      quote: estilosBaseEditor.quote,
      code: estilosBaseEditor.code,
      link: estilosBaseEditor.link,
    );

    // 4. Renderizamos el controlador de pestañas móvil
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            labelColor: Color(0xFF1A73E8),
            indicatorColor: Color(0xFF1A73E8),
            tabs: [
              Tab(icon: Icon(Icons.edit_note), text: "Editor"),
              Tab(icon: Icon(Icons.menu_book), text: "Lector"),
              Tab(icon: Icon(Icons.search), text: "Buscador"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // PESTAÑA 1: Editor Móvil Ultra-Minimalista (Máximo espacio libre)
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _tituloController, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                          IconButton(
                            onPressed: _activarModoPredicacion, 
                            icon: const Icon(Icons.play_arrow, color: Colors.green),
                          ),
                          // 🚀 NUEVO BOTÓN DE DICTADO POR VOZ
                          IconButton(
                            icon: Icon(
                              _estaGrabandoPorVoz ? Icons.mic : Icons.mic_none, 
                              color: _estaGrabandoPorVoz ? Colors.red : Colors.blueGrey,
                              size: 26,
                            ),
                            onPressed: _alternarDictadoPorVoz,
                          ),
                          IconButton(
                            onPressed: _activarModoPredicacion, 
                            icon: const Icon(Icons.play_arrow, color: Colors.green),
                          ),
                        ],
                      ),
                      
                      const Divider(), // Línea divisoria limpia debajo del título
                      
                      // 🚀 OPTIMIZACIÓN UX: El lienzo de escritura ahora ocupa todo el alto disponible,
                      // libre de barras de herramientas molestas. Se controla 100% desde Ajustes Visuales.
                      Expanded(
                        child: Container(
                          color: Color(_ajustesGlobales.colorFondoHex), // Fondo dinámico (Sepia, Blanco, etc.)
                          child: quill.QuillEditor.basic(
                            controller: _controller, 
                            focusNode: _editorFocusNode,
                            config: quill.QuillEditorConfig(
                              customStyles: configuracionEstilosEditor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // PESTAÑA 2: Lector Bíblico Móvil Integrado (Corregido con barra inferior y rejilla)
                Container(
                  color: Colors.white, 
                  child: _construirPanelLectorBiblico(),
                ),
                
                // PESTAÑA 3: Buscador Global de Versículos en Supabase
                Container(
                  color: Colors.white, 
                  child: PanelBusquedaGlobal(
                    onPasajeSeleccionado: (pasaje) {
                      setState(() {
                        _pasajeSeleccionado = pasaje; // Carga el pasaje al presionar un resultado
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  // 3. CONTROL DEL PANEL LECTOR (Se mantiene optimizado como antes)
  Widget _construirPanelLectorBiblico() {
    return _pasajeSeleccionado != null
        ? Stack(
            children: [
              VistaLectorBiblia(
                pasaje: _pasajeSeleccionado!,
                onPasajeCambiado: (nuevoPasaje) {
                  setState(() { _pasajeSeleccionado = nuevoPasaje; });
                },
              ),
              Positioned(top: 10, right: 10, child: IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() => _pasajeSeleccionado = null))),
            ],
          )
        : ListView.builder(
            itemCount: _pasajesDetectados.length,
            itemBuilder: (context, index) => ListTile(
              title: Text(_pasajesDetectados[index].textoOriginal),
              trailing: const Icon(Icons.menu_book, size: 18, color: Colors.blue),
              onTap: () => setState(() => _pasajeSeleccionado = _pasajesDetectados[index]),
            ),
          );
  }
  
  // MÉTODO DE OPTIMIZACIÓN: Sube los sermones pendientes de forma automática y limpia la caché local
  Future<void> _sincronizarBorradoresLocalesAnube() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> borradoresLocales = prefs.getStringList('borradores_locales') ?? [];
      
      if (borradoresLocales.isEmpty) return; // Si no hay nada pendiente, salimos de inmediato

      final supabaseClient = Supabase.instance.client;
      List<String> borradoresExitosos = [];

      // Recorremos cada sermón que se guardó en el dispositivo durante la desconexión
      for (var borradorRaw in borradoresLocales) {
        final Map<String, dynamic> sermon = jsonDecode(borradorRaw);
        
        // Limpiamos el título para quitar la etiqueta de emergencia de la interfaz
        String tituloReal = sermon['titulo'].toString().replaceAll(' (Sin Sincronizar)', '');

        // Subimos el registro a tu Supabase local o en la nube
        await supabaseClient.from('bosquejos').insert({
          'titulo': tituloReal,
          'contenido_json': sermon['contenido_json'],
        });
        
        borradoresExitosos.add(borradorRaw);
      }

      // Eliminamos del teléfono únicamente los sermones que ya se subieron con éxito a PostgreSQL
      borradoresLocales.removeWhere((elemento) => borradoresExitosos.contains(elemento));
      await prefs.setStringList('borradores_locales', borradoresLocales);

      // Actualizamos la pantalla del pastor para reflejar los cambios
      _cargarHistorial();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 ¡Sincronización automática completada! Tus sermones locales ya están en la nube.'),
            backgroundColor: Colors.indigo,
          )
        );
      }
    } catch (_) {
      // Si la red parpadeó o falló a mitad del proceso, los datos se quedan seguros en el teléfono
    }
  }
}
