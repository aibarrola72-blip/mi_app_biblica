-- 1. Limpiamos la estructura previa para evitar conflictos
ALTER TABLE public.referencias_cruzadas DROP CONSTRAINT IF EXISTS uq_referencia_unica;
DROP INDEX IF EXISTS uq_referencia_unica_idx;

-- 2. Añadimos la nueva columna de control único
ALTER TABLE public.referencias_cruzadas 
ADD COLUMN IF NOT EXISTS llave_unica TEXT;

-- 3. Creamos la restricción de unicidad sobre esa única columna
ALTER TABLE public.referencias_cruzadas 
ADD CONSTRAINT uq_llave_referencia UNIQUE (llave_unica);
