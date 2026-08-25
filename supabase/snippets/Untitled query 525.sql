-- 🚀 SOLUCIÓN AL ERROR 42501: Desactiva el candado de seguridad RLS para el entorno local
ALTER TABLE public.versiones DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.versiculos DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.referencias_cruzadas DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.libros DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.bosquejos DISABLE ROW LEVEL SECURITY;

-- Concede permisos explícitos de acceso al rol anónimo de la API
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
