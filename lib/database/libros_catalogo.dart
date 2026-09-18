// lib/database/libros_catalogo.dart
//
// Lógica pura del catálogo de libros bíblicos (sin dependencias de Supabase o SQLite)
// para poder probarse de forma aislada con tests unitarios.

const Map<int, String> nombresLibrosCanonicos = {
  1: 'Génesis', 2: 'Éxodo', 3: 'Levítico', 4: 'Números', 5: 'Deuteronomio', 6: 'Josué', 7: 'Jueces',
  8: 'Rut', 9: '1 Samuel', 10: '2 Samuel', 11: '1 Reyes', 12: '2 Reyes', 13: '1 Crónicas', 14: '2 Crónicas',
  15: 'Esdras', 16: 'Nehemías', 17: 'Ester', 18: 'Job', 19: 'Salmos', 20: 'Proverbios', 21: 'Eclesiastés',
  22: 'Cantares', 23: 'Isaías', 24: 'Jeremías', 25: 'Lamentaciones', 26: 'Ezequiel', 27: 'Daniel', 28: 'Oseas',
  29: 'Joel', 30: 'Amós', 31: 'Abdías', 32: 'Jonás', 33: 'Miqueas', 34: 'Nahum', 35: 'Habacuc', 36: 'Sofonías',
  37: 'Hageo', 38: 'Zacarías', 39: 'Malaquías', 40: 'Mateo', 41: 'Marcos', 42: 'Lucas', 43: 'Juan', 44: 'Hechos',
  45: 'Romanos', 46: '1 Corintios', 47: '2 Corintios', 48: 'Gálatas', 49: 'Efesios', 50: 'Filipenses',
  51: 'Colosenses', 52: '1 Tesalonicenses', 53: '2 Tesalonicenses', 54: '1 Timoteo', 55: '2 Timoteo',
  56: 'Tito', 57: 'Filemón', 58: 'Hebreos', 59: 'Santiago', 60: '1 Pedro', 61: '2 Pedro', 62: '1 Juan',
  63: '2 Juan', 64: '3 Juan', 65: 'Judas', 66: 'Apocalipsis'
};

const Map<String, int> abreviaturasLibros = {
  'genesis': 1, 'exodo': 2, 'levitico': 3, 'numeros': 4, 'deuteronomio': 5, 'josue': 6, 'jueces': 7,
  'rut': 8, '1 samuel': 9, '1sm': 9, '2 samuel': 10, '2sm': 10, '1 reyes': 11, '1re': 11,
  '2 reyes': 12, '2re': 12, '1 cronicas': 13, '1cr': 13, '2 cronicas': 14, '2cr': 14, 'esdras': 15,
  'nehemias': 16, 'ester': 17, 'job': 18, 'salmos': 19, 'sal': 19, 'proverbios': 20,
  'pr': 20, 'eclesiastes': 21, 'ec': 21, 'cantares': 22, 'cnt': 22, 'isaias': 23, 'is': 23, 'jeremias': 24,
  'jr': 24, 'lamentaciones': 25, 'ezequiel': 26, 'ez': 26, 'daniel': 27, 'dn': 27, 'oseas': 28, 'os': 28,
  'joel': 29, 'jl': 29, 'amos': 30, 'am': 30, 'abdias': 31, 'abd': 31, 'jonas': 32, 'jon': 32, 'miqueas': 33, 'mi': 33,
  'nahum': 34, 'habacuc': 35, 'sofonias': 36, 'sof': 36, 'hageo': 37, 'zacarias': 38, 'zac': 38, 'malaquias': 39,
  'mal': 39, 'mateo': 40, 'mt': 40, 'marcos': 41, 'mr': 41, 'lucas': 42, 'lc': 42, 'juan': 43, 'jn': 43,
  'hechos': 44, 'hch': 44, 'romanos': 45, 'ro': 45, '1 corintios': 46, '1co': 46, '1 cor': 46,
  '2 corintios': 47, '2co': 47, 'galatas': 48, 'gl': 48, 'efesios': 49, 'ef': 49, 'filipenses': 50, 'flp': 50,
  'colosenses': 51, 'col': 51, '1 tesalonicenses': 52, '1ts': 52, '2 tesalonicenses': 53, '2ts': 53,
  '1 timoteo': 54, '1ti': 54, '2 timoteo': 55, '2ti': 55, 'tito': 56, 'tit': 56, 'filemon': 57, 'flm': 57,
  'hebreos': 58, 'heb': 58, 'santiago': 59, 'stg': 59, 'st': 59, '1 pedro': 60, '1p': 60, '2 pedro': 61,
  '2p': 61, '1 juan': 62, '1jn': 62, '2 juan': 63, '2jn': 63, '3 juan': 64, '3jn': 64, 'judas': 65, 'apocalipsis': 66, 'ap': 66
};

const Map<String, int> mapaLibrosSanitizado = {
  'genesis': 1, 'gn': 1, 'exodo': 2, 'ex': 2, 'exo': 2, 'exod': 2, 'levitico': 3, 'lv': 3, 'numeros': 4, 'nm': 4,
  'deuteronomio': 5, 'dt': 5, 'josue': 6, 'jos': 6, 'jueces': 7, 'jue': 7, 'rut': 8, 'rt': 8,
  '1 samuel': 9, '1sm': 9, '1 sm': 9, '2 samuel': 10, '2sm': 10, '2 sm': 10, '1 reyes': 11, '1r': 11, '1 r': 11,
  '2 reyes': 12, '2r': 12, '2 r': 12, '1 cronicas': 13, '1cr': 13, '1 cr': 13, '2 cronicas': 14, '2cr': 14, '2 cr': 14,
  'esdras': 15, 'esd': 15, 'nehemias': 16, 'neh': 16, 'ester': 17, 'est': 17, 'job': 18,
  'salmos': 19, 'sal': 19, 'proverbios': 20, 'pr': 20, 'eclesiastes': 21, 'ec': 21, 'cantares': 22, 'cnt': 22,
  'isaias': 23, 'is': 23, 'jeremias': 24, 'jr': 24, 'lamentaciones': 25, 'lam': 25, 'ezequiel': 26, 'ez': 26,
  'daniel': 27, 'dn': 27, 'oseas': 28, 'os': 28, 'joel': 29, 'jl': 29, 'amos': 30, 'am': 30,
  'abdias': 31, 'abd': 31, 'jonas': 32, 'jon': 32, 'miqueas': 33, 'mi': 33, 'nahum': 34, 'nah': 34,
  'habacuc': 35, 'hab': 35, 'sofonias': 36, 'sof': 36, 'hageo': 37, 'hag': 37, 'zacarias': 38, 'zac': 38,
  'malaquias': 39, 'mal': 39, 'mateo': 40, 'mt': 40, 'marcos': 41, 'mr': 41, 'lucas': 42, 'lc': 42,
  'juan': 43, 'jn': 43, 'hechos': 44, 'hch': 44, 'romanos': 45, 'ro': 45,
  '1 corintios': 46, '1co': 46, '1 co': 46, '1 cor': 46, '2 corintios': 47, '2co': 47, '2 co': 47,
  'galatas': 48, 'ga': 48, 'efesios': 49, 'ef': 49, 'filipenses': 50, 'flp': 50, 'colosenses': 51, 'col': 51,
  '1 tesalonicenses': 52, '1ts': 52, '1 ts': 52, '2 tesalonicenses': 53, '2ts': 53, '2 ts': 53,
  '1 timoteo': 54, '1ti': 54, '1 ti': 54, '2 timoteo': 55, '2ti': 55, '2 ti': 55, 'tito': 56, 'ti': 56,
  'filemon': 57, 'flm': 57, 'hebreos': 58, 'heb': 58, 'santiago': 59, 'stg': 59,
  '1 pedro': 60, '1p': 60, '1 p': 60, '2 pedro': 61, '2p': 61, '2 p': 61,
  '1 juan': 62, '1jn': 62, '1 jn': 62, '2 juan': 63, '2jn': 63, '2 jn': 63, '3 juan': 64, '3jn': 64, '3 jn': 64,
  'judas': 65, 'jud': 65, 'apocalipsis': 66, 'ap': 66
};

String removerAcentostildes(String texto) {
  var conAcento = 'áéíóúÁÉÍÓÚñÑ';
  var sinAcento = 'aeiouAEIOUnN';
  String resultado = texto;
  for (int i = 0; i < conAcento.length; i++) {
    resultado = resultado.replaceAll(conAcento[i], sinAcento[i]);
  }
  return resultado.toLowerCase().trim().replaceAll('.', '');
}

int obtenerIdLibro(String nombreLibro) {
  String textoEvaluar = nombreLibro.toLowerCase().trim().replaceAll('.', '');
  textoEvaluar = textoEvaluar
    .replaceAll(RegExp(r'[áäàâÁÀÂÄ]'), 'a')
    .replaceAll(RegExp(r'[éëèêÉÈÊË]'), 'e')
    .replaceAll(RegExp(r'[íïìîÍÌÎÏ]'), 'i')
    .replaceAll(RegExp(r'[óöòôÓÒÔÖ]'), 'o')
    .replaceAll(RegExp(r'[úüùûÚÙÛÜ]'), 'u')
    .replaceAll(RegExp(r'[ñÑ]'), 'n');
  return mapaLibrosSanitizado[textoEvaluar] ?? 0;
}