# analysis.py
import numpy as np
from collections import defaultdict
from sklearn.cluster import DBSCAN
import cv2
from image_processing import detectar_bolhas_avancado, agrupar_bolhas_por_questoes


def analisar_preenchimento_avancado(binary, image, bolha):
    """
    Análise avançada de preenchimento com múltiplas métricas.
    Agora EFETIVAMENTE usada no fluxo de análise para bolhas ambíguas.

    Args:
        binary: Imagem binária
        image: Imagem original (para análise de intensidade)
        bolha: Dicionário com informações da bolha

    Returns:
        resultado: Dicionário com análise detalhada
    """
    cx, cy, r = bolha['x'], bolha['y'], bolha['radius']
    h_img, w_img = binary.shape

    # Limites seguros
    x_min = max(0, cx - r)
    y_min = max(0, cy - r)
    x_max = min(w_img, cx + r)
    y_max = min(h_img, cy + r)

    # ROI circular
    mask_circular = np.zeros_like(binary)
    inner_r = int(r * 0.8)
    cv2.circle(mask_circular, (cx, cy), inner_r, 255, -1)
    roi_circular = cv2.bitwise_and(binary, mask_circular)

    # ROI retangular
    roi_rect = binary[y_min:y_max, x_min:x_max]

    # Métrica 1: Fill rate circular
    inner_area = np.pi * inner_r * inner_r
    filled_pixels_circular = cv2.countNonZero(roi_circular)
    fill_rate_circular = filled_pixels_circular / inner_area if inner_area > 0 else 0

    # Métrica 2: Fill rate retangular
    if roi_rect.size > 0:
        fill_rate_rect = cv2.countNonZero(roi_rect) / roi_rect.size
    else:
        fill_rate_rect = 0

    # Métrica 3: Intensidade média na imagem original
    intensidade_media = 0
    if image is not None:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image
        roi_gray = gray[y_min:y_max, x_min:x_max]
        if roi_gray.size > 0:
            intensidade_media = float(np.mean(roi_gray))

    # Métrica 4: Energia do gradiente (bordas fortes = preenchido ou contorno)
    if roi_rect.size > 0 and roi_rect.shape[0] > 2 and roi_rect.shape[1] > 2:
        gradiente = cv2.Sobel(roi_rect.astype(np.float32), cv2.CV_64F, 1, 1, ksize=3)
        energia_gradiente = float(np.sum(np.abs(gradiente)))
    else:
        gradiente = np.array([0])
        energia_gradiente = 0.0

    # Métrica 5: Simetria radial
    simetria = _calcular_simetria_radial(binary[y_min:y_max, x_min:x_max], 
                                          cx - x_min, cy - y_min, inner_r)

    # Classificação com pesos
    # Pesos ajustados: fill_rate circular é o mais confiável
    score = (
        fill_rate_circular * 0.50 +
        fill_rate_rect * 0.20 +
        (1.0 - min(intensidade_media / 255.0, 1.0)) * 0.15 +  # Invertido: escuro = alto
        simetria * 0.15
    )

    # Confiança baseada na clareza da decisão
    confianca = min(abs(score - 0.35) * 2.5, 1.0)

    # Classificação final
    if score > 0.45:
        estado = "marcada"
    elif score > 0.20:
        estado = "parcial"
    else:
        estado = "vazia"

    return {
        'estado': estado,
        'score': float(score),
        'confianca': float(confianca),
        'metricas': {
            'fill_rate_circular': float(fill_rate_circular),
            'fill_rate_rect': float(fill_rate_rect),
            'intensidade': float(intensidade_media),
            'simetria': float(simetria),
            'energia_gradiente': float(energia_gradiente),
        }
    }


def _calcular_simetria_radial(roi_circular, cx, cy, r):
    """Calcula a simetria radial da região."""
    try:
        if roi_circular.size == 0 or r < 3:
            return 0.5

        h, w = roi_circular.shape
        cx_local = min(max(cx, 0), w - 1)
        cy_local = min(max(cy, 0), h - 1)

        r_safe = max(1, min(r, h // 2, w // 2))

        quadrantes = []
        if cy_local - r_safe >= 0 and cx_local - r_safe >= 0:
            quadrantes.append(np.sum(roi_circular[cy_local-r_safe:cy_local, cx_local-r_safe:cx_local]))
        if cy_local - r_safe >= 0 and cx_local + r_safe < w:
            quadrantes.append(np.sum(roi_circular[cy_local-r_safe:cy_local, cx_local:cx_local+r_safe]))
        if cy_local + r_safe < h and cx_local - r_safe >= 0:
            quadrantes.append(np.sum(roi_circular[cy_local:cy_local+r_safe, cx_local-r_safe:cx_local]))
        if cy_local + r_safe < h and cx_local + r_safe < w:
            quadrantes.append(np.sum(roi_circular[cy_local:cy_local+r_safe, cx_local:cx_local+r_safe]))

        if len(quadrantes) < 4:
            return 0.5

        media_quad = np.mean(quadrantes)
        if media_quad == 0:
            return 0.5

        cv_quad = np.std(quadrantes) / media_quad
        simetria = 1.0 / (1.0 + cv_quad)
        return float(simetria)
    except:
        return 0.5


def analisar_gabarito(questoes, num_questoes, alternativas=['A', 'B', 'C', 'D', 'E'], binary=None, image=None):
    """
    Analisa as questões agrupadas usando estratégia de gap máximo.
    
    Esta é a versão PRINCIPAL usada pelo pipeline multi-colunas.
    Usa o método de "maior gap entre fill_rates consecutivos" para
    identificar a bolha marcada, que é robusto a variações de contraste.
    """
    resultados = {}
    confianca = {}
    for q in range(1, num_questoes + 1):
        resultados[q] = None
        confianca[q] = 0.0

    # --- ANÁLISE ADAPTATIVA GLOBAL ---
    todas_taxas = []
    for questao in questoes:
        for bolha in questao:
            if not bolha.get('sintetica', False):
                todas_taxas.append(bolha.get('fill_rate', 0.0))

    if todas_taxas:
        media_global = np.mean(todas_taxas)
        desvio_global = np.std(todas_taxas)

        taxas_arr = np.array(todas_taxas)
        threshold_referencia = float(np.percentile(taxas_arr, 80))
        threshold_referencia = float(np.clip(threshold_referencia, 0.55, 0.90))

        print(f"Análise Adaptativa: Média={media_global:.2f}, Desvio={desvio_global:.2f}, "
              f"Threshold_ref={threshold_referencia:.2f}")
    else:
        threshold_referencia = 0.65
        print("Aviso: Nenhuma bolha detectada para análise adaptativa. Usando threshold padrão.")

    # --- ANÁLISE POR QUESTÃO: gap máximo ---
    for i, questao in enumerate(questoes):
        num_questao = i + 1
        if num_questao > num_questoes:
            break
        if not questao:
            continue

        # 1. Coletar fill_rates com índices originais
        bolhas_com_idx = [(j, bolha.get('fill_rate', 0.0)) for j, bolha in enumerate(questao)
                         if not bolha.get('sintetica', False)]

        if not bolhas_com_idx:
            continue

        # Ordenar pelo fill_rate (decrescente)
        bolhas_sorted = sorted(bolhas_com_idx, key=lambda x: x[1], reverse=True)
        fills_sorted = [f for _, f in bolhas_sorted]

        max_fill = fills_sorted[0]
        second_fill = fills_sorted[1] if len(fills_sorted) > 1 else 0.0

        # 2. Estratégia: maior gap entre fills consecutivos
        if len(fills_sorted) >= 2:
            gaps = [fills_sorted[k] - fills_sorted[k+1] for k in range(len(fills_sorted)-1)]
            maior_gap_idx = int(np.argmax(gaps))
            candidatas_acima = bolhas_sorted[:maior_gap_idx + 1]
        else:
            candidatas_acima = bolhas_sorted
            gaps = []

        # 3. Validação: fill muito baixo → forced choice com confiança baixa
        if max_fill < threshold_referencia * 0.6:
            alt_index = bolhas_com_idx[0][0]
            resultados[num_questao] = alternativas[alt_index] if alt_index < len(alternativas) else None
            confianca[num_questao] = max(0.1, min(max_fill * 1.5, 0.3))
            print(f"Q{num_questao}: Fill muito baixo — usando máximo "
                  f"({alternativas[alt_index] if alt_index < len(alternativas) else '?'}={max_fill:.2f})")
            continue

        if len(candidatas_acima) == 1:
            # Caso ideal: apenas uma bolha acima do maior gap
            idx_orig, fill_val = candidatas_acima[0]
            gap_val = gaps[maior_gap_idx] if gaps else fill_val
            nivel_confianca = min(gap_val * 2, 1.0)
            
            # Validação Avançada
            if binary is not None and (nivel_confianca < 0.6 or fill_val < threshold_referencia):
                bolha_alvo = questao[idx_orig]
                res_adv = analisar_preenchimento_avancado(binary, image, bolha_alvo)
                if res_adv['score'] > 0.45:
                    nivel_confianca = res_adv['confianca']
                    fill_val = res_adv['score']
                else:
                    # Mesmo a única opção estava fraca
                    pass
                    
            resultados[num_questao] = alternativas[idx_orig] if idx_orig < len(alternativas) else None
            confianca[num_questao] = nivel_confianca

        elif len(candidatas_acima) > 1 and len(gaps) > 0:
            melhor_idx, melhor_fill = candidatas_acima[0]
            segunda_fill = candidatas_acima[1][1]
            gap_entre = melhor_fill - segunda_fill
            
            # --- TENTAR DESEMPATAR COM ANÁLISE AVANÇADA ---
            if binary is not None and melhor_fill - segunda_fill < 0.2:
                for idx_c, val_c in candidatas_acima:
                    idx_real = idx_c
                    if idx_real < len(questao):
                        res_adv = analisar_preenchimento_avancado(binary, image, questao[idx_real])
                        # Atualiza fill interno para o score híbrido
                        bolhas_com_idx[idx_real] = (idx_real, res_adv['score'])
                
                # Re-ordenar após analysis avançada
                candidatas_revisadas = sorted([bolhas_com_idx[idx_c] for idx_c, _ in candidatas_acima], key=lambda x: x[1], reverse=True)
                melhor_idx, melhor_fill = candidatas_revisadas[0]
                segunda_fill = candidatas_revisadas[1][1] if len(candidatas_revisadas) > 1 else 0

            # Filtro de dominância relativa revisado
            if segunda_fill > 0 and melhor_fill / segunda_fill >= 1.5:
                idx_orig = melhor_idx
                gap_val = gaps[maior_gap_idx] if maior_gap_idx < len(gaps) else melhor_fill
                nivel_confianca = min(gap_val * 2, 1.0)
                resultados[num_questao] = alternativas[idx_orig] if idx_orig < len(alternativas) else None
                confianca[num_questao] = nivel_confianca
                continue

            letras_marcadas = [alternativas[j] for j, f in candidatas_acima if j < len(alternativas)]
            nivel_confianca = min(max(gap_entre * 2, 0.0), 0.5)

            print(f"Q{num_questao}: Múltiplas candidatas ({', '.join(letras_marcadas)}), "
                  f"escolhendo {alternativas[melhor_idx] if melhor_idx < len(alternativas) else '?'} "
                  f"(fill={melhor_fill:.2f})")
            resultados[num_questao] = alternativas[melhor_idx] if melhor_idx < len(alternativas) else None
            confianca[num_questao] = nivel_confianca

        else:
            # Sem candidatas claras → forced choice
            idx_orig = bolhas_sorted[0][0]
            
            if binary is not None:
                bolha_alvo = questao[idx_orig]
                res_adv = analisar_preenchimento_avancado(binary, image, bolha_alvo)
                if res_adv['score'] > 0.45:
                    max_fill = res_adv['score']
            
            resultados[num_questao] = alternativas[idx_orig] if idx_orig < len(alternativas) else None
            confianca[num_questao] = max(0.1, min(max_fill * 2, 0.4))
            print(f"Q{num_questao}: Sem candidata clara — usando máximo "
                  f"({alternativas[idx_orig] if idx_orig < len(alternativas) else '?'}={max_fill:.2f})")

    return resultados, confianca


def validar_resultados(resultados, confianca, num_questoes, num_alternativas=5):
    """Valida e marca respostas suspeitas."""
    from collections import Counter

    resultados_corrigidos = resultados.copy()

    valores_confianca = [v for v in confianca.values() if v > 0]
    if valores_confianca:
        media_confianca = np.mean(valores_confianca)
        limite_suspeito = max(0.2, media_confianca * 0.5)
    else:
        limite_suspeito = 0.2

    for q in range(1, num_questoes + 1):
        if q in confianca and confianca[q] < limite_suspeito and resultados[q] is not None:
            resultados_corrigidos[q] = f"{resultados[q]}?"

    contagem = Counter([r for r in resultados.values() if r is not None and not str(r).endswith('?')])
    total_respostas = sum(contagem.values())

    if total_respostas >= num_questoes * 0.3:
        esperado = total_respostas / num_alternativas
        for alt, count in contagem.items():
            if count > esperado * 2.0 and count > 3:
                print(f"Aviso: Alternativa '{alt}' aparece {count} vezes (esperado ~{esperado:.1f})")
                for q in range(1, num_questoes + 1):
                    if resultados[q] == alt and confianca[q] < 0.4:
                        resultados_corrigidos[q] = f"{alt}?"

    respostas_detectadas = sum(1 for r in resultados_corrigidos.values() if r is not None)
    if respostas_detectadas < num_questoes * 0.5:
        print(f"Aviso: Apenas {respostas_detectadas} de {num_questoes} questões detectadas.")

    return resultados_corrigidos


def detectar_colunas(binary_image):
    """Detecta automaticamente o número de colunas no cartão resposta."""
    projection = np.sum(binary_image, axis=0)

    projection = projection / np.max(projection) if np.max(projection) > 0 else projection
    window_size = max(len(projection) // 100, 10)
    projection_smooth = np.convolve(projection, np.ones(window_size)/window_size, mode='same')

    valleys = []
    for i in range(1, len(projection_smooth)-1):
        if projection_smooth[i] < projection_smooth[i-1] and projection_smooth[i] < projection_smooth[i+1]:
            valleys.append((i, projection_smooth[i]))

    valleys = sorted(valleys, key=lambda x: x[1])
    significant_valleys = [v for v in valleys if v[1] < 0.3]

    if len(significant_valleys) >= 2:
        return 3
    elif len(significant_valleys) == 1:
        return 2
    else:
        return 1


def segmentar_colunas_com_bordas(binary, num_colunas):
    """
    Segmenta a imagem em colunas usando projeção vertical + detecção de retângulos.
    """
    h, w = binary.shape

    # MÉTODO 1: Projeção vertical
    projection = np.sum(binary, axis=0)

    window_size = max(w // 100, 5)
    smooth_proj = np.convolve(projection, np.ones(window_size)/window_size, mode='same')

    max_val = np.max(smooth_proj)
    smooth_proj = smooth_proj / max_val if max_val > 0 else smooth_proj

    threshold = 0.2
    valleys = []

    for i in range(window_size, len(smooth_proj)-window_size):
        if smooth_proj[i] < threshold:
            window = 20
            left_max = max(smooth_proj[max(0, i-window):i]) if i > 0 else 0
            right_max = max(smooth_proj[i+1:min(len(smooth_proj), i+window+1)]) if i < len(smooth_proj)-1 else 0

            if smooth_proj[i] <= left_max * 0.7 and smooth_proj[i] <= right_max * 0.7:
                valleys.append(i)

    # MÉTODO 2: Detecção de retângulos/contornos
    kernel = np.ones((5, 5), np.uint8)
    morph = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)

    contours, _ = cv2.findContours(morph, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    min_area = (h * w) / (num_colunas * 10)
    valid_contours = [cnt for cnt in contours if cv2.contourArea(cnt) > min_area]

    rectangles = []
    for cnt in valid_contours:
        epsilon = 0.02 * cv2.arcLength(cnt, True)
        approx = cv2.approxPolyDP(cnt, epsilon, True)

        if len(approx) >= 4 and len(approx) <= 8:
            x, y, w_rect, h_rect = cv2.boundingRect(cnt)
            if h_rect > h/2:
                rectangles.append((x, x + w_rect))

    rectangles.sort(key=lambda r: r[0])

    # MÉTODO 3: Combinar
    if len(rectangles) >= num_colunas:
        merged_rectangles = []
        current_group = rectangles[0]

        for i in range(1, len(rectangles)):
            if rectangles[i][0] - current_group[1] < w * 0.05:
                current_group = (current_group[0], max(current_group[1], rectangles[i][1]))
            else:
                merged_rectangles.append(current_group)
                current_group = rectangles[i]

        merged_rectangles.append(current_group)

        if len(merged_rectangles) > num_colunas:
            merged_rectangles.sort(key=lambda r: r[1] - r[0], reverse=True)
            merged_rectangles = merged_rectangles[:num_colunas]
            merged_rectangles.sort(key=lambda r: r[0])

        if len(merged_rectangles) < num_colunas:
            if valleys:
                valleys.sort()
                for valley in valleys:
                    is_valid = True
                    for rect in merged_rectangles:
                        if rect[0] <= valley <= rect[1]:
                            is_valid = False
                            break

                    if is_valid:
                        pos = 0
                        while pos < len(merged_rectangles) and merged_rectangles[pos][0] < valley:
                            pos += 1

                        if pos > 0 and pos < len(merged_rectangles):
                            left_rect = merged_rectangles[pos-1]
                            right_rect = merged_rectangles[pos]
                            merged_rectangles[pos-1] = (left_rect[0], valley)
                            merged_rectangles.insert(pos, (valley, right_rect[1]))

                        if len(merged_rectangles) >= num_colunas:
                            break

        rectangles = merged_rectangles

    if len(rectangles) < num_colunas:
        if len(valleys) >= num_colunas - 1:
            valleys.sort()

            if len(valleys) > num_colunas - 1:
                selected_valleys = []
                valleys_copy = list(valleys)

                for i in range(num_colunas - 1):
                    target_pos = (i + 1) * w / num_colunas
                    best_valley = min(valleys_copy, key=lambda v: abs(v - target_pos))
                    selected_valleys.append(best_valley)
                    valleys_copy = [v for v in valleys_copy if abs(v - best_valley) > w * 0.05]
                    if not valleys_copy:
                        break

                valleys = sorted(selected_valleys)

            regioes = []
            inicio = 0

            for v in valleys[:num_colunas-1]:
                regioes.append((inicio, v))
                inicio = v

            regioes.append((inicio, w))
            return regioes

    if len(rectangles) == num_colunas:
        return rectangles

    # Fallback: divisão uniforme
    divisoes = []

    if rectangles:
        for i, (start, end) in enumerate(rectangles):
            if i == 0 and start > 0:
                divisoes.append((0, start))
            divisoes.append((start, end))
            if i < len(rectangles) - 1 and end < rectangles[i+1][0]:
                divisoes.append((end, rectangles[i+1][0]))
        if rectangles[-1][1] < w:
            divisoes.append((rectangles[-1][1], w))

    if not divisoes or len(divisoes) != num_colunas:
        return [(i * w // num_colunas, (i+1) * w // num_colunas) for i in range(num_colunas)]

    while len(divisoes) > num_colunas:
        min_width = float('inf')
        min_index = 0

        for i in range(len(divisoes) - 1):
            width = divisoes[i+1][1] - divisoes[i][0]
            if width < min_width:
                min_width = width
                min_index = i

        divisoes[min_index] = (divisoes[min_index][0], divisoes[min_index+1][1])
        divisoes.pop(min_index + 1)

    return divisoes


class CartaoRespostaAnalyzer:
    def __init__(self):
        self.alternativas = ['A', 'B', 'C', 'D', 'E']

    def analisar_cartao_melhorado(self, image, binary, debug_image, num_questoes, num_colunas, sensitivity):
        resultados = {}
        h, w = binary.shape

        if binary.max() <= 1.0:
            binary_proc = (binary * 255).astype(np.uint8)
        else:
            binary_proc = binary.copy()

        # Quando é coluna individual (já segmentada), processar direto
        if num_colunas <= 1:
            return self.analisar_cartao_fallback(image, binary, debug_image, num_questoes, num_colunas, sensitivity)

        # Para imagem completa: tentar detecção de retângulo
        contornos, _ = cv2.findContours(binary_proc, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        potenciais_retangulos = []

        for contorno in contornos:
            area = cv2.contourArea(contorno)
            perimetro = cv2.arcLength(contorno, True)
            if area < 1000:
                continue
            approx = cv2.approxPolyDP(contorno, 0.02 * perimetro, True)
            if 4 <= len(approx) <= 8:
                potenciais_retangulos.append(approx)

        if potenciais_retangulos:
            potenciais_retangulos.sort(key=cv2.contourArea, reverse=True)
            retangulo_cartao = potenciais_retangulos[0]
            x, y, w, h = cv2.boundingRect(retangulo_cartao)

            x = max(0, x)
            y = max(0, y)
            w = min(w, binary.shape[1] - x)
            h = min(h, binary.shape[0] - y)

            cv2.rectangle(debug_image, (x, y), (x+w, y+h), (0, 255, 0), 2)

            if w > 0 and h > 0:
                roi_cartao = binary_proc[y:y+h, x:x+w]
                roi_debug = debug_image[y:y+h, x:x+w]

                bolhas, debug_area = detectar_bolhas_avancado(roi_cartao, roi_debug, sensitivity=sensitivity)
                debug_image[y:y+h, x:x+w] = debug_area

                for bolha in bolhas:
                    bolha['centro'] = (bolha['centro'][0] + x, bolha['centro'][1] + y)
                    bolha['x'] += x
                    bolha['y'] += y

                if bolhas:
                    questoes = agrupar_bolhas_por_questoes(bolhas, num_questoes, 5)
                    resultados, confianca_res = analisar_gabarito(questoes, num_questoes, self.alternativas, binary=roi_cartao, image=image[y:y+h, x:x+w])

                    for i, questao in enumerate(questoes):
                        if i >= num_questoes: break
                        num_questao = i + 1
                        resposta = resultados.get(num_questao)

                        if "ERRO" in str(resposta):
                            cor = (0, 0, 255)
                        elif resposta is not None:
                            cor = (0, 255, 0)
                        else:
                            cor = (255, 0, 0)

                        for j, bolha in enumerate(questao):
                            if j >= 5: break
                            cv2.circle(debug_image, bolha['centro'], bolha['radius'], cor, 2)
                            alt_letra = self.alternativas[j]
                            cv2.putText(debug_image, alt_letra, 
                                       (bolha['centro'][0] - 5, bolha['centro'][1] + 5), 
                                       cv2.FONT_HERSHEY_SIMPLEX, 0.7, cor, 2)
                else:
                    for i in range(1, num_questoes + 1):
                        resultados[i] = None
        else:
            return self.analisar_cartao_fallback(image, binary, debug_image, num_questoes, num_colunas, sensitivity)

        for i in range(1, num_questoes + 1):
            if i not in resultados:
                resultados[i] = None
        return resultados

    def analisar_cartao_fallback(self, image, binary, debug_image, num_questoes, num_colunas, sensitivity):
        resultados = {i: None for i in range(1, num_questoes + 1)}

        if binary.max() <= 1.0:
            binary_proc = (binary * 255).astype(np.uint8)
        else:
            binary_proc = binary.copy()

        bolhas, debug_img = detectar_bolhas_avancado(binary_proc, debug_image, sensitivity=sensitivity)

        debug_image[:] = debug_img[:]

        if bolhas:
            questoes = agrupar_bolhas_por_questoes(bolhas, num_questoes, len(self.alternativas))
            resultados_analise, confianca_res = analisar_gabarito(questoes, num_questoes, self.alternativas, binary=binary_proc, image=image)
            resultados = validar_resultados(resultados_analise, confianca_res, num_questoes)
        return resultados


class MultiColumnCartaoAnalyzer:
    def __init__(self, analyzer):
        self.analyzer = analyzer
        self.alternativas = ['A', 'B', 'C', 'D', 'E']

    def criar_visualizacao_simplificada(self, clean_image, resultados, binary, num_colunas):
        from image_processing import detectar_retangulos_colunas, detectar_bolhas_avancado
        
        h, w = binary.shape
        
        # Tentar usar retângulos detectados
        # Nota: não temos acesso à image original aqui, criar uma versão gray
        gray_bin = binary  # já é binária
        
        num_questoes = len(resultados)
        if num_colunas == 2:
            questoes_por_coluna = [(num_questoes + 1) // 2, num_questoes // 2]
        elif num_colunas == 3:
            base = num_questoes // 3
            resto = num_questoes % 3
            questoes_por_coluna = [base + (1 if i < resto else 0) for i in range(3)]
        else:
            base = num_questoes // num_colunas
            resto = num_questoes % num_colunas
            questoes_por_coluna = [base + (1 if i < resto else 0) for i in range(num_colunas)]

        # Usar segmentação por bordas como fallback
        regioes_colunas = segmentar_colunas_com_bordas(binary, num_colunas)
        
        questao_atual = 1

        for idx, (x_inicio, x_fim) in enumerate(regioes_colunas):
            if idx >= len(questoes_por_coluna):
                break

            x_inicio = max(0, min(x_inicio, w-1))
            x_fim = max(0, min(x_fim, w))

            if x_fim <= x_inicio:
                continue

            coluna_bin = binary[:, x_inicio:x_fim]

            if coluna_bin.max() <= 1.0:
                coluna_bin_proc = (coluna_bin * 255).astype(np.uint8)
            else:
                coluna_bin_proc = coluna_bin.copy()

            bolhas_coluna, _ = detectar_bolhas_avancado(coluna_bin_proc, None, sensitivity=0.1)

            for bolha in bolhas_coluna:
                bolha['x'] += x_inicio
                if 'centro' in bolha:
                    cx, cy = bolha['centro']
                    bolha['centro'] = (cx + x_inicio, cy)

            questoes_nesta_coluna = questoes_por_coluna[idx]
            from image_processing import agrupar_bolhas_por_questoes
            questoes_agrupadas = agrupar_bolhas_por_questoes(bolhas_coluna, questoes_nesta_coluna, 5)

            for i, bolhas_questao in enumerate(questoes_agrupadas):
                num_questao = questao_atual + i
                resposta = resultados.get(num_questao)

                if resposta is None or '?' in str(resposta):
                    continue

                try:
                    alt_index = self.alternativas.index(resposta[0] if isinstance(resposta, str) else resposta)
                except ValueError:
                    continue

                if alt_index < 0 or alt_index >= len(bolhas_questao):
                    continue

                bolha = bolhas_questao[alt_index]

                cv2.circle(clean_image,
                          (bolha['centro'][0], bolha['centro'][1]),
                          bolha['radius'],
                          (0, 255, 0),
                          -1)

            questao_atual += questoes_nesta_coluna

    def analisar_cartao_multicolunas(self, image, binary, debug_image, num_questoes, num_colunas, sensitivity, threshold=150, return_debug_image=False):
        """
        v2: Usa detecção de retângulos impressos como âncora para as colunas.
        Fallback para segmentação por projeção se retângulos não forem encontrados.
        """
        from image_processing import detectar_retangulos_colunas
        
        h, w = binary.shape
        resultados = {}

        clean_image = image.copy()
        clean_debug = cv2.cvtColor(clean_image, cv2.COLOR_BGR2RGB)

        if num_colunas <= 1:
            resultados = self.analyzer.analisar_cartao_melhorado(
                image, binary, debug_image, num_questoes, num_colunas, sensitivity
            )
            self.criar_visualizacao_simplificada(clean_debug, resultados, binary, num_colunas)

            if return_debug_image:
                return resultados, clean_debug
            return resultados

        # === NOVO: Tentar detectar retângulos impressos ===
        retangulos = detectar_retangulos_colunas(binary, image, num_colunas)
        
        if retangulos is not None:
            # Usar retângulos detectados como ROI para cada coluna
            print(f"  Usando retângulos detectados: {retangulos}")
            
            if num_colunas == 2:
                questoes_por_coluna = [(num_questoes + 1) // 2, num_questoes // 2]
            elif num_colunas == 3:
                base = num_questoes // 3
                resto = num_questoes % 3
                questoes_por_coluna = [base + (1 if i < resto else 0) for i in range(3)]
            else:
                base = num_questoes // num_colunas
                resto = num_questoes % num_colunas
                questoes_por_coluna = [base + (1 if i < resto else 0) for i in range(num_colunas)]

            print(f"Divisão de questões por coluna: {questoes_por_coluna}")
            
            questao_atual = 1
            
            for idx, (rx, ry, rw, rh) in enumerate(retangulos):
                if idx >= len(questoes_por_coluna):
                    break
                
                # Adicionar margem pequena
                margin = int(min(rw, rh) * 0.02)
                rx = max(0, rx - margin)
                ry = max(0, ry - margin)
                rw = min(rw + 2*margin, w - rx)
                rh = min(rh + 2*margin, h - ry)
                
                coluna_bin = binary[ry:ry+rh, rx:rx+rw]
                coluna_img = image[ry:ry+rh, rx:rx+rw].copy()
                coluna_debug = debug_image[ry:ry+rh, rx:rx+rw]
                
                questoes_nesta_coluna = questoes_por_coluna[idx]
                
                if questoes_nesta_coluna <= 0:
                    continue
                
                # Garantir binary no range correto
                if coluna_bin.max() <= 1.0:
                    coluna_bin = (coluna_bin * 255).astype(np.uint8)
                
                resultados_coluna = self.analyzer.analisar_cartao_fallback(
                    coluna_img, coluna_bin, coluna_debug,
                    questoes_nesta_coluna, 1, sensitivity
                )
                
                debug_image[ry:ry+rh, rx:rx+rw] = coluna_debug
                
                for q, resposta in resultados_coluna.items():
                    if q <= questoes_nesta_coluna:
                        resultados[questao_atual + q - 1] = resposta
                
                questao_atual += questoes_nesta_coluna
            
        else:
            # === FALLBACK: Segmentação por projeção vertical ===
            print("  ⚠️ Fallback: usando segmentação por projeção vertical")
            
            regioes_colunas = segmentar_colunas_com_bordas(binary, num_colunas)

            if num_colunas == 2:
                questoes_por_coluna = [(num_questoes + 1) // 2, num_questoes // 2]
            elif num_colunas == 3:
                base = num_questoes // 3
                resto = num_questoes % 3
                questoes_por_coluna = [base + (1 if i < resto else 0) for i in range(3)]
            else:
                base = num_questoes // num_colunas
                resto = num_questoes % num_colunas
                questoes_por_coluna = [base + (1 if i < resto else 0) for i in range(num_colunas)]

            print(f"Divisão de questões por coluna: {questoes_por_coluna}")

            questao_atual = 1

            for idx, (x_inicio, x_fim) in enumerate(regioes_colunas):
                if idx >= len(questoes_por_coluna):
                    break

                x_inicio = max(0, min(x_inicio, w-1))
                x_fim = max(0, min(x_fim, w))

                if x_fim <= x_inicio:
                    continue

                coluna_bin = binary[:, x_inicio:x_fim]
                coluna_img = image[:, x_inicio:x_fim].copy()
                coluna_debug = debug_image[:, x_inicio:x_fim]

                questoes_nesta_coluna = questoes_por_coluna[idx]

                if questoes_nesta_coluna <= 0:
                    continue

                resultados_coluna = self.analyzer.analisar_cartao_melhorado(
                    coluna_img,
                    coluna_bin,
                    coluna_debug,
                    questoes_nesta_coluna, 1, sensitivity
                )

                debug_image[:, x_inicio:x_fim] = coluna_debug

                for q, resposta in resultados_coluna.items():
                    if q <= questoes_nesta_coluna:
                        resultados[questao_atual + q - 1] = resposta

                questao_atual += questoes_nesta_coluna

        # Preencher questões faltantes
        for q in range(1, num_questoes + 1):
            if q not in resultados:
                resultados[q] = None

        self.criar_visualizacao_simplificada(clean_debug, resultados, binary, num_colunas)

        if return_debug_image:
            return resultados, clean_debug

        return resultados