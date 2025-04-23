#image_processing.py
import cv2
import numpy as np
from collections import defaultdict
from sklearn.cluster import DBSCAN

def melhorar_pre_processamento(image):
    """
    Pré-processamento avançado da imagem para melhorar detecção de bolhas.
    
    Args:
        image: Imagem original em BGR
    
    Returns:
        binary: Imagem binária otimizada para detecção de bolhas
        normalized: Imagem normalizada para visualização
    """
    # Converter para escala de cinza
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    
    # Aplicar equalização de histograma adaptativa (CLAHE) com parâmetros otimizados
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(16, 16))
    equalized = clahe.apply(gray)
    
    # Redução de ruído com filtro Gaussiano (mais efetivo para este caso)
    denoised = cv2.GaussianBlur(equalized, (5, 5), 0)
    
    # Normalização global para melhorar contraste
    normalized = cv2.normalize(denoised, None, 0, 255, cv2.NORM_MINMAX)
    
    # Aplicar threshold adaptativo com parâmetros mais agressivos
    binary_adaptive = cv2.adaptiveThreshold(
        normalized, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
        cv2.THRESH_BINARY_INV, 21, 10
    )
    
    # Aplicar também threshold Otsu para comparação
    _, binary_otsu = cv2.threshold(normalized, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    
    # Combinar os dois métodos de threshold
    binary = cv2.bitwise_or(binary_adaptive, binary_otsu)
    
    # Limpeza morfológica otimizada
    kernel_open = np.ones((3, 3), np.uint8)
    kernel_close = np.ones((7, 7), np.uint8)
    
    # Opening (erosão seguida de dilatação) - remove pequenos ruídos
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel_open)
    
    # Closing (dilatação seguida de erosão) - fecha pequenas quebras
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel_close)
    
    return binary, normalized

def corrigir_perspectiva(image, binary):
    """
    Detecta e corrige a perspectiva do cartão de respostas.
    
    Args:
        image: Imagem original em BGR
        binary: Imagem binária pré-processada
    
    Returns:
        corrected_image: Imagem corrigida em perspectiva
        corrected_binary: Binária corrigida em perspectiva
        success: Boolean indicando sucesso na correção
    """
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    
    if not contours:
        return image, binary, False
    
    contours = sorted(contours, key=cv2.contourArea, reverse=True)
    largest_contour = contours[0]
    
    perimeter = cv2.arcLength(largest_contour, True)
    approx = cv2.approxPolyDP(largest_contour, 0.02 * perimeter, True)
    
    if len(approx) != 4:
        hull = cv2.convexHull(largest_contour)
        approx = cv2.approxPolyDP(hull, 0.02 * cv2.arcLength(hull, True), True)
        
        if len(approx) != 4:
            x, y, w, h = cv2.boundingRect(largest_contour)
            approx = np.array([[x, y], [x+w, y], [x+w, y+h], [x, y+h]], dtype=np.float32).reshape(-1, 1, 2)
    
    approx = approx.reshape(4, 2)
    sum_coords = approx.sum(axis=1)
    diff_coords = np.diff(approx, axis=1)
    
    rect = np.zeros((4, 2), dtype=np.float32)
    rect[0] = approx[np.argmin(sum_coords)]
    rect[2] = approx[np.argmax(sum_coords)]
    rect[1] = approx[np.argmin(diff_coords)]
    rect[3] = approx[np.argmax(diff_coords)]
    
    width_A = np.sqrt(((rect[2][0] - rect[3][0]) ** 2) + ((rect[2][1] - rect[3][1]) ** 2))
    width_B = np.sqrt(((rect[1][0] - rect[0][0]) ** 2) + ((rect[1][1] - rect[0][1]) ** 2))
    max_width = max(int(width_A), int(width_B))
    
    height_A = np.sqrt(((rect[1][0] - rect[2][0]) ** 2) + ((rect[1][1] - rect[2][1]) ** 2))
    height_B = np.sqrt(((rect[0][0] - rect[3][0]) ** 2) + ((rect[0][1] - rect[3][1]) ** 2))
    max_height = max(int(height_A), int(height_B))
    
    dst = np.array([
        [0, 0],
        [max_width - 1, 0],
        [max_width - 1, max_height - 1],
        [0, max_height - 1]
    ], dtype=np.float32)
    
    transform_matrix = cv2.getPerspectiveTransform(rect, dst)
    corrected_image = cv2.warpPerspective(image, transform_matrix, (max_width, max_height))
    corrected_binary = cv2.warpPerspective(binary, transform_matrix, (max_width, max_height))
    
    return corrected_image, corrected_binary, True

def detectar_bolhas_avancado(binary, debug_image=None, threshold=100, sensitivity=0.5):
    """
    Detecta bolhas em um cartão resposta com métodos robustos e filtragem melhorada.

    Args:
        binary: Imagem binária pré-processada
        debug_image: Imagem para desenhar informações de debug (opcional)
        threshold: Valor de limiar para detecção de marcação (0-255)
        sensitivity: Sensibilidade para considerar uma bolha preenchida (0.0-1.0)

    Returns:
        bolhas: Lista de dicionários com informações de cada bolha detectada
        debug_img: Imagem com visualização do processamento
    """
    import numpy as np
    import cv2

    if debug_image is None:
        debug_img = cv2.cvtColor(binary, cv2.COLOR_GRAY2BGR)
    else:
        debug_img = debug_image.copy()
    
    # Preparar imagem para HoughCircles - inversão para que círculos sejam mais claros que o fundo
    img_for_circles = 255 - binary.copy()
    # Suavização para melhorar detecção
    img_for_circles = cv2.GaussianBlur(img_for_circles, (5, 5), 0)

    # Aplicar HoughCircles com parâmetros mais robustos
    circles = cv2.HoughCircles(
        img_for_circles,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=25,
        param1=50,   # Sensibilidade do detector de bordas
        param2=25,   # Threshold para detecção de círculos
        minRadius=10,
        maxRadius=30
    )

    bolhas = []
    
    if circles is not None:
        circles = np.uint16(np.around(circles[0]))
        centros_detectados = []

        for (x, y, r) in circles:
            # Verificar limites da imagem
            if (x - r < 0 or y - r < 0 or 
                x + r >= binary.shape[1] or y + r >= binary.shape[0]):
                continue
                
            # Verifica duplicatas por proximidade
            if any(np.linalg.norm(np.array((x, y)) - np.array(c)) < 20 for c in centros_detectados):
                continue
            
            centros_detectados.append((x, y))

            # Melhor análise de preenchimento usando máscara circular
            mask = np.zeros_like(binary)
            cv2.circle(mask, (x, y), r, 255, -1)
            
            # Usar uma máscara menor para análise interna (80% do raio)
            inner_mask = np.zeros_like(binary)
            inner_r = int(r * 0.8)  # Raio interno
            cv2.circle(inner_mask, (x, y), inner_r, 255, -1)
            
            # Calcular preenchimento apenas na região interna
            roi = cv2.bitwise_and(binary, inner_mask)
            inner_area = np.pi * inner_r * inner_r
            filled_pixels = cv2.countNonZero(roi)
            fill_rate = filled_pixels / inner_area
            
            # Aplicar threshold com base na sensibilidade
            is_filled = fill_rate > sensitivity

            bolhas.append({
                'x': x,
                'y': y,
                'centro': (x, y),
                'radius': r,
                'fill_rate': fill_rate,
                'filled': is_filled
            })

            # Desenha para debug
            color = (0, 0, 255) if is_filled else (0, 255, 0)
            cv2.circle(debug_img, (x, y), r, color, 2)
            cv2.putText(debug_img, f"{int(fill_rate * 100)}%", (x - 20, y - 15),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1)
    
    # Método alternativo se não foram encontrados círculos suficientes
    if len(bolhas) < 10:
        # Método alternativo: detecção por contornos 
        contornos, _ = cv2.findContours(binary, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)

        for cnt in contornos:
            area = cv2.contourArea(cnt)
            
            # Filtragem por área
            if area < 100 or area > 900:
                continue

            perimeter = cv2.arcLength(cnt, True)
            if perimeter == 0:
                continue
                
            # Filtragem por circularidade
            circularity = 4 * np.pi * area / (perimeter * perimeter)
            if circularity < 0.7:
                continue

            # Filtragem por proporção de dimensões
            x, y, w, h = cv2.boundingRect(cnt)
            if w / h < 0.7 or w / h > 1.3:
                continue

            # Criar máscara circular para análise de preenchimento
            mask = np.zeros_like(binary)
            center = (x + w // 2, y + h // 2)
            radius = (w + h) // 4
            cv2.circle(mask, center, int(radius * 0.8), 255, -1)
            
            # Analisar preenchimento mais preciso
            roi = cv2.bitwise_and(binary, mask)
            masked_area = cv2.countNonZero(mask)
            if masked_area == 0:
                continue
                
            filled_pixels = cv2.countNonZero(roi)
            fill_rate = filled_pixels / masked_area
            is_filled = fill_rate > sensitivity

            # Calcular centro
            M = cv2.moments(cnt)
            if M["m00"] != 0:
                cx = int(M["m10"] / M["m00"])
                cy = int(M["m01"] / M["m00"])
            else:
                cx, cy = x + w // 2, y + h // 2

            # Verificar se já existe uma bolha muito próxima
            if any(np.linalg.norm(np.array((cx, cy)) - np.array(b['centro'])) < 20 for b in bolhas):
                continue

            bolhas.append({
                'x': cx,
                'y': cy,
                'centro': (cx, cy),
                'radius': radius,
                'fill_rate': fill_rate,
                'filled': is_filled,
                'contour': cnt
            })

            # Desenha para debug
            color = (0, 0, 255) if is_filled else (0, 255, 0)
            cv2.circle(debug_img, (cx, cy), radius, color, 2)
            cv2.putText(debug_img, f"{int(fill_rate * 100)}%", (cx - 20, cy - 15),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1)

    return bolhas, debug_img

def agrupar_bolhas_por_questoes(bolhas, num_questoes=10, num_alternativas=5):
    """
    Agrupa bolhas por questões usando clustering hierárquico com melhor filtragem.
    
    Args:
        bolhas: Lista de dicionários com informações das bolhas
        num_questoes: Número esperado de questões
        num_alternativas: Número esperado de alternativas por questão
    
    Returns:
        questoes: Lista de listas de bolhas agrupadas por questão
    """
    if not bolhas:
        return []
    
    # Extrair centros das bolhas para clustering
    if 'centro' in bolhas[0]:
        centros = np.array([bolha['centro'] for bolha in bolhas])
    else:
        centros = np.array([[bolha['x'], bolha['y']] for bolha in bolhas])
    
    # Aplicar DBSCAN para agrupar por coordenada Y (linhas/questões)
    sorted_y = np.sort([c[1] for c in centros])
    y_diffs = np.diff(sorted_y)
    
    if len(y_diffs) > 0:
        median_diff = np.median(y_diffs)
        # Garantir que epsilon seja sempre > 0
        epsilon = max(median_diff * 0.6, 5.0)  # Mínimo de 5.0 pixels
    else:
        epsilon = 20
    
    y_coords = np.array([[c[1]] for c in centros])
    db = DBSCAN(eps=epsilon, min_samples=2).fit(y_coords)
    
    labels = db.labels_
    
    clusters = defaultdict(list)
    for i, bolha in enumerate(bolhas):
        if labels[i] != -1:
            clusters[labels[i]].append(bolha)
    
    # Ordenar clusters por posição vertical
    sorted_clusters = sorted(
        clusters.values(),
        key=lambda cluster: np.mean([b['centro'][1] if 'centro' in b else b['y'] for b in cluster])
    )
    
    # Limitar ao número de questões esperado
    sorted_clusters = sorted_clusters[:num_questoes]
    
    questoes = []
    for cluster in sorted_clusters:
        # Ordenar bolhas horizontalmente
        if 'centro' in cluster[0]:
            bolhas_ordenadas = sorted(cluster, key=lambda b: b['centro'][0])
        else:
            bolhas_ordenadas = sorted(cluster, key=lambda b: b['x'])
        
        # Se há mais alternativas que o esperado, precisamos filtrar
        if len(bolhas_ordenadas) > num_alternativas:
            print(f"Aviso: Encontradas {len(bolhas_ordenadas)} alternativas (esperado {num_alternativas}).")
            
            # Método 1: Agrupamento horizontal mais robusto
            x_coords = np.array([b['centro'][0] if 'centro' in b else b['x'] for b in bolhas_ordenadas])
            x_coords = x_coords.reshape(-1, 1)
            
            # Tentar agrupar horizontalmente para identificar alternativas próximas/duplicadas
            # Garantir que eps seja sempre > 0
            x_db = DBSCAN(eps=20, min_samples=1).fit(x_coords)
            x_labels = x_db.labels_
            
            # Agrupar bolhas horizontalmente próximas
            x_clusters = defaultdict(list)
            for i, bolha in enumerate(bolhas_ordenadas):
                x_clusters[x_labels[i]].append(bolha)
            
            # Para cada cluster horizontal, manter apenas a bolha com maior taxa de preenchimento
            bolhas_filtradas = []
            for x_cluster in x_clusters.values():
                if len(x_cluster) > 0:
                    melhor_bolha = max(x_cluster, key=lambda b: b.get('fill_rate', b.get('preenchimento', 0)))
                    bolhas_filtradas.append(melhor_bolha)
            
            # Ordenar novamente e limitar ao número esperado de alternativas
            if 'centro' in bolhas_filtradas[0]:
                bolhas_filtradas = sorted(bolhas_filtradas, key=lambda b: b['centro'][0])
            else:
                bolhas_filtradas = sorted(bolhas_filtradas, key=lambda b: b['x'])
            
            # Ainda pode haver mais que o esperado após filtragem, então limitamos
            if len(bolhas_filtradas) > num_alternativas:
                # Dividir em grupos equidistantes
                x_min = min(b['centro'][0] if 'centro' in b else b['x'] for b in bolhas_filtradas)
                x_max = max(b['centro'][0] if 'centro' in b else b['x'] for b in bolhas_filtradas)
                largura_total = x_max - x_min
                largura_grupo = largura_total / num_alternativas
                
                grupos_alternativas = [[] for _ in range(num_alternativas)]
                for bolha in bolhas_filtradas:
                    x = bolha['centro'][0] if 'centro' in bolha else bolha['x']
                    # Determinar em qual grupo esta bolha deve ficar
                    idx_grupo = min(int((x - x_min) / largura_grupo), num_alternativas - 1)
                    grupos_alternativas[idx_grupo].append(bolha)
                
                # De cada grupo, selecionar a bolha com maior preenchimento
                bolhas_finais = []
                for grupo in grupos_alternativas:
                    if grupo:
                        melhor_bolha = max(grupo, key=lambda b: b.get('fill_rate', b.get('preenchimento', 0)))
                        bolhas_finais.append(melhor_bolha)
                    else:
                        # Se algum grupo ficou vazio, tentar preenchê-lo com None
                        bolhas_finais.append(None)
                
                # Remover Nones e ordenar novamente
                bolhas_finais = [b for b in bolhas_finais if b is not None]
                if bolhas_finais and 'centro' in bolhas_finais[0]:
                    bolhas_finais = sorted(bolhas_finais, key=lambda b: b['centro'][0])
                else:
                    bolhas_finais = sorted(bolhas_finais, key=lambda b: b['x'])
                
                bolhas_ordenadas = bolhas_finais[:num_alternativas]
            else:
                bolhas_ordenadas = bolhas_filtradas[:num_alternativas]
            
        # Se há menos alternativas que o esperado, precisamos preencher com bolhas sintéticas
        elif len(bolhas_ordenadas) < num_alternativas:
            print(f"Aviso: Encontradas apenas {len(bolhas_ordenadas)} de {num_alternativas} alternativas.")
            
            # Tentar estimar posições das bolhas faltantes
            if len(bolhas_ordenadas) >= 2:
                # Calcular espaçamento horizontal médio
                x_coords = [b['centro'][0] if 'centro' in b else b['x'] for b in bolhas_ordenadas]
                x_diffs = np.diff(sorted(x_coords))
                if len(x_diffs) > 0:
                    espaco_medio = np.mean(x_diffs)
                    raio_medio = np.mean([b['radius'] for b in bolhas_ordenadas if 'radius' in b])
                    
                    # Estimar posições completas
                    x_min = min(x_coords)
                    posicoes_ideais = [x_min + i * espaco_medio for i in range(num_alternativas)]
                    
                    # Criar bolhas sintéticas para posições faltantes
                    bolhas_completas = []
                    for i, pos_x in enumerate(posicoes_ideais):
                        # Verificar se já existe uma bolha próxima a esta posição
                        bolha_existente = None
                        for bolha in bolhas_ordenadas:
                            x = bolha['centro'][0] if 'centro' in bolha else bolha['x']
                            if abs(x - pos_x) < espaco_medio * 0.3:  # Tolerância
                                bolha_existente = bolha
                                break
                        
                        if bolha_existente:
                            bolhas_completas.append(bolha_existente)
                        else:
                            # Criar uma bolha sintética com fill_rate baixo
                            y_medio = np.mean([b['centro'][1] if 'centro' in b else b['y'] for b in bolhas_ordenadas])
                            bolha_sintetica = {
                                'x': int(pos_x),
                                'y': int(y_medio),
                                'centro': (int(pos_x), int(y_medio)),
                                'radius': int(raio_medio),
                                'fill_rate': 0.0,
                                'filled': False,
                                'sintetica': True
                            }
                            bolhas_completas.append(bolha_sintetica)
                    
                    # Reordenar bolhas
                    if 'centro' in bolhas_completas[0]:
                        bolhas_ordenadas = sorted(bolhas_completas, key=lambda b: b['centro'][0])
                    else:
                        bolhas_ordenadas = sorted(bolhas_completas, key=lambda b: b['x'])
            
        questoes.append(bolhas_ordenadas)
    
    return questoes

def analisar_gabarito(questoes, num_questoes, alternativas=['A', 'B', 'C', 'D', 'E']):
    """
    Analisa as questões agrupadas para determinar respostas marcadas com regras aprimoradas.
    
    Args:
        questoes: Lista de listas de bolhas agrupadas por questão
        num_questoes: Número esperado de questões
        alternativas: Lista de alternativas possíveis
    
    Returns:
        resultados: Dicionário com resultados por questão
        confianca: Dicionário com níveis de confiança por questão
    """
    resultados = {}
    confianca = {}
    
    for q in range(1, num_questoes + 1):
        resultados[q] = None
        confianca[q] = 0.0
    
    for i, questao in enumerate(questoes):
        num_questao = i + 1
        
        if num_questao > num_questoes:
            break
            
        if not questao:
            continue
            
        # Estatísticas iniciais
        max_preenchimento = 0.0
        alt_index = -1
        second_max = 0.0
        preenchimentos = []
        
        # Listar todos os preenchimentos para análise estatística
        for j, bolha in enumerate(questao):
            if j >= len(alternativas):
                break
                
            if 'sintetica' in bolha and bolha['sintetica']:
                preenchimento = 0.0
            else:
                preenchimento = bolha.get('fill_rate', bolha.get('preenchimento', 0.0))
                
            preenchimentos.append(preenchimento)
            
            if preenchimento > max_preenchimento:
                second_max = max_preenchimento
                max_preenchimento = preenchimento
                alt_index = j
            elif preenchimento > second_max:
                second_max = preenchimento
        
        # Análise estatística para identificar outliers (bolhas marcadas)
        if preenchimentos:
            media = np.mean(preenchimentos)
            desvio = np.std(preenchimentos)
            
            # Definir threshold adaptativo
            threshold_base = 0.3  # Valor base
            
            # Se há alto contraste entre as bolhas, usamos threshold mais alto
            if max_preenchimento > 0.5 and desvio > 0.15:
                threshold = max(threshold_base, media + 1.5 * desvio)
            else:
                threshold = threshold_base
            
            # Calcular medida de confiança
            if second_max > 0:
                diferenca = max_preenchimento - second_max
                nivel_confianca = diferenca / max(max_preenchimento, 0.1)  # Normalizado
            else:
                nivel_confianca = 1.0 if max_preenchimento > threshold else 0.0
            
            nivel_confianca = min(max(nivel_confianca, 0.0), 1.0)
            
            # Determinar se há uma bolha significativamente preenchida
            if alt_index >= 0 and max_preenchimento > threshold:
                resultados[num_questao] = alternativas[alt_index]
                confianca[num_questao] = nivel_confianca
                
                # Informação para depuração
                print(f"Q{num_questao}: Alternativa {alternativas[alt_index]} selecionada com preench. {max_preenchimento:.2f} (confiança: {nivel_confianca:.2f})")
                print(f"   Preenchimentos: {[f'{p:.2f}' for p in preenchimentos]}")
            else:
                print(f"Q{num_questao}: Nenhuma alternativa atinge o threshold ({threshold:.2f}). Maior: {max_preenchimento:.2f}")
    
    return resultados, confianca

def validar_resultados(resultados, confianca, num_questoes, num_alternativas=5):
    """
    Valida e corrige resultados com baixa confiança ou padrões improváveis.
    
    Args:
        resultados: Dicionário com resultados por questão
        confianca: Dicionário com níveis de confiança por questão
        num_questoes: Número total de questões
        num_alternativas: Número de alternativas por questão
    
    Returns:
        resultados_corrigidos: Dicionário com resultados após validação
    """
    resultados_corrigidos = resultados.copy()
    
    for q in range(1, num_questoes + 1):
        if q in confianca and confianca[q] < 0.2:
            resultados_corrigidos[q] = f"{resultados[q]}?" if resultados[q] else None
    
    contagem = {'A': 0, 'B': 0, 'C': 0, 'D': 0, 'E': 0, None: 0}
    for alt in resultados.values():
        if alt in contagem:
            contagem[alt] += 1
        elif alt and alt.endswith('?'):
            base_alt = alt[0]
            if base_alt in contagem:
                contagem[base_alt] += 0.5  # Conta parcialmente
    
    total_marcadas = sum(1 for alt in resultados.values() if alt is not None)
    if total_marcadas < num_questoes * 0.5:
        print("Aviso: Menos de 50% das questões foram detectadas como marcadas.")
    
    return resultados_corrigidos

def processar_imagem_completa(imagem_path, num_questoes=10, num_alternativas=5, threshold=150, sensitivity=0.3):
    """
    Processa uma imagem de cartão resposta de forma completa, desde o pré-processamento
    até a identificação das respostas marcadas.
    
    Args:
        imagem_path: Caminho para a imagem do cartão resposta
        num_questoes: Número esperado de questões
        num_alternativas: Número de alternativas por questão
        threshold: Valor de limiar para binarização
        sensitivity: Sensibilidade para detecção de preenchimento
        
    Returns:
        resultados: Dicionário com os resultados identificados
        imagem_debug: Imagem com anotações de debug
    """
    # Carregar imagem
    image = cv2.imread(imagem_path)
    if image is None:
        raise ValueError(f"Não foi possível carregar a imagem: {imagem_path}")
    
    # Pré-processamento
    binary, normalized = melhorar_pre_processamento(image)
    
    # Tentar corrigir perspectiva
    corrected_image, corrected_binary, success = corrigir_perspectiva(image, binary)
    if success:
        image = corrected_image
        binary = corrected_binary
    
    # Criar imagem de debug
    debug_image = image.copy()
    
    # Detectar bolhas
    bolhas, debug_image = detectar_bolhas_avancado(binary, debug_image, threshold, sensitivity)
    
    # Agrupar bolhas por questões
    questoes = agrupar_bolhas_por_questoes(bolhas, num_questoes, num_alternativas)
    
    # Analisar e determinar respostas
    alternativas = ['A', 'B', 'C', 'D', 'E'][:num_alternativas]
    resultados, confianca = analisar_gabarito(questoes, num_questoes, alternativas)
    
    # Validar resultados
    resultados_validados = validar_resultados(resultados, confianca, num_questoes, num_alternativas)
    
    return resultados_validados, debug_image

# Função auxiliar para carregar e processar imagem a partir da interface
def analisar_cartao_melhorado(image, binary, debug_image, num_questoes, num_colunas, sensitivity):
    """
    Função de análise de cartão resposta para integração com UI.
    
    Args:
        image: Imagem original
        binary: Imagem binária pré-processada
        debug_image: Imagem para debug
        num_questoes: Número de questões esperado
        num_colunas: Número de colunas no cartão
        sensitivity: Sensibilidade para detecção (0.0-1.0)
        
    Returns:
        resultados: Dicionário com os resultados
    """
    # Detectar bolhas
    bolhas, debug_image = detectar_bolhas_avancado(binary, debug_image, sensitivity=sensitivity)
    
    # Dividir questões por coluna se necessário
    questoes_por_coluna = num_questoes // num_colunas
    resultados = {}
    
    if bolhas:
        # Agrupar bolhas por questões
        questoes = agrupar_bolhas_por_questoes(bolhas, num_questoes, 5)
        
        # Para cada coluna
        for col in range(num_colunas):
            # Calcular índice das questões para esta coluna
            inicio = col * questoes_por_coluna
            fim = min((col + 1) * questoes_por_coluna, len(questoes))
            
            # Analisar as questões desta coluna
            resultados_coluna, confianca = analisar_gabarito(
                questoes[inicio:fim], 
                questoes_por_coluna,
                ['A', 'B', 'C', 'D', 'E']
            )
            
            # Ajustar numeração das questões e adicionar ao resultado final
            for q, resposta in resultados_coluna.items():
                num_questao = q + col * questoes_por_coluna
                resultados[num_questao] = resposta
    
    # Inicializar questões faltantes com None
    for q in range(1, num_questoes + 1):
        if q not in resultados:
            resultados[q] = None
    
    return resultados