// lib/modules/home/controlador_navegacion.dart

import 'package:flutter/material.dart';
import '../../database/ajustes_config.dart';
import '../lector/pantalla_inicio_view.dart';
import '../bosquejos/vista_editor.dart';
import '../lector/visor_biblia_libro.dart';
import '../lector/panel_busqueda_global.dart';
import '../../database/pasaje_biblico_model.dart';

class ControladorNavegacion extends StatefulWidget {
  const ControladorNavegacion({super.key});

  @override
  State<ControladorNavegacion> createState() => _ControladorNavegacionState();
}

class _ControladorNavegacionState extends State<ControladorNavegacion> {
  int _indiceSeleccionado = 0;
  final AjustesConfig _ajustesGlobales = AjustesConfig();

  // Controladores de estado persistentes compartidos en memoria
  PasajeBiblico? _pasajeMapeadoLector;

  // 🚀 ARQUITECTURA DE INDIZACIÓN: Mantiene vivas las pantallas en segundo plano
  late final List<Widget> _pantallas;

  @override
  void initState() {
    super.initState();
    _ajustesGlobales.cargarAjustes();
    _ajustesGlobales.addListener(() {
      if (mounted) setState(() {});
    });

    // Inicializamos el pool de aplicaciones fijas
    _pantallas = [
      // Pestaña 0: Inicio Centro de Mandos (Le pasamos una función callback para cambiar de pestaña)
      PantallaInicioView(onCambiarPestana: _saltarAPestana),
      
      // Pestaña 1: Editor de Bosquejos Profesional Quill
      const VistaEditorBosquejo(),
      
      // Pestaña 2: Lector Bíblico Libro Completo
      const VisorBibliaLibro(),
      
      // Pestaña 3: Buscador Global Concordancia
      PanelBusquedaGlobal(
        onPasajeSeleccionado: (pasaje) {
          // Tu BibliaDatabaseHelper guardará de forma automática el rastro.
          // Al tocar un versículo del buscador, la barra cambia a la pestaña del Lector (Pestaña 2)
          _saltarAPestana(2);
        },
      ),
    ];
  }

  void _saltarAPestana(int indice) {
    setState(() {
      _indiceSeleccionado = indice;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool esOscuro = _ajustesGlobales.modoOscuroLectura;

    return Scaffold(
      // IndexedStack: Evita que las vistas se destruyan o recarguen al cambiar de pestaña. 
      // El cursor del editor y la posición de lectura de la Biblia se quedan exactamente donde los dejaste.
      body: IndexedStack(
        index: _indiceSeleccionado,
        children: _pantallas,
      ),
      
      // 🛠️ BARRA DE MENÚ INFERIOR UNIFICADA (Material Design 3 Adaptivo)
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indiceSeleccionado,
        onDestinationSelected: _saltarAPestana,
        backgroundColor: esOscuro ? const Color(0xFF1E1E1E) : Colors.white,
        indicatorColor: Colors.blue.withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_rounded),
            selectedIcon: Icon(Icons.home_rounded, color: Colors.blue),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_rounded),
            selectedIcon: Icon(Icons.edit_note_rounded, color: Colors.blue),
            label: 'Editor',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_rounded),
            selectedIcon: Icon(Icons.menu_book_rounded, color: Colors.blue),
            label: 'Lector',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded, color: Colors.blue),
            label: 'Buscador',
          ),
        ],
      ),
    );
  }
}