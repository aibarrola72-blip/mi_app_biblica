// lib/database/canal_eventos.dart

import 'dart:async';

class CanalEventos {
  static final CanalEventos _instancia = CanalEventos._interno();
  factory CanalEventos() => _instancia;
  CanalEventos._interno();

  // El Stream ahora transporta únicamente un String (la cita bíblica)
  final _controladorCitas = StreamController<String>.broadcast();

  Stream<String> get alRecibirCita => _controladorCitas.stream;

  // Transmitir solo la cita hacia el editor
  void enviarCitaAlEditor(String cita) {
    _controladorCitas.add(cita);
  }
}
