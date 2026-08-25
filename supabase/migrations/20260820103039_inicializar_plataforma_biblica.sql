-- 1. CREACIÓN DE TABLAS BASE
CREATE TABLE IF NOT EXISTS libros (
    id INTEGER PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    abreviatura VARCHAR(10),
    testamento VARCHAR(2)
);

CREATE TABLE IF NOT EXISTS versiones (
    id VARCHAR(10) PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    idioma VARCHAR(5) DEFAULT 'es'
);

CREATE TABLE IF NOT EXISTS versiculos (
    id BIGSERIAL PRIMARY KEY,
    version_id VARCHAR(10) DEFAULT 'RV1960' REFERENCES versiones(id),
    libro_id INTEGER REFERENCES libros(id) ON DELETE CASCADE,
    capitulo INTEGER NOT NULL,
    versiculo INTEGER NOT NULL,
    texto TEXT NOT NULL,
    fts_vector tsvector,
    CONSTRAINT uq_version_libro_cap_ver UNIQUE (version_id, libro_id, capitulo, versiculo)
);

CREATE TABLE IF NOT EXISTS referencias_cruzadas (
    id BIGSERIAL PRIMARY KEY,
    origen_libro_id INTEGER REFERENCES libros(id),
    origen_capitulo INTEGER NOT NULL,
    origen_versiculo INTEGER NOT NULL,
    destino_libro_id INTEGER REFERENCES libros(id),
    destino_capitulo INTEGER NOT NULL,
    destino_versiculo INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS bosquejos (
    id BIGSERIAL PRIMARY KEY,
    titulo VARCHAR(255) NOT NULL,
    contenido_json TEXT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. POBLAR CATÁLOGOS OBLIGATORIOS
INSERT INTO "public"."versiones" ("id", "nombre", "idioma") VALUES 
('DHH', 'Biblia Traducida (DHH)', 'es'), 
('DHHS', 'Biblia Traducida (DHHS)', 'es'), 
('LBLA', 'Biblia Traducida (LBLA)', 'es'), 
('NBLA', 'Biblia Traducida (NBLA)', 'es'), 
('NTV', 'Biblia Traducida (NTV)', 'es'), 
('NVI', 'Biblia Traducida (NVI)', 'es'), 
('NVIC', 'Biblia Traducida (NVIC)', 'es'), 
('RV1960', 'Biblia Traducida (RV1960)', 'es'), 
('RVA2015', 'Biblia Traducida (RVA2015)', 'es'), 
('RVC', 'Biblia Traducida (RVC)', 'es'), 
('TLA', 'Biblia Traducida (TLA)', 'es'), 
('TLAI', 'Biblia Traducida (TLAI)', 'es')
ON CONFLICT (id) DO NOTHING;

INSERT INTO libros (id, nombre, abreviatura, testamento) VALUES
(1, 'Génesis', 'Gen', 'AT'), (2, 'Éxodo', 'Exo', 'AT'), (3, 'Levítico', 'Lev', 'AT'),
(4, 'Números', 'Num', 'AT'), (5, 'Deuteronomio', 'Deu', 'AT'), (6, 'Josué', 'Jos', 'AT'),
(7, 'Jueces', 'Jue', 'AT'), (8, 'Rut', 'Rut', 'AT'), (9, '1 Samuel', '1_sam', 'AT'),
(10, '2 Samuel', '2_sam', 'AT'), (11, '1 Reyes', '1_reyes', 'AT'), (12, '2 Reyes', '2_reyes', 'AT'),
(13, '1 Crónicas', '1_cron', 'AT'), (14, '2 Crónicas', '2_cron', 'AT'), (15, 'Esdras', 'Esd', 'AT'),
(16, 'Nehemías', 'Neh', 'AT'), (17, 'Ester', 'Est', 'AT'), (18, 'Job', 'Job', 'AT'),
(19, 'Salmos', 'Sal', 'AT'), (20, 'Proverbios', 'Prov', 'AT'), (21, 'Eclesiastés', 'Ecl', 'AT'),
(22, 'Cantares', 'Cant', 'AT'), (23, 'Isaías', 'Isa', 'AT'), (24, 'Jeremías', 'Jer', 'AT'),
(25, 'Lamentaciones', 'Lam', 'AT'), (26, 'Ezequiel', 'Eze', 'AT'), (27, 'Daniel', 'Dan', 'AT'),
(28, 'Oseas', 'Ose', 'AT'), (29, 'Joel', 'Joe', 'AT'), (30, 'Amós', 'Amo', 'AT'),
(31, 'Abdías', 'Abd', 'AT'), (32, 'Jonás', 'Jon', 'AT'), (33, 'Miqueas', 'Miq', 'AT'),
(34, 'Nahum', 'Nah', 'AT'), (35, 'Habacuc', 'Hab', 'AT'), (36, 'Sofonías', 'Sof', 'AT'),
(37, 'Hageo', 'Hag', 'AT'), (38, 'Zacarías', 'Zac', 'AT'), (39, 'Malaquías', 'Mal', 'AT'),
(40, 'Mateo', 'Mat', 'NT'), (41, 'Marcos', 'Mar', 'NT'), (42, 'Lucas', 'Luc', 'NT'),
(43, 'Juan', 'Jn', 'NT'), (44, 'Hechos', 'Hch', 'NT'), (45, 'Romanos', 'Rom', 'NT'),
(46, '1 Corintios', '1_cor', 'NT'), (47, '2 Corintios', '2_cor', 'NT'), (48, 'Gálatas', 'Gal', 'NT'),
(49, 'Efesios', 'Efe', 'NT'), (50, 'Filipenses', 'Flp', 'NT'), (51, 'Colosenses', 'Col', 'NT'),
(52, '1 Tesalonicenses', '1_tes', 'NT'), (53, '2 Tesalonicenses', '2_tes', 'NT'), 
(54, '1 Timoteo', '1_tim', 'NT'), (55, '2 Timoteo', '2_tim', 'NT'), (56, 'Tito', 'Tit', 'NT'),
(57, 'Filemón', 'Flm', 'NT'), (58, 'Hebreos', 'Heb', 'NT'), (59, 'Santiago', 'Stg', 'NT'),
(60, '1 Pedro', '1_ped', 'NT'), (61, '2 Pedro', '2_ped', 'NT'), (62, '1 Juan', '1_juan', 'NT'),
(63, '2 Juan', '2_juan', 'NT'), (64, '3 Juan', '3_juan', 'NT'), (65, 'Judas', 'Jud', 'NT'),
(66, 'Apocalipsis', 'Apo', 'NT')
ON CONFLICT (id) DO NOTHING;

-- 3. CREACIÓN DE ÍNDICES COMPUESTOS DE ALTA VELOCIDAD
CREATE INDEX IF NOT EXISTS idx_versiculos_multi_version ON versiculos (version_id, libro_id, capitulo);
CREATE INDEX IF NOT EXISTS idx_versiculos_orden ON versiculos (libro_id, capitulo, versiculo);
CREATE INDEX IF NOT EXISTS idx_versiculos_fts ON versiculos USING gin(fts_vector);
CREATE INDEX IF NOT EXISTS idx_referencias_origen ON referencias_cruzadas (origen_libro_id, origen_capitulo, origen_versiculo);

-- 4. CONFIGURACIÓN DEL MOTOR FULL-TEXT SEARCH (FTS) AUTOMÁTICO
CREATE OR REPLACE FUNCTION versiculos_trigger_fts() RETURNS trigger AS $$
begin
  new.fts_vector := to_tsvector('spanish', coalesce(new.texto, ''));
  return new;
end
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_versiculos_fts ON versiculos;
CREATE TRIGGER trg_versiculos_fts BEFORE INSERT OR UPDATE ON versiculos
  FOR EACH ROW EXECUTE FUNCTION versiculos_trigger_fts();

-- 5. CONFIGURACIÓN DE POLÍTICAS DE ACCESO Y DESACTIVACIÓN DE RLS DE RAÍZ
ALTER TABLE public.versiculos DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.bosquejos DISABLE ROW LEVEL SECURITY;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO anon;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;
