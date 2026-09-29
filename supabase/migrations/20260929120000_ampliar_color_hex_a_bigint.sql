-- 1. AMPLIAR color_hex: el cliente envía ARGB completo (p. ej. 0xFFFFF59D =
--    4294901149) y el rango de integer (int4) termina en 2147483647. Con int4
--    todo upsert de un resaltado fallaba con "integer out of range" y la marca
--    se perdía en silencio (el cliente la tragaba en su catch).
--    bigint (int8) es compatible sin pérdida: los valores ya almacenados se
--    conservan y el JSON que recibe Flutter sigue siendo un número (se lee con
--    `as num` -> toInt()), por lo que no se rompe ningún contrato de parseo.
BEGIN;

ALTER TABLE public.resaltados_biblia
    ALTER COLUMN color_hex TYPE bigint;

COMMIT;

-- Verificación post-migración:
--   SELECT column_name, data_type
--     FROM information_schema.columns
--    WHERE table_name = 'resaltados_biblia' AND column_name = 'color_hex';
-- Debe devolver: color_hex | bigint
