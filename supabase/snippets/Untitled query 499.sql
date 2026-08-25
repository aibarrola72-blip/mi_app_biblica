-- 1. Eliminamos la restricción lógica vieja para evitar colisiones
ALTER TABLE public.referencias_cruzadas DROP CONSTRAINT IF EXISTS uq_referencia_unica;

-- 2. Creamos un índice físico ÚNICO (PostgreSQL prefiere indexaciones directas para resolver ON CONFLICT)
CREATE UNIQUE INDEX IF NOT EXISTS uq_referencia_unica_idx 
ON public.referencias_cruzadas (
  origen_libro_id, origen_capitulo, origen_versiculo, 
  destino_libro_id, destino_capitulo, destino_versiculo
);
