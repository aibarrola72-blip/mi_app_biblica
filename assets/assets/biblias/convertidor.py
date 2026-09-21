import json
import re
import csv

# 1. Diccionario de mapeo de libros a IDs según el orden canónico de tu base de datos
# Asegúrate de ajustar estos IDs si tu tabla 'libros' usa otra numeración.
diccionario_libros = {
    "Gn": 1, "Ex": 2, "Lv": 3, "Nm": 4, "Dt": 5, "Jos": 6, "Jue": 7, "Rt": 8,
    "1 S": 9, "2 S": 10, "1 R": 11, "2 R": 12, "1 Cr": 13, "2 Cr": 14, "Esd": 15,
    "Neh": 16, "Est": 17, "Job": 18, "Sal": 19, "Pr": 20, "Ec": 21, "Cant": 22,
    "Is": 23, "Jer": 24, "Lam": 25, "Ez": 26, "Dn": 27, "Os": 28, "Jl": 29,
    "Am": 30, "Abd": 31, "Jon": 32, "Miq": 33, "Nah": 34, "Hab": 35, "Sof": 36,
    "Ag": 37, "Zac": 38, "Mal": 39, "Mt": 40, "Mr": 41, "Lc": 42, "Jn": 43,
    "Hch": 44, "Ro": 45, "1 Co": 46, "2 Co": 47, "Gál": 48, "Ef": 49, "Flp": 50,
    "Col": 51, "1 Ts": 52, "2 Ts": 53, "1 Tim": 54, "2 Tim": 55, "Tit": 56,
    "Flm": 57, "He": 58, "Heb": 58, "Stg": 59, "1 P": 60, "2 P": 61, "1 Jn": 62,
    "2 Jn": 63, "3 Jn": 64, "Jud": 65, "Ap": 66
}

def extraer_referencias(json_path, csv_path):
    # Cargar el archivo JSON original enviado en el contexto
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    referencias_cruzadas = []
    
    # Expresiones regulares para segmentar los bloques HTML del JSON
    reg_regex_verso = re.compile(r'class="verse\s+v([0-9]+)"[^>]*>(.*?)</span>\s*</span>', re.DOTALL)
    reg_regex_nota = re.compile(r'class=" body">(.*?)</span>', re.DOTALL)
    
    # Iterar sobre la estructura de libros y capítulos del JSON
    for libro_idx, libro in enumerate(data.get('books', [])):
        origen_libro_id = libro_idx + 1 # Asumiendo Génesis = 1
        
        for capitulo in libro.get('chapters', []):
            # Extraer número de capítulo de forma segura
            cap_usfm = capitulo.get('chapter_usfm', '')
            origen_capitulo = int(cap_usfm.split('.')[-1]) if '.' in cap_usfm else 1
            html_contenido = capitulo.get('chapter_html', '')
            
            # Buscar versículos dentro del HTML
            matches_versos = reg_regex_verso.findall(html_contenido)
            for v_num, bloque_interno in matches_versos:
                origen_versiculo = int(v_num)
                
                # Verificar si el versículo contiene notas de referencias cruzadas (#)
                if 'class="note x"' in bloque_interno:
                    matches_notas = reg_regex_nota.findall(bloque_interno)
                    
                    for texto_nota_raw in matches_notas:
                        # Limpiar etiquetas HTML residuales internas de la nota
                        texto_nota = re.sub(r'<[^>]*>', '', texto_nota_raw).strip()
                        
                        # Dividir si hay múltiples libros en una misma nota (separados por punto y coma)
                        segmentos = texto_nota.split(';')
                        for segmento in segmentos:
                            segmento = segmento.trim() if hasattr(segmento, 'trim') else segmento.strip()
                            if not segmento:
                                continue
                                
                            # Identificar el nombre del libro destino (ej: "2 Co.", "Gn.")
                            match_libro = re.match(r'([1-3]?\s?[A-Za-záéíóúÁÉÍÓÚ\s]+)\.', segmento)
                            if not match_libro:
                                continue
                                
                            nombre_libro_dest = match_libro.group(1).strip()
                            destino_libro_id = diccionario_libros.get(nombre_libro_dest, 0)
                            if destino_libro_id == 0:
                                continue # Ignorar si el libro no está mapeado
                                
                            # Buscar todos los pares de "Capítulo.Versículo" o rangos en ese segmento
                            # Maneja formatos como "4.6", "19.4", "10.7-8", "4.4,10"
                            matches_num = re.findall(r'([0-9]+)\.([0-9]+(?:-[0-9]+)?(?:,[0-9]+)?)', segmento)
                            
                            for cap_dest, vers_dest_raw in matches_num:
                                destino_capitulo = int(cap_dest)
                                
                                # Normalizar versículos compuestos (comas o rangos)
                                # Ej: "7-8" -> [7, 8] o "4,10" -> [4, 10]
                                sub_versiculos = []
                                if ',' in vers_dest_raw:
                                    sub_versiculos = vers_dest_raw.split(',')
                                elif '-' in vers_dest_raw:
                                    inicio, fin = map(int, vers_dest_raw.split('-'))
                                    sub_versiculos = [str(x) for range(inicio, fin + 1)]
                                else:
                                    sub_versiculos = [vers_dest_raw]
                                    
                                for v_dest in sub_versiculos:
                                    try:
                                        destino_versiculo = int(v_dest.strip())
                                        
                                        # Construcción de la restricción UNIQUE requerida
                                        llave_unica = f"{origen_libro_id}_{origen_capitulo}_{origen_versiculo}_{destino_libro_id}_{destino_capitulo}_{destino_versiculo}"
                                        
                                        referencias_cruzadas.append({
                                            "origen_libro_id": origen_libro_id,
                                            "origen_capitulo": origen_capitulo,
                                            "origen_versiculo": origen_versiculo,
                                            "destino_libro_id": destino_libro_id,
                                            "destino_capitulo": destino_capitulo,
                                            "destino_versiculo": destino_versiculo,
                                            "llave_unica": llave_unica
                                        })
                                    except ValueError:
                                        continue

    # 3. Escritura del archivo CSV físico con las cabeceras exactas de tu tabla SQL
    with open(csv_path, 'w', encoding='utf-8', newline='') as f_csv:
        columnas = ["origen_libro_id", "origen_capitulo", "origen_versiculo", "destino_libro_id", "destino_capitulo", "destino_versiculo", "llave_unica"]
        writer = csv.DictWriter(f_csv, fieldnames=columnas)
        writer.writeheader()
        writer.writerows(referencias_cruzadas)
        print(f"Éxito: Se han extraído {len(referencias_cruzadas)} referencias en '{csv_path}'")

# Ejecución local (asumiendo que tu archivo se llama 'rv1960.json')
extraer_referencias('rv1960.json', 'referencias_cruzadas.csv')
