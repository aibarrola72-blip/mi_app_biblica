-- =====================================================================
-- ACTIVAR RLS + POLÍTICAS MULTIUSUARIO (idempotente y reproducible)
--
-- Tablas: bosquejos, perfiles_pastor, progreso_lectura, resaltados_biblia
-- Objetivo: cada usuario autenticado solo lee/escribe sus propios
-- registros, comparando la columna de dueño contra auth.uid().
--
-- NOTA: Esta migración es idempotente; se puede aplicar en el entorno
-- remoto, en un entorno local (supabase db reset) o en un clon nuevo
-- sin romper lo que ya exista.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. PERFILES_PASTOR (PK 'id' = auth.uid(), FK a auth.users)
-- ---------------------------------------------------------------------
ALTER TABLE public.perfiles_pastor ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Los pastores gestionan su propio perfil" ON public.perfiles_pastor;
CREATE POLICY "Los pastores gestionan su propio perfil" ON public.perfiles_pastor
    FOR ALL TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- ---------------------------------------------------------------------
-- 2. BOSQUEJOS (dueño en columna usuario_id)
-- ---------------------------------------------------------------------
ALTER TABLE public.bosquejos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Los pastores leen sus propios bosquejos" ON public.bosquejos;
CREATE POLICY "Los pastores leen sus propios bosquejos" ON public.bosquejos
    FOR SELECT TO authenticated
    USING (auth.uid() = usuario_id);

DROP POLICY IF EXISTS "Los pastores crean sus propios bosquejos" ON public.bosquejos;
CREATE POLICY "Los pastores crean sus propios bosquejos" ON public.bosquejos
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = usuario_id);

DROP POLICY IF EXISTS "Los pastores modifican sus propios bosquejos" ON public.bosquejos;
CREATE POLICY "Los pastores modifican sus propios bosquejos" ON public.bosquejos
    FOR UPDATE TO authenticated
    USING (auth.uid() = usuario_id)
    WITH CHECK (auth.uid() = usuario_id);

DROP POLICY IF EXISTS "Los pastores eliminan sus propios bosquejos" ON public.bosquejos;
CREATE POLICY "Los pastores eliminan sus propios bosquejos" ON public.bosquejos
    FOR DELETE TO authenticated
    USING (auth.uid() = usuario_id);

-- Índice de apoyo para las políticas por dueño
CREATE INDEX IF NOT EXISTS idx_bosquejos_usuario_id ON public.bosquejos (usuario_id);

-- ---------------------------------------------------------------------
-- 3. PROGRESO_LECTURA (dueño en columna usuario_id)
-- ---------------------------------------------------------------------
ALTER TABLE public.progreso_lectura ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Los pastores ven su historial de lectura" ON public.progreso_lectura;
CREATE POLICY "Los pastores ven su historial de lectura" ON public.progreso_lectura
    FOR SELECT TO authenticated
    USING (auth.uid() = usuario_id);

DROP POLICY IF EXISTS "Los pastores registran lectura nueva" ON public.progreso_lectura;
CREATE POLICY "Los pastores registran lectura nueva" ON public.progreso_lectura
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = usuario_id);

DROP POLICY IF EXISTS "Los pastores modifican su propio progreso" ON public.progreso_lectura;
CREATE POLICY "Los pastores modifican su propio progreso" ON public.progreso_lectura
    FOR UPDATE TO authenticated
    USING (auth.uid() = usuario_id)
    WITH CHECK (auth.uid() = usuario_id);

DROP POLICY IF EXISTS "Los pastores eliminan su propio progreso" ON public.progreso_lectura;
CREATE POLICY "Los pastores eliminan su propio progreso" ON public.progreso_lectura
    FOR DELETE TO authenticated
    USING (auth.uid() = usuario_id);

-- Acelera el dashboard (filtra por usuario y ordena por fecha de lectura)
CREATE INDEX IF NOT EXISTS idx_progreso_usuario_fecha
    ON public.progreso_lectura (usuario_id, fecha_lectura DESC);

-- ---------------------------------------------------------------------
-- 4. RESALTADOS_BIBLIA (dueño en columna user_id)
-- ---------------------------------------------------------------------
ALTER TABLE public.resaltados_biblia ENABLE ROW LEVEL SECURITY;

-- Limpieza: existía una política ALL duplicada y redundante
DROP POLICY IF EXISTS "Permitir inserciones a usuarios autenticados" ON public.resaltados_biblia;

DROP POLICY IF EXISTS "Los pastores controlan sus versículos pintados" ON public.resaltados_biblia;
CREATE POLICY "Los pastores controlan sus versículos pintados" ON public.resaltados_biblia
    FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_resaltados_user ON public.resaltados_biblia (user_id);

-- ---------------------------------------------------------------------
-- 5. PROVISIÓN AUTOMÁTICA DE PERFIL (reproducible en entornos limpios)
--    El trigger ya existía en el remoto con la misma lógica; se redefine
--    de forma idempotente y se protege con ON CONFLICT para no fallar
--    si el perfil ya fue creado por otra vía.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
    INSERT INTO public.perfiles_pastor (id, nombre)
    VALUES (new.id, COALESCE(new.raw_user_meta_data->>'full_name',
                             new.raw_user_meta_data->>'name',
                             'Pastor'))
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ---------------------------------------------------------------------
-- 6. ENDURECIMIENTO (defensa en profundidad)
--    El rol anon (clave pública embebida en la app) no debe tocar tablas
--    de usuario aunque RLS ya le devuelve 0 filas: sin privilegios a nivel
--    de tabla tampoco puede intentar operaciones.
-- ---------------------------------------------------------------------
REVOKE ALL PRIVILEGES ON public.bosquejos,
                         public.perfiles_pastor,
                         public.progreso_lectura,
                         public.resaltados_biblia FROM anon;

-- El rol authenticated necesita las secuencias (identity/serial) para insertar
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

COMMIT;