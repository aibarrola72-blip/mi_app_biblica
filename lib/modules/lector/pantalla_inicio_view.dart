// lib/modules/home/pantalla_inicio_view.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/ajustes_config.dart';
import '../../database/biblia_db_helper.dart';
import '../../database/auth_service.dart';
import 'splash_screen_view.dart';

class PantallaInicioView extends StatefulWidget {
  final Function(int) onCambiarPestana;

  const PantallaInicioView({super.key, required this.onCambiarPestana});

  @override
  State<PantallaInicioView> createState() => _PantallaInicioViewState();
}

class _PantallaInicioViewState extends State<PantallaInicioView> {
  final AjustesConfig _ajustesGlobales = AjustesConfig();
  final BibliaDatabaseHelper _dbHelper = BibliaDatabaseHelper();
  final AuthService _authService = AuthService();
  final _supabase = Supabase.instance.client;

  // Variables de Perfil de Usuario de Google
  String _nombrePastor = "Pastor";
  String? _urlFotoPerfil;

  // Variables de Control de Estado y Analíticas
  bool _cargandoDashboard = true;
  bool _estaOnline = true;
  
  // Punto 1: Hábitos
  int _rachaDias = 0;
  int _totalCapitulosLeidos = 0;
  int _totalVersiculosLeidos = 0;

  // 🚀 NUEVO: Variables para el Tiempo en el Altar
  int _minutosSemanales = 0;
  int _minutosMensuales = 0;
  
  // Punto 2: Bosquejos
  int _totalSermones = 0;
  String _ultimoSermonTitulo = "Ninguno reciente";
  Map<String, dynamic>? _ultimoSermonObjeto;
  int _atCitasCount = 0;
  int _ntCitasCount = 0;
  
  // Punto 3: Teología
  int _totalLibrosCompletados = 0;
  List<String> _librosFaltantes = [];
  List<Map<String, dynamic>> _topLibrosMasPredicados = [];
  Map<int, int> _conteoColoresResaltados = {
    0xFFFFF59D: 0, // Amarillo Promesas
    0xFFA5D6A7: 0, // Verde Mandamientos
    0xFF9FA8DA: 0, // Azul Doctrinas
    0xFFF48FB1: 0, // Rosa Exhortación
  };

  @override
  void initState() {
    super.initState();
    // 🚀 LA SOLUCIÓN: Escuchamos de forma activa cuando la sesión de Supabase esté lista
  // Esto garantiza que la primera carga nunca ocurra con un ID de usuario vacío.
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final Session? session = data.session;
    if (session != null) {
      // En cuanto la sesión se restaura, cargamos el escritorio con datos reales
      _refrescarDatosDesdeNube(); 
    } else {
      // Si de verdad no hay sesión (usuario deslogueado), apagamos el cargador
      setState(() => _cargandoDashboard = false);
    }
  });
    _ajustesGlobales.cargarAjustes();
    _ajustesGlobales.addListener(() { if (mounted) setState(() {}); });
    _recuperarDatosPerfilGoogle();
    _refrescarDatosDesdeNube();
  }

  /// 🔐 CAPTURA DE METADATOS DE GOOGLE AUTH:
  void _recuperarDatosPerfilGoogle() {
    final usuario = _authService.usuarioActual;
    if (usuario != null && usuario.userMetadata != null) {
      setState(() {
        _nombrePastor = usuario.userMetadata!['full_name'] ?? usuario.userMetadata!['name'] ?? "Pastor";
        _urlFotoPerfil = usuario.userMetadata!['avatar_url'] ?? usuario.userMetadata!['picture'];
      });
    }
  }

  // 🚀 CENTRALIZADOR ANALÍTICO CON INTERCEPCIÓN PULL-TO-REFRESH
  Future<void> _refrescarDatosDesdeNube() async {
    if (!mounted) return;
    setState(() => _cargandoDashboard = true);

    try {
      // 1. Verificar Conectividad Real
      try {
        await _supabase.from('perfiles_pastor').select('id').limit(1).timeout(const Duration(milliseconds: 1000));
        _estaOnline = true;
      } catch (_) { 
        _estaOnline = false; 
      }

      final String usuarioUid = _supabase.auth.currentUser?.id ?? '';

      // 2. Cargar Racha e Historial Devocional Remoto (Sincronizado al Segundo)
      if (_estaOnline && usuarioUid.isNotEmpty) {
        // Traemos el marcador canónico del perfil del pastor
        final perfil = await _supabase.from('perfiles_pastor').select('racha_actual, ultima_fecha_lectura').eq('id', usuarioUid).maybeSingle();
        
        if (perfil != null) {
          _rachaDias = perfil['racha_actual'] ?? 0;
          final String? ultimaFechaRaw = perfil['ultima_fecha_lectura'];

          // 🛡️ SALVAGUARDA DE COLOQUEL DE RACHA DIARIA:
          // Si pasó más de un día desde la última lectura, la racha visual cae a 0 de forma automática hasta que vuelva a leer
          if (ultimaFechaRaw != null && ultimaFechaRaw.isNotEmpty) {
            // Solo intentamos analizar si trae al menos el formato YYYY-MM-DD (10 caracteres)
            final DateTime? fechaUltimaLectura = ultimaFechaRaw.length >= 10
                ? DateTime.tryParse(ultimaFechaRaw.substring(0, 10))
                : null;
            final DateTime hoy = DateTime.now();
            final DateTime hoyLimpio = DateTime(hoy.year, hoy.month, hoy.day);
            
            if (fechaUltimaLectura != null && hoyLimpio.difference(fechaUltimaLectura).inDays > 1) {
              _rachaDias = 0; // La racha expiró por inactividad
            }
          }
        } else {
          _rachaDias = 0;
        }

        // Descargamos la bitácora completa de progreso de lectura
        final List<dynamic> registrosLectura = await _supabase
            .from('progreso_lectura')
            .select('libro_id, capitulo, versiculos_leidos, fecha_lectura')
            .eq('usuario_id', usuarioUid);
        
        int bVersos = 0;
        int capsSemanales = 0;
        int capsMensuales = 0;
        
        // Normalización estricta de tiempos devocionales
        final ahora = DateTime.now();
        final hace7Dias = DateTime(ahora.year, ahora.month, ahora.day).subtract(const Duration(days: 7));
        final hace30Dias = DateTime(ahora.year, ahora.month, ahora.day).subtract(const Duration(days: 30));
        Map<int, List<int>> capitulosPorLibro = {};

        for (var reg in registrosLectura) {
          int libId = reg['libro_id'];
          int cap = reg['capitulo'];
          bVersos += (reg['versiculos_leidos'] as num).toInt();

          if (reg['fecha_lectura'] != null) {
            final DateTime fechaReg = DateTime.parse(reg['fecha_lectura']);
            if (fechaReg.isAfter(hace7Dias)) capsSemanales++;
            if (fechaReg.isAfter(hace30Dias)) capsMensuales++;
          }

          capitulosPorLibro.putIfAbsent(libId, () => []);
          if (!capitulosPorLibro[libId]!.contains(cap)) capitulosPorLibro[libId]!.add(cap);
        }

        int librosTerminados = 0;
        List<String> pendientes = [];
        for (int i = 1; i <= 66; i++) {
          int req = _dbHelper.obtenerTotalCapitulos(i);
          int hechos = capitulosPorLibro[i]?.length ?? 0;
          if (hechos >= req) {
            librosTerminados++;
          } else {
            pendientes.add(_dbHelper.obtenerNombreLibro(i));
          }
        }

        setState(() {
          _totalCapitulosLeidos = registrosLectura.length;
          _totalVersiculosLeidos = bVersos;
          _minutosSemanales = capsSemanales * 4; // 4 minutos promedio estimado por capítulo leídos
          _minutosMensuales = capsMensuales * 4;
          _totalLibrosCompletados = librosTerminados;
          _librosFaltantes = pendientes;
        });
      }

      // 3. Ecosistema Analítico de Bosquejos y Homilética
      final List<dynamic> bosquejos = await _dbHelper.obtenerHistorialBosquejos();
      _totalSermones = bosquejos.length;
      
      if (bosquejos.isNotEmpty) {
        _ultimoSermonObjeto = bosquejos.first;
        _ultimoSermonTitulo = _ultimoSermonObjeto!['titulo'] ?? 'Sin título';
      } else {
        _ultimoSermonObjeto = null;
        _ultimoSermonTitulo = "Ninguno reciente";
      }

      int atCount = 0;
      int ntCount = 0;
      Map<int, int> mapaFrecuenciaLibros = {};
      final RegExp regExp = RegExp(r'([1-3]?\s?[A-Z][a-záéíóúÁÉÍÓÚñÑ]+)\s+([0-9]+)\s*:\s*([0-9]+)');

      for (var b in bosquejos) {
        String contenidoRaw = b['contenido_json'].toString();
        String tituloRaw = b['titulo'].toString();
        final String textoLimpio = '$tituloRaw $contenidoRaw'.replaceAll(RegExp(r'[\{\}\[\]\(\)\"\,\\]'), ' ');

        final matches = regExp.allMatches(textoLimpio);
        for (var m in matches) {
          final String nombreLibroDetectado = m.group(1)!.trim();
          int libroId = _dbHelper.obtenerLibroId(nombreLibroDetectado);
          if (libroId > 0) {
            if (libroId <= 39) {
              atCount++;
            } else {
              ntCount++;
            }
            mapaFrecuenciaLibros[libroId] = (mapaFrecuenciaLibros[libroId] ?? 0) + 1;
          }
        }
      }

      // 4. Conteo e Indexación de Resaltados Teológicos (Móvil / Web)
      Map<String, dynamic> decodedResaltados = {};
      
      if (_estaOnline && usuarioUid.isNotEmpty) {
        decodedResaltados = await _dbHelper.descargarResaltadosDeNube();
      } 
      
      if (decodedResaltados.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final String? resaltadosRaw = prefs.getString('biblioteca_resaltados');
        if (resaltadosRaw != null) {
          decodedResaltados = jsonDecode(resaltadosRaw);
        }
      }

      _conteoColoresResaltados = {0xFFFFF59D: 0, 0xFFA5D6A7: 0, 0xFF9FA8DA: 0, 0xFFF48FB1: 0};

      for (var valorColor in decodedResaltados.values) {
        int colorInt = valorColor as int;
        if (colorInt == Colors.yellow.value || colorInt == 0xFFFFF59D) _conteoColoresResaltados[0xFFFFF59D] = _conteoColoresResaltados[0xFFFFF59D]! + 1;
        if (colorInt == Colors.green.value || colorInt == 0xFFA5D6A7) _conteoColoresResaltados[0xFFA5D6A7] = _conteoColoresResaltados[0xFFA5D6A7]! + 1;
        if (colorInt == Colors.blue.value || colorInt == 0xFF9FA8DA) _conteoColoresResaltados[0xFF9FA8DA] = _conteoColoresResaltados[0xFF9FA8DA]! + 1;
        if (colorInt == Colors.pink.value || colorInt == 0xFFF48FB1) _conteoColoresResaltados[0xFFF48FB1] = _conteoColoresResaltados[0xFFF48FB1]! + 1;
      }

      if (_estaOnline && decodedResaltados.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('biblioteca_resaltados', jsonEncode(decodedResaltados));
      }

      setState(() {
        _atCitasCount = atCount;
        _ntCitasCount = ntCount;

        var listaOrdenadaLibros = mapaFrecuenciaLibros.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        
        _topLibrosMasPredicados = listaOrdenadaLibros.take(3).map((e) => {
          'nombre': _dbHelper.obtenerNombreLibro(e.key),
          'citas': e.value
        }).toList();
      });

    } catch (e) { 
      print("Error cargando dashboard unificado: $e"); 
    }

    if (mounted) setState(() => _cargandoDashboard = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool esOscuro = _ajustesGlobales.modoOscuroLectura;
    final Color colorFondo = esOscuro ? const Color(0xFF121212) : const Color(0xFFF6F8FA);
    final Color colorCard = esOscuro ? const Color(0xFF1E1E1E) : Colors.white;
    final Color colorTextoP = esOscuro ? Colors.white : const Color(0xFF24292F);
    final Color colorTextoS = esOscuro ? Colors.grey.shade400 : const Color(0xFF57606A);

    return Scaffold(
      
      backgroundColor: colorFondo,
      appBar: AppBar(
        backgroundColor: colorCard,
        elevation: 0.5,
        title: Text('Escritorio de estudio', style: TextStyle(color: colorTextoP, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          
          IconButton(
            icon: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent, size: 22),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await _authService.cerrarSesion();
              if (mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SplashScreenView()));
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
      color: const Color(0xFF1A73E8),       // Color azul para el círculo de carga
      backgroundColor: colorCard,           // Color de fondo del círculo
      onRefresh: _refrescarDatosDesdeNube,  // Ejecuta la función unificada que modificamos antes
      
      child: _cargandoDashboard
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(), // Obligatorio para Web
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                children: [
                  // 📡 PUNTO 4: LED Indicador de Red del Servidor
                  Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _estaOnline ? Colors.green : Colors.orange,
                          boxShadow: [BoxShadow(color: _estaOnline ? Colors.green.withValues(alpha: 0.4) : Colors.orange.withValues(alpha: 0.4), blurRadius: 4, spreadRadius: 1)],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(_estaOnline ? 'Sincronizado' : 'Offline', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorTextoS)),
                    ],
                  ),
                  // 🔥 PUNTO 1: Racha de Días Consecutivos y Banner de Bienvenida
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: esOscuro ? [const Color(0xFF1A237E), const Color(0xFF0D47A1)] : [Colors.blue.shade800, Colors.blue.shade600]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        // Foto de Perfil Circular de Google Auth o Inicial por defecto
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.white,
                          backgroundImage: _urlFotoPerfil != null ? NetworkImage(_urlFotoPerfil!) : null,
                          child: _urlFotoPerfil == null 
                              ? Icon(Icons.person_rounded, size: 28, color: Colors.blue.shade800) 
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('¡Paz, $_nombrePastor!', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text('Que la unción del Espíritu Santo guíe su bosquejo.', style: TextStyle(color: Colors.blue.shade100, fontSize: 13)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            children: [
                              const Icon(Icons.local_fire_department_rounded, color: Colors.amber, size: 20),
                              const SizedBox(width: 3),
                              Text('$_rachaDias días', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 🚀 NUEVA TARJETA: Minutos Invertidos en el Altar (Hábitos Devocionales)
                  Text('Tiempo Invertido en el Altar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorTextoP)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: colorCard, borderRadius: BorderRadius.circular(14), 
                      border: Border.all(color: esOscuro ? Colors.grey.shade800 : Colors.black12)
                    ),
                    child: Row(
                      children: [                          
                        _construirItemMinutos('Esta Semana', '$_minutosSemanales', 'min', Colors.blue.shade600, colorTextoP ,colorTextoS),
                            Container(width: 1, height: 45, color: esOscuro ? Colors.grey.shade800 : Colors.grey.shade200),
                        _construirItemMinutos('Este Mes', '$_minutosMensuales', 'min', Colors.teal.shade600, colorTextoP ,colorTextoS),                  
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 📝 PUNTO 2: Acceso Rápido al Último Sermón Modificado
                  Text(
                    'Última actividad en el atril', 
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorTextoP),
                  ),
                  Text('Total: $_totalSermones', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorTextoS)),
                  const SizedBox(height: 8),

                  InkWell(
                    // Si no hay sermón, el botón se deshabilita automáticamente
                    onTap: _ultimoSermonObjeto == null ? null : () {
                      _dbHelper.sermonEnTransito = _ultimoSermonObjeto!;
                      widget.onCambiarPestana(1); // Mover al Editor
                    }, 
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorCard, 
                        borderRadius: BorderRadius.circular(14), 
                        border: Border.all(color: esOscuro ? Colors.grey.shade800 : Colors.black12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10), 
                            decoration: BoxDecoration(
                              color: (_ultimoSermonObjeto == null ? Colors.grey : Colors.orange).withOpacity(0.12), 
                              borderRadius: BorderRadius.circular(10),
                            ), 
                            child: Icon(
                              Icons.description_rounded, 
                              color: _ultimoSermonObjeto == null ? Colors.grey : Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _ultimoSermonObjeto == null ? 'No hay sermones guardados' : _ultimoSermonTitulo, 
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colorTextoP), 
                                  maxLines: 1, 
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _ultimoSermonObjeto == null 
                                      ? 'Crea un sermón nuevo en el editor' 
                                      : 'Presione para cargar este bosquejo en el atril', 
                                  style: TextStyle(fontSize: 12, color: colorTextoS),
                                ),
                              ],
                            ),
                          ),
                          if (_ultimoSermonObjeto != null)
                            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                    // 📊 PUNTO 2 (B): Gráfico de Balance Doctrinal por Testamento
                    Container(
                    padding: const EdgeInsets.all(16),decoration: BoxDecoration(color: colorCard, borderRadius: BorderRadius.circular(14), 
                    border: Border.all(color: esOscuro ? Colors.grey.shade800 : Colors.black12)),
                    child: Column(
                    crossAxisAlignment: 
                    CrossAxisAlignment.start,
                    children: [
                    Text('Balance Doctrinal de Predicación', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: colorTextoP)),
                    const SizedBox(height: 4),
                    Text('Distribución de citas bíblicas indexadas en sus bosquejos', style: TextStyle(fontSize: 12, color: colorTextoS)),
                    const SizedBox(height: 14),
                    _construirBarraProporcionalCitas(colorTextoS),
                    ],
                    ),
                    ),
                    const SizedBox(height: 16),

                    // 📊 3. SECCIÓN VISUAL DE LAS BARRAS PROPORCIONALES (TOP 3)
                    // Invocamos el método modularizado pasando las variables de diseño de tu build
                    _construirSeccionTopLibros(colorCard, esOscuro, colorTextoP, colorTextoS),

                    const SizedBox(height: 16),

                    // 🎨 PUNTO 3: Balance Temático de Versículos Pintados por Color
                    Text('Profundidad de su Estudio Teológico', 
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorTextoP)
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: colorCard, borderRadius: BorderRadius.circular(14), 
                        border: Border.all(color: esOscuro ? Colors.grey.shade800 : Colors.black12)
                      ),
                      child: 
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _bloqueColorIndicador(Colors.yellow.shade200, 
                          _conteoColoresResaltados[0xFFFFF59D] ?? 0, 'Promesas'),
                          _bloqueColorIndicador(Colors.green.shade200, 
                          _conteoColoresResaltados[0xFFA5D6A7] ?? 0, 'Mandatos'),
                          _bloqueColorIndicador(Colors.blue.shade200, 
                          _conteoColoresResaltados[0xFF9FA8DA] ?? 0, 'Doctrinas'),
                          _bloqueColorIndicador(Colors.pink.shade200, 
                          _conteoColoresResaltados[0xFFF48FB1] ?? 0, 'Consejos'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sección Base de Progreso Canónico Existente
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: colorCard, borderRadius: BorderRadius.circular(14), 
                        border: Border.all(color: esOscuro ? Colors.grey.shade800 : Colors.black12)
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Meta de Lectura Bíblica General', 
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: colorTextoP)),
                              Text('$_totalCapitulosLeidos / 1189 Caps', 
                                style: TextStyle(fontSize: 12, color: colorTextoS, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: (_totalCapitulosLeidos / 1189).clamp(0.0, 1.0),
                            backgroundColor: esOscuro ? Colors.grey.shade800 : Colors.grey.shade200,
                            color: Colors.blue.shade600,minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Libros Completados: $_totalLibrosCompletados / 66', 
                                style: TextStyle(fontSize: 12, color: colorTextoS)),
                              Text('Versículos Leídos: $_totalVersiculosLeidos', 
                                style: TextStyle(fontSize: 12, color: colorTextoS, fontWeight: FontWeight.bold)
                              ),
                            ],
                          )
                        ],
                      ),
                  ),
                    if (_totalLibrosCompletados < 66) ...[
                      const SizedBox(height: 16),
                      Text('Libros que faltan leer (${_librosFaltantes.length})', 
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorTextoP)
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 180,decoration: BoxDecoration(
                          color: colorCard, borderRadius: BorderRadius.circular(14), 
                          border: Border.all(color: esOscuro ? Colors.grey.shade800 : Colors.black12)
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          itemCount: _librosFaltantes.length,
                          itemBuilder: (context, idx) => ListTile(
                            dense: true,contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.bookmark_border_rounded, color: Colors.blue, size: 16),
                            title: Text(_librosFaltantes[idx], 
                              style: TextStyle(color: colorTextoP, fontSize: 13, fontWeight: FontWeight.w500)
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey),
                            onTap: () => widget.onCambiarPestana(2),
                          ),
                          separatorBuilder: (context, index) => const Divider(height: 1),
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            )
    );
  }
  
  // 🚀 WIDGET AUXILIAR: Construye la celda analítica de tiempo con métrica de sufijo chico
  Widget _construirItemMinutos(String label, String valor, String sufijo, Color coloricon, Color colorTxP, Color colorTxS) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_top_rounded, size: 16, color: coloricon),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colorTxS)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorTxP),),
              const SizedBox(width: 2),
              Text(sufijo, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorTxS),),
            ],            
          ),
        ],
      ),
    );
  }

  Widget _construirBarraProporcionalCitas(Color colorTextoS) {
    int sumaTotal = _atCitasCount + _ntCitasCount;
    double porcentajeAt = sumaTotal > 0 ? (_atCitasCount / sumaTotal) : 0.5;
    double porcentajeNt = sumaTotal > 0 ? (_ntCitasCount / sumaTotal) : 0.5;
    
    return Column(
      children: [
        Row(
          children: [
            if (porcentajeAt > 0) 
            Expanded(
                flex: (porcentajeAt * 100).toInt(), 
                child:        
                Container(
                  height: 8, 
                  decoration: const BoxDecoration(color: Colors.brown, 
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(4), bottomLeft: Radius.circular(4))
                  )
                )
              ),
              if (porcentajeNt > 0) Expanded(flex: (porcentajeNt * 100).toInt(), 
              child: 
              Container(
                height: 8, 
                decoration: BoxDecoration(color: Colors.teal.shade600, 
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(4), bottomRight: Radius.circular(4)
                  )
                )
              )
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8, height: 8, decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.brown
                  )
                ), 
                const SizedBox(width: 4), 
                Text('A. Testamento: $_atCitasCount citas (${(porcentajeAt * 100).toStringAsFixed(0)}%)', 
                  style: TextStyle(fontSize: 11, color: colorTextoS)
                )
              ]
            ),
            Row(
              children: [
                Container(width: 8, height: 8, 
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.teal.shade600)
                ), 
                const SizedBox(width: 4), 
                Text('N. Testamento: $_ntCitasCount citas (${(porcentajeNt * 100).toStringAsFixed(0)}%)', 
                  style: TextStyle(fontSize: 11, color: colorTextoS)
                )
              ]
            ),
          ],
        )
      ],
    );
  }

  Widget _bloqueColorIndicador(Color colorFondo, int cantidad, String etiqueta) {
    return Column(
      children: [
        Container(
          width: 40, height: 35,
          decoration: BoxDecoration(color: colorFondo, borderRadius: BorderRadius.circular(8), 
            border: Border.all(color: Colors.black12)
          ),
          child: Center(
            child: 
            Text('$cantidad', 
              style: const TextStyle(fontWeight: FontWeight.bold, 
                fontSize: 14, color: Colors.black87
              )
            )
          ),
        ),
        const SizedBox(height: 4),
        Text(etiqueta, style: const TextStyle(fontSize: 11, 
          fontWeight: FontWeight.w500, color: Colors.grey)
        ),
      ],
    );
  }

  Widget _construirSeccionTopLibros(Color colorCard, bool esOscuro, Color colorTextoP, Color colorTextoS) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorCard, 
        borderRadius: BorderRadius.circular(14), 
        border: Border.all(color: esOscuro ? Colors.grey.shade800 : Colors.black12),
      ),
      child: _topLibrosMasPredicados.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'Redacte sermones con citas para activar el motor analítico...', 
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                // Conseguimos la cifra del libro número 1 como base máxima para las proporciones
                final int maxCitas = _topLibrosMasPredicados.first['citas'] ?? 1;
                
                // 🌐 ADAPTACIÓN WEB: Si la pantalla mide más de 600px, reducimos el factor 
                // de la barra a 0.40 para que en monitores de PC mantenga una escala elegante.
                final double factorAncho = constraints.maxWidth > 600 ? 0.40 : 0.55;
                final double anchoMaximoBarra = constraints.maxWidth * factorAncho; 

                return Column(
                  children: List.generate(_topLibrosMasPredicados.length, (index) {
                    final libro = _topLibrosMasPredicados[index];
                    final int citasActuales = libro['citas'] ?? 0;
                    
                    // Cálculo matemático de la proporción (Regla de tres simple)
                    final double factorProporcional = maxCitas > 0 ? (citasActuales / maxCitas) : 0.0;
                    final double anchoCalculado = anchoMaximoBarra * factorProporcional;

                    // Paleta de colores degradada según el podio
                    final Color colorBarra = index == 0 
                        ? const Color(0xFF1A73E8) // Azul Rey
                        : index == 1 
                            ? Colors.teal.shade400  // Teal
                            : Colors.blueGrey.shade400; // Gris azulado

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(                              
                        children: [
                          CircleAvatar(
                            radius: 11, 
                            backgroundColor: colorBarra.withOpacity(0.12), 
                            child: Text(
                              '${index + 1}', 
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorBarra),
                            ),
                          ),
                          const SizedBox(width: 12),                                          
                          Expanded(
                            child: Text(
                              '${libro['nombre']}', 
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorTextoP),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          
                          // 📊 BARRA DE PROGRESO PROPORCIONAL MULTIPLATAFORMA
                          Container(
                            height: 8,
                            width: anchoCalculado < 8 ? 8 : anchoCalculado,
                            decoration: BoxDecoration(
                              color: colorBarra,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          
                          // Contador numérico de referencias
                          SizedBox(
                            width: 90,
                            child: Text(
                              '$citasActuales ${citasActuales == 1 ? 'referencia' : 'referencias'}', 
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorTextoS),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                );
              },
            ),
    );
  }
}