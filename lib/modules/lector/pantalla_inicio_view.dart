// lib/modules/home/pantalla_inicio_view.dart

import 'package:flutter/material.dart';
import '../../database/ajustes_config.dart';
import '../bosquejos/vista_editor.dart';
import '../lector/visor_biblia_libro.dart';
import '../lector/repasador_resaltados_view.dart';
import '../lector/panel_ajustes_view.dart';

class PantallaInicioView extends StatefulWidget {
  const PantallaInicioView({super.key});

  @override
  State<PantallaInicioView> createState() => _PantallaInicioViewState();
}

class _PantallaInicioViewState extends State<PantallaInicioView> {
  final AjustesConfig _ajustesGlobales = AjustesConfig();

  @override
  void initState() {
    super.initState();
    _ajustesGlobales.cargarAjustes();
    _ajustesGlobales.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool esOscuro = _ajustesGlobales.modoOscuroLectura;
    
    // Paletas unificadas de diseño adaptable
    final Color colorFondo = esOscuro ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final Color colorAppBar = esOscuro ? const Color(0xFF1E1E1E) : Colors.white;
    final Color colorTextoPrimario = esOscuro ? Colors.white : const Color(0xFF202124);
    final Color colorTextoSecundario = esOscuro ? Colors.grey.shade400 : const Color(0xFF5F6368);

    return Scaffold(
      backgroundColor: colorFondo,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        elevation: 0.5,
        centerTitle: false,
        title: Row(
          children: [
            Icon(Icons.auto_stories_rounded, color: Colors.blue.shade600, size: 28),
            const SizedBox(width: 12),
            Text(
              'Biblioteca Pastoral',
              style: TextStyle(color: colorTextoPrimario, fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              esOscuro ? Icons.wb_sunny_rounded : Icons.nightlight_round,
              color: esOscuro ? Colors.amber : Colors.blueGrey,
            ),
            onPressed: () => _ajustesGlobales.cambiarModoOscuroLectura(!esOscuro),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                builder: (context) => PanelAjustesView(ajustes: _ajustesGlobales),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Si el ancho supera los 700px (Tablets/PCs), dibujamos una rejilla de 2 columnas; si no, 1 sola.
          final int columnas = constraints.maxWidth > 700 ? 2 : 1;
          
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner de Bienvenida o Introducción Pastoral
                Text(
                  '¡Bienvenido a su escritorio de estudio!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorTextoPrimario),
                ),
                const SizedBox(height: 6),
                Text(
                  'Centralice sus sermones, referencias relacionales y lecturas bíblicas en un solo ecosistema integrado.',
                  style: TextStyle(fontSize: 14, color: colorTextoSecundario),
                ),
                const SizedBox(height: 28),

                // Rejilla Dinámica Adaptable de Servicios
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: columnas,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: columnas == 2 ? 1.6 : 1.45,
                  children: [
                    _construirTarjetaModulo(
                      context: context,
                      titulo: 'Editor de Bosquejos',
                      descripcion: 'Redacte sermones de forma fluida. Cuenta con escaneo automático de citas bíblicas por RegEx y dictado por voz para flujos rápidos.',
                      icono: Icons.edit_note_rounded,
                      colorIcono: Colors.blue,
                      esOscuro: esOscuro,
                      destino: const VistaEditorBosquejo(),
                    ),
                    _construirTarjetaModulo(
                      context: context,
                      titulo: 'Modo Lectura Completa',
                      descripcion: 'Explore la Biblia sin distracciones. Incluye salto rápido por cuadrícula, conector de cadenas cruzadas y prevención de apagado de pantalla en el púlpito.',
                      icono: Icons.menu_book_rounded,
                      colorIcono: Colors.indigo,
                      esOscuro: esOscuro,
                      destino: const VisorBibliaLibro(),
                    ),
                    _construirTarjetaModulo(
                      context: context,
                      titulo: 'Marcas y Notas de Estudio',
                      descripcion: 'Consulte y repase toda su biblioteca de versículos sombreados en lote. Filtre por tonalidades para estructurar tópicos doctrinales.',
                      icono: Icons.bookmark_added_rounded,
                      colorIcono: Colors.amber,
                      esOscuro: esOscuro,
                      destino: const RepasadorResaltadosView(),
                    ),
                    _construirTarjetaModulo(
                      context: context,
                      titulo: 'Ajustes de Sincronización',
                      descripcion: 'Personalice tipografías (Serif, Sans), tamaños base e interlineados proporcionales. Gestione la base de datos e inyecciones locales.',
                      icono: Icons.settings_suggest_rounded,
                      colorIcono: Colors.teal,
                      esOscuro: esOscuro,
                      onTapEspecial: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                          builder: (context) => PanelAjustesView(ajustes: _ajustesGlobales),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Widget Interno Modularizado para Diseñar las Tarjetas con Efecto Premium
  Widget _construirTarjetaModulo({
    required BuildContext context,
    required String titulo,
    required String descripcion,
    required IconData icono,
    required Color colorIcono,
    required bool esOscuro,
    Widget? destino,
    VoidCallback? onTapEspecial,
  }) {
    final Color fondoCard = esOscuro ? const Color(0xFF1E1E1E) : Colors.white;
    final Color colorBorde = esOscuro ? Colors.grey.shade800 : Colors.grey.shade200;
    final Color colorTextoT = esOscuro ? Colors.white : const Color(0xFF202124);
    final Color colorTextoD = esOscuro ? Colors.grey.shade400 : const Color(0xFF5F6368);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTapEspecial ?? () {
        if (destino != null) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => destino));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(18.0),
        decoration: BoxDecoration(
          color: fondoCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorBorde, width: 1),
          boxShadow: [
            BoxShadow(
              color: esOscuro ? Colors.transparent : Colors.black.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila de encabezado interno de la tarjeta
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorIcono.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icono, color: colorIcono, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    titulo,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorTextoT),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: colorTextoD.withOpacity(0.5)),
              ],
            ),
            const SizedBox(height: 12),
            
            // Cuerpo descriptivo detallado de las funciones internas del módulo
            Expanded(
              child: Text(
                descripcion,
                style: TextStyle(fontSize: 13, color: colorTextoD, height: 1.4),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
