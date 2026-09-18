// Tests unitarios del catálogo bíblico (lógica pura, sin Supabase ni SQLite).
import 'package:flutter_test/flutter_test.dart';

import 'package:mi_app_biblica/database/libros_catalogo.dart';

void main() {
  group('nombresLibrosCanonicos', () {
    test('resuelve libros al inicio y final del canon', () {
      expect(nombresLibrosCanonicos[1], 'Génesis');
      expect(nombresLibrosCanonicos[66], 'Apocalipsis');
      expect(nombresLibrosCanonicos.length, 66);
    });

    test('devuelve null para ids fuera de rango', () {
      expect(nombresLibrosCanonicos[0], isNull);
      expect(nombresLibrosCanonicos[67], isNull);
    });
  });

  group('removerAcentostildes', () {
    test('limpia tildes, convierte a minúsculas y quita puntos', () {
      expect(removerAcentostildes('Éxodo'), 'exodo');
      expect(removerAcentostildes('1 Crónicas.'), '1 cronicas');
      expect(removerAcentostildes('Apocalipsis'), 'apocalipsis');
    });
  });

  group('obtenerIdLibro', () {
    test('reconoce nombres completos con tildes y mayúsculas', () {
      expect(obtenerIdLibro('Génesis'), 1);
      expect(obtenerIdLibro('Apocalipsis'), 66);
      expect(obtenerIdLibro('1 Corintios'), 46);
      expect(obtenerIdLibro('Éxodo'), 2);
    });

    test('reconoce abreviaturas y formatos con puntos', () {
      expect(obtenerIdLibro('Gn'), 1);
      expect(obtenerIdLibro('1 Co.'), 46);
      expect(obtenerIdLibro('Ap'), 66);
      expect(obtenerIdLibro('Sal.'), 19);
    });

    test('devuelve 0 para textos no reconocidos', () {
      expect(obtenerIdLibro('Texto Inventado'), 0);
    });
  });

  group('abreviaturasLibros', () {
    test('el mapa de abreviaturas cubre todos los libros', () {
      expect(abreviaturasLibros['genesis'], 1);
      expect(abreviaturasLibros['apocalipsis'], 66);
      expect(abreviaturasLibros['jn'], 43);
    });
  });
}