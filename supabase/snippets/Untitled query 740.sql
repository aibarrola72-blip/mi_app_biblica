CREATE OR REPLACE FUNCTION public.importar_lotes_biblia(
  versiculos_input JSONB,
  referencias_input JSONB
)
RETURNS VOID AS $$
BEGIN
  -- Inyección controlada de versículos planos
  IF jsonb_array_length(versiculos_input) > 0 THEN
    INSERT INTO public.versiculos (version_id, libro_id, capitulo, versiculo, texto)
    SELECT 
      (elem->>'version_id')::TEXT,
      (elem->>'libro_id')::INTEGER,
      (elem->>'capitulo')::INTEGER,
      (elem->>'versiculo')::INTEGER,
      (elem->>'texto')::TEXT
    FROM jsonb_array_elements(versiculos_input) AS elem
    ON CONFLICT (version_id, libro_id, capitulo, versiculo) 
    DO UPDATE SET texto = EXCLUDED.texto;
  END IF;

  -- Inyección controlada de citas marginales sin duplicar filas idénticas
  IF jsonb_array_length(referencias_input) > 0 THEN
    INSERT INTO public.referencias_cruzadas (
      origen_libro_id, origen_capitulo, origen_versiculo, 
      destino_libro_id, destino_capitulo, destino_versiculo, llave_unica
    )
    SELECT 
      (elem->>'origen_libro_id')::INTEGER,
      (elem->>'origen_capitulo')::INTEGER,
      (elem->>'origen_versiculo')::INTEGER,
      (elem->>'destino_libro_id')::INTEGER,
      (elem->>'destino_capitulo')::INTEGER,
      (elem->>'destino_versiculo')::INTEGER,
      (elem->>'llave_unica')::TEXT
    FROM jsonb_array_elements(referencias_input) AS elem
    ON CONFLICT (llave_unica) 
    DO NOTHING;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.importar_lotes_biblia TO anon, authenticated, service_role;
