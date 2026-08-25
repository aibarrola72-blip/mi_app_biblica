import 'package:flutter/material.dart';
import '../../database/biblia_db_helper.dart';
// import '../bosquejos/vista_editor.dart';
import 'package:mi_app_biblica/database/pasaje_biblico_model.dart';


class VistaLectorBiblia extends StatefulWidget {
  final PasajeBiblico pasaje;
  final ValueChanged<PasajeBiblico>? onPasajeCambiado;

  const VistaLectorBiblia({super.key, required this.pasaje, this.onPasajeCambiado});

  @override
  State<VistaLectorBiblia> createState() => _VistaLectorBibliaState();
}

class _VistaLectorBibliaState extends State<VistaLectorBiblia> {
  final BibliaDatabaseHelper _dbHelper = BibliaDatabaseHelper();
  // OPTIMIZACIÓN: Controlador de scroll para posicionar automáticamente el texto sagrado
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _versiculos = [];
  List<Map<String, dynamic>> _referencias = [];
  bool _cargando = true;
  
  // Guardamos el libro y capítulo actuales para saber si realmente hay que recargar todo o solo mover el scroll
  int? _ultimoLibroId;
  int? _ultimoCapitulo;

  @override
  void initState() {
    super.initState();
    _cargarTextoBiblico();
  }

  @override
  void didUpdateWidget(covariant VistaLectorBiblia oldWidget) {
    super.didUpdateWidget(oldWidget);
    // OPTIMIZACIÓN: Solo disparamos la recarga estructural si el libro o el capítulo cambiaron.
    if (oldWidget.pasaje.libroId != widget.pasaje.libroId || 
        oldWidget.pasaje.capitulo != widget.pasaje.capitulo || 
        oldWidget.pasaje.versiculo != widget.pasaje.versiculo) {
      _cargarTextoBiblico();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose(); // Liberar memoria del controlador de scroll
    super.dispose();
  }

  void _cargarTextoBiblico() async {
    final mismoCapitulo = _ultimoLibroId == widget.pasaje.libroId && _ultimoCapitulo == widget.pasaje.capitulo;

    if (!mismoCapitulo) {
      if (mounted) setState(() => _cargando = true);
    }

    // OPTIMIZACIÓN CONCURRENTE: Disparar ambas consultas en paralelo para reducir el tiempo a la mitad
    final resultados = await Future.wait([
      _dbHelper.obtenerCapitulo(widget.pasaje.libroId, widget.pasaje.capitulo),
      _dbHelper.obtenerReferenciasCruzadas(widget.pasaje.libroId, widget.pasaje.capitulo, widget.pasaje.versiculo),
    ]);

    // MEDIDA DE SEGURIDAD: Evita fugas de memoria o errores fatales si el widget se destruyó en el proceso asíncrono
    if (!mounted) return;

    setState(() {
      _versiculos = resultados[0];
      _referencias = resultados[1];
      _cargando = false;
      _ultimoLibroId = widget.pasaje.libroId;
      _ultimoCapitulo = widget.pasaje.capitulo;
    });

    // Desplazamiento automático al versículo seleccionado tras el redibujo de la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) => _hacerScrollAlVersiculo());
  }

  void _hacerScrollAlVersiculo() {
    if (_versiculos.isEmpty || !_scrollController.hasClients) return;
    
    // Buscar la posición del versículo en la lista
    final index = _versiculos.indexWhere((v) => v['versiculo'] == widget.pasaje.versiculo);
    if (index != -1) {
      // Estimación aproximada de altura por elemento para un scroll fluido sin saltos bruscos
      final posicionDestino = index * 42.0; 
      final maxScroll = _scrollController.position.maxScrollExtent;
      
      _scrollController.animateTo(
        posicionDestino.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Al utilizar nuestro mapa estático indexado, la conversión de ID a Texto toma 0ms
    String nombreLibro = _dbHelper.obtenerNombreLibro(widget.pasaje.libroId);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$nombreLibro ${widget.pasaje.capitulo}', 
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A73E8)),
          ),
          const Divider(),
          if (_cargando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            Expanded(
              flex: 6,
              // OPTIMIZACIÓN: ListView con scroll dinámico asignado
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _versiculos.length,
                itemBuilder: (context, index) {
                  final v = _versiculos[index];
                  bool esResaltado = widget.pasaje.versiculo == v['versiculo'];
                  
                  return GestureDetector(
                    // 🚀 INTERACCIÓN EN EL PÚLPITO / ESTUDIO:
                    // Al dejar presionado el versículo, abre la comparación de versiones
                    onLongPress: () => _mostrarComparativaVersiones(
                      widget.pasaje.libroId, 
                      widget.pasaje.capitulo, 
                      v['versiculo'],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 16, color: Colors.black87, height: 1.4),
                          children: [
                            TextSpan(text: '${v['versiculo']} ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                            TextSpan(
                              text: v['texto'] ?? '', 
                              style: TextStyle(backgroundColor: esResaltado ? Colors.yellow.withOpacity(0.4) : Colors.transparent),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_referencias.isNotEmpty) ...[
              const Divider(),
              const Text('🔗 Textos Relacionados (TSK):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              const SizedBox(height: 4),
              Expanded(
                flex: 4,
                child: ListView.builder(
                  itemCount: _referencias.length,
                  itemBuilder: (context, index) {
                    final ref = _referencias[index];
                    int destLibro = ref['destino_libro_id'] ?? 43;
                    int destCap = ref['destino_capitulo'] ?? 1;
                    int destVer = ref['destino_versiculo'] ?? 1;
                    String nombreDest = _dbHelper.obtenerNombreLibro(destLibro);

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.menu_book, size: 16, color: Colors.orange),
                        title: Text('$nombreDest $destCap:$destVer'),
                        trailing: const Icon(Icons.arrow_forward, size: 14),
                        onTap: () {
                          if (widget.onPasajeCambiado != null) {
                            widget.onPasajeCambiado!(PasajeBiblico(
                              libroId: destLibro,
                              capitulo: destCap,
                              versiculo: destVer,
                              textoOriginal: '$nombreDest $destCap:$destVer',
                            ));
                          }
                        },
                      ),
                    );
                  },
                ),
              )
            ]
          ]
        ],
      ),
    );
  }
    void _mostrarComparativaVersiones(int libroId, int capitulo, int versiculo) {
    String nombreLibro = _dbHelper.obtenerNombreLibro(libroId);

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
                'Comparando: $nombreLibro $capitulo:$versiculo',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _dbHelper.compararVersiculoEnVersiones(libroId, capitulo, versiculo),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text('No hay otras versiones disponibles para este texto.'));
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
                              // Etiqueta de la versión (NVI, RV1960, etc.)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  comp['version_id'] ?? 'RV1960',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue),
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Texto bíblico traducido
                              Text(
                                comp['texto'] ?? '',
                                style: const TextStyle(fontSize: 15, color: Colors.black87),
                              ),
                              const Divider(color: Colors.black12),
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
}
