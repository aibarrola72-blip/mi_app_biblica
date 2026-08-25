-- 1. Desactivar restricciones previas de forma segura en cascada
DROP TABLE IF EXISTS public.referencias_cruzadas CASCADE;
DROP TABLE IF EXISTS public.versiculos CASCADE;
DROP TABLE IF EXISTS public.versiones CASCADE;
DROP TABLE IF EXISTS public.libros CASCADE;

-- 2. Estructura maestra del Canon Bíblico
CREATE TABLE public.libros (
  id INTEGER NOT NULL,
  nombre TEXT NOT NULL,
  CONSTRAINT libros_pkey PRIMARY KEY (id)
);

-- Inserción inicial de control para evitar fallas relacionales (fkeys)
INSERT INTO public.libros (id, nombre) VALUES 
(1, 'Génesis'), (2, 'Éxodo'), (3, 'Levítico'), (4, 'Números'), (5, 'Deuteronomio'),
(6, 'Josué'), (7, 'Jueces'), (8, 'Rut'), (9, '1 Samuel'), (10, '2 Samuel'),
(11, '1 Reyes'), (12, '2 Reyes'), (13, '1 Crónicas'), (14, '2 Crónicas'),
(15, 'Esdras'), (16, 'Nehemías'), (17, 'Ester'), (18, 'Job'), (19, 'Salmos'),
(20, 'Proverbios'), (21, 'Eclesiastés'), (22, 'Cantares'), (23, 'Isaías'),
(24, 'Jeremías'), (25, 'Lamentaciones'), (26, 'Ezequiel'), (27, 'Daniel'),
(28, 'Oseas'), (29, 'Joel'), (30, 'Amós'), (31, 'Abdías'), (32, 'Jonás'),
(33, 'Miqueas'), (34, 'Nahum'), (35, 'Habacuc'), (36, 'Sofonías'), (37, 'Hageo'),
(38, 'Zacarías'), (39, 'Malaquías'), (40, 'Mateo'), (41, 'Marcos'), (42, 'Lucas'),
(43, 'Juan'), (44, 'Hechos'), (45, 'Romanos'), (46, '1 Corintios'), (47, '2 Corintios'),
(48, 'Gálatas'), (49, 'Efesios'), (50, 'Filipenses'), (51, 'Colosenses'),
(52, '1 Tesalonicenses'), (53, '2 Tesalonicenses'), (54, '1 Timoteo'),
(55, '2 Timoteo'), (56, 'Tito'), (57, 'Filemón'), (58, 'Hebreos'), (59, 'Santiago'),
(60, '1 Pedro'), (61, '2 Pedro'), (62, '1 Juan'), (63, '2 Juan'), (64, '3 Juan'),
(65, 'Judas'), (66, 'Apocalipsis')
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre;

-- 3. Estructura de Versiones
CREATE TABLE public.versiones (
  id TEXT NOT NULL,
  nombre TEXT NOT NULL,
  idioma TEXT NOT NULL,
  CONSTRAINT versiones_pkey PRIMARY KEY (id)
);

-- 4. Estructura de Versículos con Clave Única Compuesta
CREATE TABLE public.versiculos (
  id BIGSERIAL NOT NULL,
  version_id TEXT NOT NULL,
  libro_id INTEGER NOT NULL,
  capitulo INTEGER NOT NULL,
  versiculo INTEGER NOT NULL,
  texto TEXT NOT NULL,
  CONSTRAINT versiculos_pkey PRIMARY KEY (id),
  CONSTRAINT versiculos_version_id_fkey FOREIGN KEY (version_id) REFERENCES versiones (id) ON DELETE CASCADE,
  CONSTRAINT versiculos_libro_id_fkey FOREIGN KEY (libro_id) REFERENCES libros (id) ON DELETE CASCADE,
  CONSTRAINT uq_versiculo_unico UNIQUE (version_id, libro_id, capitulo, versiculo)
);

-- 5. Estructura de Referencias Cruzadas Indexada por Llave Única Virtual
CREATE TABLE public.referencias_cruzadas (
  id BIGSERIAL NOT NULL,
  origen_libro_id INTEGER NOT NULL,
  origen_capitulo INTEGER NOT NULL,
  origen_versiculo INTEGER NOT NULL,
  destino_libro_id INTEGER NOT NULL,
  destino_capitulo INTEGER NOT NULL,
  destino_versiculo INTEGER NOT NULL,
  llave_unica TEXT NOT NULL,
  CONSTRAINT referencias_cruzadas_pkey PRIMARY KEY (id),
  CONSTRAINT referencias_cruzadas_origen_libro_id_fkey FOREIGN KEY (origen_libro_id) REFERENCES libros (id) ON DELETE CASCADE,
  CONSTRAINT referencias_cruzadas_destino_libro_id_fkey FOREIGN KEY (destino_libro_id) REFERENCES libros (id) ON DELETE CASCADE,
  CONSTRAINT uq_llave_referencia UNIQUE (llave_unica)
);

-- 6. Apertura de acceso total libre (Unrestricted local development)
ALTER TABLE public.versiones DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.versiculos DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.referencias_cruzadas DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.libros DISABLE ROW LEVEL SECURITY;
