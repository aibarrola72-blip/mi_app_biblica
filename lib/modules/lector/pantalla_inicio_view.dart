// lib/modules/home/pantalla_inicio_view.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/ajustes_config.dart';
import '../../database/biblia_db_helper.dart';

class PantallaInicioView extends StatefulWidget {
  final Function(int) onCambiarPestana;

  const PantallaInicioView({super.key, required this.onCambiarPestana});

  @override
  State<PantallaInicioView> createState() => _PantallaInicioViewState();
}

class _PantallaInicioViewState extends State<PantallaInicioView> {
  final AjustesConfig _ajustesGlobales = AjustesConfig();
  final BibliaDatabaseHelper _dbHelper = BibliaDatabaseHelper();
  final _supabase = Supabase.instance.client;

  // Variables de Control de Estado y Analíticas
  bool _cargandoDashboard = true;
  bool _estaOnline = true;
  
  // Punto 1: Hábitos
  int _rachaDias = 0;
  int _totalCapitulosLeidos = 0;
  int _totalVersiculosLeidos = 0;
  
  // Punto 2: Bosquejos
  int _totalSermones = 0;
  String _ultimoSermonTitulo = "Ninguno reciente";
  Map<String, dynamic>? _ultimoSermonObjeto;
  int _atCitasCount = 0;
  int _ntCitasCount = 0;
  
  // Punto 3: Teología
  int _totalLibrosCompletados = 0;
  List<String> _librosFaltantes = [];
  Map<int, int> _conteoColoresResaltados = {
    0xFFFFF59D: 0, // Amarillo Promesas
    0xFFA5D6A7: 0, // Verde Mandamientos
    0xFF9FA8DA: 0, // Azul Doctrinas
    0xFFF48FB1: 0, // Rosa Exhortación
  };

  @override
  void initState() {
    super.initState();
    _ajustesGlobales.cargarAjustes();
    _ajustesGlobales.addListener(() { if (mounted) setState(() {}); });
    _cargarTodoElDashboardPastoral();
  }

  /// 🚀 CENTRALIZADOR ANALÍTICO: Dispara el escaneo multipanel
  Future<void> _cargarTodoElDashboardPastoral() async {
    if (!mounted) return;
    setState(() => _cargandoDashboard = true);

    await _verificarEstadoServidorConectividad();
    await _calcularMetricasDeLecturaYRacha();
    await _analizarEcosistemaDeSermonesYTestamentos();
    await _contarBalanceDeColoresResaltados();

    if (mounted) setState(() => _cargandoDashboard = false);
  }

  Future<void> _verificarEstadoServidorConectividad() async {
    try {
      // Intento ligero de ping HTTP a tu cluster
      await _supabase.from('perfiles_pastor').select('id').limit(1).timeout(const Duration(milliseconds: 1200));
      _estaOnline = true;
    } catch (_) {
      _estaOnline = false;
    }
  }

  Future<void> _calcularMetricasDeLecturaYRacha() async {
    try {
      // Datos del perfil remoto (Racha y Última fecha)
      final perfil = await _supabase.from('perfiles_pastor').select('racha_actual').eq('id', 'unico_pastor').maybeSingle();
      if (perfil != null) {
        _rachaDias = perfil['racha_actual'] ?? 0;
      }

      // Capítulos de la tabla relacional
      final List<dynamic> registros = await _supabase.from('progreso_lectura').select('libro_id, capitulo, versiculos_leidos').eq('usuario_id', 'unico_pastor');
      int versoSuma = 0;
      Map<int, List<int>> capitulosPorLibro = {};

      for (var reg in registros) {
        int libId = reg['libro_id'];
        int cap = reg['capitulo'];
        versoSuma += (reg['versiculos_leidos'] as num).toInt();

        capitulosPorLibro.putIfAbsent(libId, () => []);
        if (!capitulosPorLibro[libId]!.contains(cap)) capitulosPorLibro[libId]!.add(cap);
      }

      int librosTerminados = 0;
      List<String> pendientes = [];

      for (int i = 1; i <= 66; i++) {
        int requeridos = _dbHelper.obtenerTotalCapitulos(i);
        int hechos = capitulosPorLibro[i]?.length ?? 0;
        if (hechos >= requeridos) librosTerminados++; else pendientes.add(_dbHelper.obtenerNombreLibro(i));
      }

      _totalCapitulosLeidos = registros.length;
      _totalVersiculosLeidos = versoSuma;
      _totalLibrosCompletados = librosTerminados;
      _librosFaltantes = pendientes;
    } catch (_) {}
  }

  Future<void> _analizarEcosistemaDeSermonesYTestamentos() async {
    try {
      final List<dynamic> sermones = await _dbHelper.obtenerHistorialBosquejos();
      _totalSermones = sermones.length;
      
      if (sermones.isNotEmpty) {
        _ultimoSermonObjeto = sermones.first;
        _ultimoSermonTitulo = _ultimoSermonObjeto!['titulo'] ?? 'Sin título';
      }

      // Análisis analítico estructural de citas AT vs NT
      int atCount = 0;
      int ntCount = 0;
      final regExp = RegExp(r'\b([1-3]?\s?[A-Z][a-záéíóúÁÉÍÓÚñÑ]+)\s+([0-9]+):([0-9]+)\b');

      for (var s in sermones) {
        String contenidoRaw = s['contenido_json'].toString();
        final matches = regExp.allMatches(contenidoRaw);
        for (var m in matches) {
          int libroId = _dbHelper.obtenerLibroId(m.group(1)!);
          if (libroId > 0 && libroId <= 39) atCount++;
          if (libroId >= 40 && libroId <= 66) ntCount++;
        }
      }
      _atCitasCount = atCount;
      _ntCitasCount = ntCount;
    } catch (_) {}
  }

  Future<void> _contarBalanceDeColoresResaltados() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? resaltadosRaw = prefs.getString('biblioteca_resaltados');
      
      // Reiniciamos contadores
      _conteoColoresResaltados = {0xFFFFF59D: 0, 0xFFA5D6A7: 0, 0xFF9FA8DA: 0, 0xFFF48FB1: 0};

      if (resaltadosRaw != null) {
        final Map<String, dynamic> decoded = jsonDecode(resaltadosRaw);
        for (var valorColor in decoded.values) {
          int colorInt = valorColor as int;
          // Normalizamos el mapeo al espectro de paleta base de 24 bits
          if (_conteoColoresResaltados.containsKey(colorInt)) {
            _conteoColoresResaltados[colorInt] = _conteoColoresResaltados[colorInt]! + 1;
          }
        }
      }
    } catch (_) {}
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
        title: Text('Tablero de Control Pastoral', style: TextStyle(color: colorTextoP, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          // 📡 PUNTO 4: LED Indicador de Red del Servidor
          Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _estaOnline ? Colors.green : Colors.orange,
                  boxShadow: [BoxShadow(color: _estaOnline ? Colors.green.withOpacity(0.4) : Colors.orange.withOpacity(0.4), blurRadius: 4, spreadRadius: 1)],
                ),
              ),
              const SizedBox(width: 6),
              Text(_estaOnline ? 'Cloud' : 'Local Cache', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorTextoS)),
            ],
          ),
          IconButton(icon: const Icon(Icons.sync_rounded), tooltip: 'Sincronizar todo', onPressed: _cargarTodoElDashboardPastoral),
          const SizedBox(width: 8),
        ],
      ),
      body: _cargandoDashboard
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                children: [
                  // 🔥 PUNTO 1: Racha de Días Consecutivos y Banner de Bienvenida
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: esOscuro ? [const Color(0xFF1A237E), const Color(0xFF0D47A1)] : [Colors.blue.shade800, Colors.blue.shade600]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('¡Saludos, siervo de Dios!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Que la gracia de nuestro Señor guíe su estudio el día de hoy.', style: TextStyle(color: Colors.blue.shade100, fontSize: 13)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.local_fire_department_rounded, color: Colors.amber, size: 24),
                              const SizedBox(width: 4),
                              Text('$_rachaDias días', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 📝 PUNTO 2: Acceso Rápido al Último Sermón Modificado
		              Text('Última actividad en el atril', 
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorTextoP)
                  ),
                  const SizedBox(height: 8),InkWell(onTap: () => widget.onCambiarPestana(1), 
                  // Cambia a pestaña Editor
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                    color: colorCard, borderRadius: BorderRadius.circular(14), 
                    border: Border.all(color: esOscuro ? Colors.grey.shade800 : Colors.black12)
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10), 
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), 
                            borderRadius: BorderRadius.circular(10)
                          ), 
                          child: const Icon(
                          Icons.description_rounded, color: Colors.orange)
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_ultimoSermonTitulo, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colorTextoP), 
                                maxLines: 1, overflow: TextOverflow.ellipsis
                              ),
                              const SizedBox(height: 2),
                              Text('Presione para continuar editando este bosquejo', 
                                style: TextStyle(fontSize: 12, color: colorTextoS)
                              ),
                            ],
                          ),
                        ),
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
                          ),
                          separatorBuilder: (context, index) => const Divider(height: 1),
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            );
          }

  Widget _construirBarraProporcionalCitas(Color colorTextoS) {
  int sumaTotal = _atCitasCount + _ntCitasCount;double porcentajeAt = sumaTotal > 0 ? 
  (_atCitasCount / sumaTotal) : 0.5;double porcentajeNt = sumaTotal > 0 ? 
  (_ntCitasCount / sumaTotal) : 0.5;
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
}