-- 1. Añadimos la columna fts_vector que se actualiza sola combinando el texto de los versículos
ALTER TABLE public.versiculos 
ADD COLUMN fts_vector tsvector GENERATED ALWAYS AS (to_tsvector('spanish', coalesce(texto, ''))) STORED;

-- 2. Creamos un índice GiN para que las búsquedas tomen milisegundos incluso con millones de filas
CREATE INDEX IF NOT EXISTS versiculos_fts_idx ON public.versiculos USING gin (fts_vector);
