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
    Agrupa bolhas por questões usando clustering adaptativo.
    
    Args:
        bolhas: Lista de dicionários com informações das bolhas
        num_questoes: Número esperado de questões
        num_alternativas: Número esperado de alternativas por questão
    
    Returns:
        questoes: Lista de listas de bolhas agrupadas por questão
    """
    import numpy as np
    from collections import defaultdict
    from sklearn.cluster import DBSCAN

    if not bolhas:
        return []
    
    # Extrair centros das bolhas para clustering
    if 'centro' in bolhas[0]:
        centros = np.array([bolha['centro'] for bolha in bolhas])
    else:
        centros = np.array([[bolha['x'], bolha['y']] for bolha in bolhas])
    
    # Análise preliminar de distribuição dos pontos para configurar melhor o DBSCAN
    y_coords = np.array([c[1] for c in centros])
    y_sorted = np.sort(y_coords)
    y_diffs = np.diff(y_sorted)
    
    # Adaptação automática do epsilon baseada na estrutura do documento
    if len(y_diffs) > 0:
        # Análise da distribuição vertical para determinar o agrupamento
        # Usar percentil para reduzir influência de outliers
        epsilon = np.percentile(y_diffs, 25) * 0.75  # 75% do primeiro quartil
        epsilon = max(epsilon, 10.0)  # Mínimo de 10 pixels para evitar micro-agrupamentos
    else:
        epsilon = 20.0  # Valor padrão para poucos pontos
    
    # Agrupar pontos verticalmente (por linhas/questões)
    y_only = y_coords.reshape(-1, 1)
    db = DBSCAN(eps=epsilon, min_samples=min(2, len(bolhas)//num_questoes)).fit(y_only)
    
    # Lidar com casos onde DBSCAN produz mais clusters que questões esperadas
    labels = db.labels_
    unique_labels = np.unique(labels)
    num_clusters = len(unique_labels) - (1 if -1 in unique_labels else 0)
    
    # Se temos significativamente mais clusters que questões, ajustar epsilon e recalcular
    if num_clusters > num_questoes * 1.5 and num_clusters > 1:
        # Aumentar epsilon gradualmente
        epsilon *= 1.5
        db = DBSCAN(eps=epsilon, min_samples=min(2, len(bolhas)//num_questoes)).fit(y_only)
        labels = db.labels_
    
    # Agrupar bolhas por clusters
    clusters = defaultdict(list)
    for i, bolha in enumerate(bolhas):
        if labels[i] != -1:  # Ignorar outliers
            clusters[labels[i]].append(bolha)
    
    # Ordenar clusters por posição vertical
    sorted_clusters = sorted(
        clusters.values(),
        key=lambda cluster: np.mean([b['centro'][1] if 'centro' in b else b['y'] for b in cluster])
    )
    
    # Verificação para caso de falta ou excesso de clusters
    if len(sorted_clusters) != num_questoes:
        print(f"Aviso: Detectadas {len(sorted_clusters)} linhas de questões (esperado {num_questoes}).")
        
        # Caso 1: Mais clusters que questões esperadas
        if len(sorted_clusters) > num_questoes:
            # Manter apenas os clusters mais populosos ou melhor formados
            clusters_scores = []
            for cluster in sorted_clusters:
                # Calcular score baseado em número de bolhas e alinhamento horizontal
                num_bolhas = len(cluster)
                if num_bolhas >= num_alternativas:
                    # Calcular variância das coordenadas X para ver se estão bem alinhadas horizontalmente
                    x_coords = [b['centro'][0] if 'centro' in b else b['x'] for b in cluster]
                    # Calcular distâncias entre pontos consecutivos ordenados
                    x_sorted = np.sort(x_coords)
                    x_diffs = np.diff(x_sorted)
                    # Calcular desvio padrão das diferenças (quanto menor, mais uniforme)
                    x_std = np.std(x_diffs) if len(x_diffs) > 0 else float('inf')
                    score = num_bolhas / (1 + x_std/100)  # Score maior para mais bolhas e menor variância
                else:
                    score = num_bolhas / num_alternativas  # Score proporcional para clusters incompletos
                
                clusters_scores.append((cluster, score))
            
            # Ordenar clusters por score e manter apenas os melhores
            sorted_clusters = [c for c, _ in sorted(clusters_scores, key=lambda x: x[1], reverse=True)[:num_questoes]]
            # Reordenar verticalmente
            sorted_clusters = sorted(
                sorted_clusters,
                key=lambda cluster: np.mean([b['centro'][1] if 'centro' in b else b['y'] for b in cluster])
            )
        
        # Caso 2: Menos clusters que questões esperadas
        # Neste caso, mantemos o que temos e processamos normalmente
        # O código que recebe o resultado precisará lidar com questões faltantes
    
    # Limitar ao número de questões esperado
    sorted_clusters = sorted_clusters[:num_questoes]
    
    questoes = []
    for cluster in sorted_clusters:
        # Ordenar bolhas horizontalmente
        if not cluster:
            questoes.append([])
            continue
            
        if 'centro' in cluster[0]:
            bolhas_ordenadas = sorted(cluster, key=lambda b: b['centro'][0])
        else:
            bolhas_ordenadas = sorted(cluster, key=lambda b: b['x'])
        
        # Se há mais alternativas que o esperado, filtrar
        if len(bolhas_ordenadas) > num_alternativas:
            # Cálculo de divisão horizontal equidistante
            x_min = min(b['centro'][0] if 'centro' in b else b['x'] for b in bolhas_ordenadas)
            x_max = max(b['centro'][0] if 'centro' in b else b['x'] for b in bolhas_ordenadas)
            largura_total = max(1, x_max - x_min)  # Evitar divisão por zero
            largura_grupo = largura_total / num_alternativas
            
            # Agrupar bolhas em buckets equidistantes
            buckets = [[] for _ in range(num_alternativas)]
            for bolha in bolhas_ordenadas:
                x = bolha['centro'][0] if 'centro' in bolha else bolha['x']
                # Calcular em qual bucket a bolha pertence
                idx = min(int((x - x_min) / largura_grupo), num_alternativas - 1)
                buckets[idx].append(bolha)
            
            # Selecionar a melhor bolha de cada bucket (maior taxa de preenchimento)
            bolhas_selecionadas = []
            for bucket in buckets:
                if bucket:
                    melhor_bolha = max(bucket, 
                                      key=lambda b: b.get('fill_rate', b.get('preenchimento', 0)))
                    bolhas_selecionadas.append(melhor_bolha)
            
            bolhas_ordenadas = sorted(bolhas_selecionadas, 
                                     key=lambda b: b['centro'][0] if 'centro' in b else b['x'])
        
        # Se há menos alternativas que o esperado, preencher com bolhas sintéticas
        if len(bolhas_ordenadas) < num_alternativas:
            # Calcular o espaçamento horizontal ideal se tivermos pelo menos 2 bolhas
            if len(bolhas_ordenadas) >= 2:
                x_coords = [b['centro'][0] if 'centro' in b else b['x'] for b in bolhas_ordenadas]
                x_sorted = np.sort(x_coords)
                x_diffs = np.diff(x_sorted)
                if len(x_diffs) > 0:
                    espaco_medio = np.mean(x_diffs)
                    y_medio = np.mean([b['centro'][1] if 'centro' in b else b['y'] for b in bolhas_ordenadas])
                    raio_medio = np.mean([b.get('radius', 10) for b in bolhas_ordenadas])
                    
                    # Estimar todas as posições esperadas
                    x_coords_esperados = []
                    # Encontrar a posição inicial mais provável
                    if len(x_coords) >= num_alternativas:
                        # Se temos bolhas suficientes, usar as primeiras como base
                        inicio = np.min(x_coords)
                    else:
                        # Caso contrário, estimar pelas distâncias
                        possiveis_inicios = [x_sorted[0] - i * espaco_medio for i in range(num_alternativas)]
                        # Escolher o início que faz mais sentido (bolhas existentes se encaixam melhor)
                        melhor_inicio = x_sorted[0]
                        melhor_score = float('inf')
                        
                        for inicio in possiveis_inicios:
                            posicoes = [inicio + i * espaco_medio for i in range(num_alternativas)]
                            # Calcular erro como soma das distâncias mínimas
                            erros = []
                            for pos in posicoes:
                                min_dist = min([abs(pos - x) for x in x_coords], default=float('inf'))
                                erros.append(min_dist)
                            score = sum(erros)
                            if score < melhor_score:
                                melhor_score = score
                                melhor_inicio = inicio
                        
                        inicio = max(0, melhor_inicio)  # Garantir que não seja negativo
                    
                    # Gerar posições esperadas
                    x_coords_esperados = [inicio + i * espaco_medio for i in range(num_alternativas)]
                    
                    # Criar mapeamento das posições existentes para esperadas
                    bolhas_completas = []
                    bolhas_usadas = set()
                    
                    for x_esperado in x_coords_esperados:
                        # Encontrar a bolha mais próxima desta posição esperada
                        melhor_bolha = None
                        menor_distancia = float('inf')
                        
                        for i, bolha in enumerate(bolhas_ordenadas):
                            if i in bolhas_usadas:
                                continue
                                
                            x_atual = bolha['centro'][0] if 'centro' in bolha else bolha['x']
                            distancia = abs(x_atual - x_esperado)
                            
                            # Considerar apenas bolhas próximas o suficiente
                            if distancia < espaco_medio * 0.5 and distancia < menor_distancia:
                                menor_distancia = distancia
                                melhor_bolha = bolha
                        
                        if melhor_bolha:
                            # Adicionar bolha existente
                            idx = bolhas_ordenadas.index(melhor_bolha)
                            bolhas_usadas.add(idx)
                            bolhas_completas.append(melhor_bolha)
                        else:
                            # Adicionar bolha sintética
                            bolha_sintetica = {
                                'x': int(x_esperado),
                                'y': int(y_medio),
                                'centro': (int(x_esperado), int(y_medio)),
                                'radius': int(raio_medio),
                                'fill_rate': 0.0,
                                'filled': False,
                                'sintetica': True
                            }
                            bolhas_completas.append(bolha_sintetica)
                    
                    # Usar as bolhas complementadas
                    if bolhas_completas:
                        bolhas_ordenadas = sorted(bolhas_completas, 
                                                key=lambda b: b['centro'][0] if 'centro' in b else b['x'])
        
        questoes.append(bolhas_ordenadas[:num_alternativas])
    
    return questoes

def analisar_gabarito(questoes, num_questoes, alternativas=['A', 'B', 'C', 'D', 'E']):
    """
    Analisa as questões agrupadas para determinar respostas marcadas com análise estatística robusta.
    
    Args:
        questoes: Lista de listas de bolhas agrupadas por questão
        num_questoes: Número esperado de questões
        alternativas: Lista de alternativas possíveis
    
    Returns:
        resultados: Dicionário com resultados por questão
        confianca: Dicionário com níveis de confiança por questão
    """
    import numpy as np
    
    resultados = {}
    confianca = {}
    
    # Inicializar resultados
    for q in range(1, num_questoes + 1):
        resultados[q] = None
        confianca[q] = 0.0
    
    # Estatísticas globais para análise adaptativa
    todas_taxas = []
    for questao in questoes:
        for bolha in questao:
            if 'sintetica' not in bolha or not bolha['sintetica']:
                taxa = bolha.get('fill_rate', bolha.get('preenchimento', 0.0))
                todas_taxas.append(taxa)
    
    # Determinar threshold adaptativo com base em todas as bolhas
    if todas_taxas:
        media_global = np.mean(todas_taxas)
        desvio_global = np.std(todas_taxas)
        # Threshold base ajustado à distribuição dos dados
        threshold_base = max(0.3, media_global + 0.5 * desvio_global)
    else:
        threshold_base = 0.3  # Valor padrão se não houver dados
    
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
        
        # Coletar todos os preenchimentos para análise
        for j, bolha in enumerate(questao):
            if j >= len(alternativas):
                break
                
            # Ignorar bolhas sintéticas na avaliação
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
        
        # Análise estatística para identificar marcações
        if preenchimentos:
            # Análise específica da questão
            media_questao = np.mean(preenchimentos)
            desvio_questao = np.std(preenchimentos)
            
            # Definir threshold de forma adaptativa
            if desvio_questao > 0.1 and max_preenchimento > 0.4:
                # Alta variação e preenchimento significativo: provavelmente há uma resposta
                threshold = media_questao + 0.8 * desvio_questao
            else:
                # Baixa variação ou preenchimento fraco: usar threshold base mais rigoroso
                threshold = max(threshold_base, media_questao + 1.0 * desvio_questao)
            
            # Calcular medida de confiança normalizada
            if second_max > 0:
                # Diferença normalizada entre os dois maiores valores
                diferenca_norm = (max_preenchimento - second_max) / max(max_preenchimento, 0.1)
                nivel_confianca = min(1.0, diferenca_norm * 2)  # Multiplicador para destacar diferenças
            else:
                nivel_confianca = 1.0 if max_preenchimento > threshold else 0.0
            
            nivel_confianca = min(max(nivel_confianca, 0.0), 1.0)  # Limitar entre 0 e 1
            
            # Determinar se há uma bolha significativamente preenchida
            if alt_index >= 0 and max_preenchimento > threshold:
                resultados[num_questao] = alternativas[alt_index]
                confianca[num_questao] = nivel_confianca
                # Para debug
                if len(preenchimentos) > 1:
                    taxa_formatada = [f"{p:.2f}" for p in preenchimentos]
                    print(f"Q{num_questao}: Alternativa {alternativas[alt_index]} (preench. {max_preenchimento:.2f}, conf. {nivel_confianca:.2f}, threshold {threshold:.2f})")
                    print(f"   Preenchimentos: {taxa_formatada}")
            else:
                # Para debug
                print(f"Q{num_questao}: Nenhuma alternativa atinge o threshold ({threshold:.2f}). Maior: {max_preenchimento:.2f}")
    
    return resultados, confianca

def validar_resultados(resultados, confianca, num_questoes, num_alternativas=5):
    """
    Valida e corrige resultados com análise estatística e detecção de anomalias.
    
    Args:
        resultados: Dicionário com resultados por questão
        confianca: Dicionário com níveis de confiança por questão
        num_questoes: Número total de questões
        num_alternativas: Número de alternativas por questão
    
    Returns:
        resultados_corrigidos: Dicionário com resultados após validação
    """
    import numpy as np
    from collections import Counter
    
    resultados_corrigidos = resultados.copy()
    
    # Análise de confiança
    valores_confianca = [v for v in confianca.values() if v > 0]
    if valores_confianca:
        media_confianca = np.mean(valores_confianca)
        limite_suspeito = max(0.2, media_confianca * 0.5)  # Adapta ao conjunto de dados
    else:
        limite_suspeito = 0.2  # Valor default
    
    # Marcar respostas com baixa confiança
    for q in range(1, num_questoes + 1):
        if q in confianca and confianca[q] < limite_suspeito and resultados[q] is not None:
            resultados_corrigidos[q] = f"{resultados[q]}?"
    
    # Estatísticas de distribuição de respostas
    contagem = Counter([r for r in resultados.values() if r is not None and not r.endswith('?')])
    total_respostas = sum(contagem.values())
    
    # Verificar se a distribuição está muito desequilibrada
    if total_respostas >= num_questoes * 0.3:  # Se temos pelo menos 30% de respostas
        # Calcular distribuição esperada (aproximadamente uniforme)
        esperado_por_alternativa = total_respostas / num_alternativas
        
        # Verificar alternativas com ocorrência muito acima do esperado
        for alt, count in contagem.items():
            if count > esperado_por_alternativa * 2.0 and count > 3:
                # Alternativa com frequência suspeita (mais do que o dobro do esperado)
                print(f"Aviso: Alternativa '{alt}' aparece {count} vezes (esperado ~{esperado_por_alternativa:.1f})")
                
                # Revisar respostas com essa alternativa e baixa confiança
                for q in range(1, num_questoes + 1):
                    if resultados[q] == alt and confianca[q] < 0.4:
                        resultados_corrigidos[q] = f"{alt}?"  # Marcar como suspeita
    
    # Verificar se número total de respostas detectadas é razoável
    respostas_detectadas = sum(1 for r in resultados_corrigidos.values() if r is not None)
    if respostas_detectadas < num_questoes * 0.5:
        print(f"Aviso: Apenas {respostas_detectadas} de {num_questoes} questões foram detectadas como marcadas.")
    
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