INSERT INTO public.versiones (id, nombre, idioma) VALUES 
('RVA2015', 'Reina-Valera Actualizada 2015', 'es'),
('NTV', 'Nueva Traducción Viviente', 'es'),
('LBLA', 'La Biblia de las Américas', 'es'),
('DHHS', 'Dios Habla Hoy (Con Deuterocanónicos)', 'es'),
('DHH', 'Dios Habla Hoy (Estándar)', 'es'),
('NBLA', 'Nueva Biblia Las Americas', 'es'),
('NVIC', 'Nueva Versión Internacional (Castellano)', 'es'),
('TLA', 'Traducción en Lenguaje Actual', 'es'),
('TLAI', 'Traducción en Lenguaje Actual Internacional', 'es')
ON CONFLICT (id) DO NOTHING;