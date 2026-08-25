// lib/database/ajustes_config.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AjustesConfig extends ChangeNotifier {
  String _tipoLetra = 'sans-serif';
  double _tamanoLetra = 18.0;
  int _colorFondoHex = 0xFFFFFFFF;
  bool _modoOscuroLectura = false;

  String get tipoLetra => _tipoLetra;
  double get tamanoLetra => _tamanoLetra;
  int get colorFondoHex => _colorFondoHex;
  bool get modoOscuroLectura => _modoOscuroLectura;

  final _supabase = Supabase.instance.client;

  // Carga inicial híbrida: Lee el disco y de inmediato escucha si la nube tiene actualizaciones
  Future<void> cargarAjustes() async {
    final prefs = await SharedPreferences.getInstance();
    _tipoLetra = prefs.getString('pref_tipo_letra') ?? 'sans-serif';
    _tamanoLetra = prefs.getDouble('pref_tamano_letra') ?? 18.0;
    _colorFondoHex = prefs.getInt('pref_color_fondo') ?? 0xFFFFFFFF;
    notifyListeners();
    // 🚀 RECOBRAR ESTADO DE MODO OSCURO GUARDADO EN DISCO
    _modoOscuroLectura = prefs.getBool('pref_modo_oscuro_lectura') ?? false;
    notifyListeners();

    // Descarga de respaldo asíncrona de Supabase
    _descargarAjustesDeNube();
  }

  Future<void> _descargarAjustesDeNube() async {
    try {
      final datos = await _supabase.from('perfil_ajustes').select().eq('id', 'unico_pastor').maybeSingle();
      if (datos != null) {
        _tipoLetra = datos['tipo_letra'] ?? _tipoLetra;
        _tamanoLetra = (datos['tamano_letra'] as num).toDouble();
        _colorFondoHex = datos['color_fondo_hex'] ?? _colorFondoHex;
        
        // Guardamos en la caché local del teléfono/notebook
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pref_tipo_letra', _tipoLetra);
        await prefs.setDouble('pref_tamano_letra', _tamanoLetra);
        await prefs.setInt('pref_color_fondo', _colorFondoHex);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _subirAjustesANube() async {
    try {
      await _supabase.from('perfil_ajustes').upsert({
        'id': 'unico_pastor',
        'tipo_letra': _tipoLetra,
        'tamano_letra': _tamanoLetra,
        'color_fondo_hex': _colorFondoHex,
        'updated_at': DateTime.now().toIso8601String()
      });
    } catch (_) {}
  }

  Future<void> guardarTipoLetra(String nuevaFuente) async {
    _tipoLetra = nuevaFuente;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_tipo_letra', nuevaFuente);
    notifyListeners();
    _subirAjustesANube(); // Sincroniza al instante
  }

  Future<void> guardarTamanoLetra(double nuevoTamano) async {
    _tamanoLetra = nuevoTamano;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pref_tamano_letra', nuevoTamano);
    notifyListeners();
    _subirAjustesANube();
  }

  Future<void> guardarColorFondo(int nuevoColorHex) async {
    _colorFondoHex = nuevoColorHex;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pref_color_fondo', nuevoColorHex);
    notifyListeners();
    _subirAjustesANube();
  }
  
  // 🚀 MÉTODO DE CORRECCIÓN: Enlaza el botón de la luna con la persistencia local y la nube
  Future<void> cambiarModoOscuroLectura(bool activado) async {
    _modoOscuroLectura = activado;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_modo_oscuro_lectura', activado);
    notifyListeners(); // Redibuja el lector en tiempo real
    
    // Sincroniza el cambio con tu servidor de Google Cloud de forma transparente
    _subirAjustesANube(); 
  }
}
