CREATE TABLE IF NOT EXISTS public.perfil_ajustes (
    id VARCHAR(50) PRIMARY KEY DEFAULT 'unico_pastor',
    tipo_letra VARCHAR(50) NOT NULL,
    tamano_letra NUMERIC NOT NULL,
    color_fondo_hex BIGINT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Habilitar permisos públicos inmediatos
ALTER TABLE public.perfil_ajustes DISABLE ROW LEVEL SECURITY;
GRANT ALL PRIVILEGES ON TABLE public.perfil_ajustes TO anon;
