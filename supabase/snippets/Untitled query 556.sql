-- 1. Creación de la tabla con restricción de unicidad compuesta
CREATE TABLE IF NOT EXISTS public.referencias_cruzadas (
  id bigserial NOT NULL,
  origen_libro_id integer NOT NULL, -- Cambiado a NOT NULL para consistencia relacional
  origen_capitulo integer NOT NULL,
  origen_versiculo integer NOT NULL,
  destino_libro_id integer NOT NULL, -- Cambiado a NOT NULL para consistencia relacional
  destino_capitulo integer NOT NULL,
  destino_versiculo integer NOT NULL,
  
  CONSTRAINT referencias_cruzadas_pkey PRIMARY KEY (id),
  CONSTRAINT referencias_cruzadas_origen_libro_id_fkey FOREIGN KEY (origen_libro_id) REFERENCES libros (id) ON DELETE CASCADE,
  CONSTRAINT referencias_cruzadas_destino_libro_id_fkey FOREIGN KEY (destino_libro_id) REFERENCES libros (id) ON DELETE CASCADE,
  
  -- 🚀 CRÍTICO PARA EL MIGRADOR EN DART: Evita duplicados idénticos y habilita el uso de ON CONFLICT / UPSERT
  CONSTRAINT uq_referencia_unica UNIQUE (
    origen_libro_id, origen_capitulo, origen_versiculo, 
    destino_libro_id, destino_capitulo, destino_versiculo
  )
) TABLESPACE pg_default;

-- 2. Índice de Origen: Optimiza la búsqueda de "Citas marginales de este versículo" (Ya lo tenías, mantenido)
CREATE INDEX IF NOT EXISTS idx_referencias_origen 
ON public.referencias_cruzadas USING btree (
  origen_libro_id,
  origen_capitulo,
  origen_versiculo
) TABLESPACE pg_default;

-- 3. 🚀 NUEVO - Índice de Destino: Optimiza la consulta inversa "¿Qué otros versículos citan a este?"
CREATE INDEX IF NOT EXISTS idx_referencias_destino 
ON public.referencias_cruzadas USING btree (
  destino_libro_id,
  destino_capitulo,
  destino_versiculo
) TABLESPACE pg_default;
