// lib/database/canal_eventos.dart

import 'dart:async';

class CanalEventos {
  static final CanalEventos _instancia = CanalEventos._interno();
  factory CanalEventos() => _instancia;
  CanalEventos._interno();

  // El Stream ahora transporta únicamente un String (la cita bíblica)
  final _controladorCitas = StreamController<String>.broadcast();

  Stream<String> get alRecibirCita => _controladorCitas.stream;

  // 🚀 NUEVO CANAL: Transmite un mapa con el bosquejo completo seleccionado
  final _controladorCargarSermonCompleto = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get streamCargarSermon => _controladorCargarSermonCompleto.stream;


  // Transmitir solo la cita hacia el editor
  void enviarCitaAlEditor(String cita) {
    _controladorCitas.add(cita);
  }

  // Transmitir el bosquejo completo hacia el editor
  void enviarBosquejoCompleto(Map<String, dynamic> datosSermon) {
    _controladorCargarSermonCompleto.add(datosSermon);
  }
}
