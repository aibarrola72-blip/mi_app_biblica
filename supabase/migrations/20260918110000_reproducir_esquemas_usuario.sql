-- =====================================================================
-- REPRODUCIBILIDAD DEL ESQUEMA MULTIUSUARIO (idempotente)
--
-- La migración base solo crea libros, versiones, versiculos,
-- referencias_cruzadas y bosquejos. Las tablas de usuario usadas por la
-- app (perfiles_pastor, progreso_lectura, resaltados_biblia) se crearon
-- históricamente desde la consola, por lo que un entorno limpio
-- (supabase db reset) no podía reproducirlas y la migración de RLS
-- fallaría.
--
-- Este archivo registra esos esquemas de forma idempotente (IF NOT
-- EXISTS) para que un clon o reset no dependa de la consola. En el
-- entorno remoto ya existen y esta migración no toca nada.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. PERFILES_PASTOR
--    PK 'id' = auth.uid(); la app usa nombre, racha_actual y
--    ultima_fecha_lectura. El trigger handle_new_user() crea la fila.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.perfiles_pastor (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre text,
    racha_actual integer DEFAULT 0,
    ultima_fecha_lectura text,
    updated_at timestamptz DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2. BOSQUEJOS: el dueño se guarda en la columna usuario_id
-- ---------------------------------------------------------------------
ALTER TABLE public.bosquejos ADD COLUMN IF NOT EXISTS usuario_id uuid;

-- ---------------------------------------------------------------------
-- 3. PROGRESO_LECTURA (bitácora devocional, única por usuario+capítulo)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.progreso_lectura (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id uuid,
    libro_id integer,
    capitulo integer,
    versiculos_leidos integer DEFAULT 0,
    fecha_lectura timestamptz,
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT uq_progreso_usuario_libro_cap UNIQUE (usuario_id, libro_id, capitulo)
);

-- ---------------------------------------------------------------------
-- 4. RESALTADOS_BIBLIA (única por usuario + llave del versículo)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.resaltados_biblia (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid,
    llave_resaltado text,
    color_hex integer,
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT uq_resaltados_user_llave UNIQUE (user_id, llave_resaltado)
);

COMMIT;