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
    Analisa as questões agrupadas usando intensidade relativa intra-linha.

    ABORDAGEM PRINCIPAL — Comparação Relativa:
    Para cada questão (linha de 5 bolhas), normaliza os fill_rates pelo
    máximo local da linha. A bolha com maior valor normalizado é a marcada,
    independente do valor absoluto. Isso elimina o efeito de sombras e
    iluminação desuniforme que afeta todas as bolhas de uma linha igualmente.

    Score de separação = (max_fill - second_max_fill) / max_fill
    → score < 0.15: candidatos muito próximos → questão de "baixa confiança"

    ABORDAGEM SECUNDÁRIA (fallback):
    Para score < 0.10, aciona analisar_preenchimento_avancado para desempatar
    as 2 melhores candidatas via análise morfológica (fill_rate circular,
    simetria radial, gradiente).

    Returns:
        resultados:               dict {num_questao: letra | None}
        confianca:                dict {num_questao: float}
        questoes_baixa_confianca: list[dict] com questao, score e candidatos
    """
    resultados = {q: None for q in range(1, num_questoes + 1)}
    confianca = {q: 0.0 for q in range(1, num_questoes + 1)}
    questoes_baixa_confianca = []

    # --- DIAGNÓSTICO GLOBAL (para log e threshold de fallback) ---
    todas_taxas = []
    for questao in questoes:
        for bolha in questao:
            if not bolha.get('sintetica', False):
                todas_taxas.append(bolha.get('fill_rate', 0.0))

    if todas_taxas:
        media_global = float(np.mean(todas_taxas))
        desvio_global = float(np.std(todas_taxas))
        taxas_arr = np.array(todas_taxas)
        threshold_referencia = float(np.clip(np.percentile(taxas_arr, 80), 0.55, 0.90))
        print(f"Análise Adaptativa: Média={media_global:.2f}, Desvio={desvio_global:.2f}, "
              f"Threshold_ref={threshold_referencia:.2f}")
    else:
        media_global = desvio_global = 0.0
        threshold_referencia = 0.65
        print("Aviso: Nenhuma bolha detectada para análise adaptativa. Usando threshold padrão.")

    # --- ANÁLISE POR QUESTÃO: intensidade relativa intra-linha ---
    for i, questao in enumerate(questoes):
        num_questao = i + 1
        if num_questao > num_questoes:
            break
        if not questao:
            continue

        bolhas_reais = [b for b in questao if not b.get('sintetica', False)]
        if not bolhas_reais:
            continue

        # === MÉTODO PRIMÁRIO: Máximo Fill Rate ===
        # Encontra a bolha com maior preenchimento (fill_rate)
        # Se houver múltiplas com fill alto, marca como baixa confiança
        fills = [b.get('fill_rate', 0.0) for b in questao if not b.get('sintetica', False)]

        if not fills:
            letra = None
            score_sep = 0.0
        else:
            max_fill = float(np.max(fills))
            if max_fill < 1e-6:
                # Todas as bolhas ~0
                letra = None
                score_sep = 0.0
                print(f"Q{num_questao}: Todas bolhas ~0 — nenhuma resposta detectada")
            else:
                # Normalizar pelo máximo (intensidade relativa)
                fills_norm = np.array(fills) / max_fill
                idx_max = int(np.argmax(fills_norm))
                letra = alternativas[idx_max] if idx_max < len(alternativas) else None

                # Score de separação
                sorted_norm = np.sort(fills_norm)[::-1]
                second_norm = sorted_norm[1] if len(sorted_norm) > 1 else 0.0
                score_sep = float(1.0 - second_norm)

        resultados[num_questao] = letra
        confianca[num_questao] = score_sep

        # === SINALIZAÇÃO DE BAIXA CONFIANÇA (score < 0.15) ===
        if score_sep < 0.15:
            # Identificar candidatos que estão dentro de 20% do máximo
            fills_com_letra = [
                (alternativas[j], bolha.get('fill_rate', 0.0))
                for j, bolha in enumerate(questao)
                if j < len(alternativas) and not bolha.get('sintetica', False)
            ]
            max_fill_q = max((f for _, f in fills_com_letra), default=0.0)
            candidatos = [
                lt for lt, f in fills_com_letra
                if max_fill_q > 0 and f >= max_fill_q * 0.80
            ]

            questoes_baixa_confianca.append({
                "questao": num_questao,
                "score": round(score_sep, 4),
                "candidatos": candidatos
            })
            fills_log = ", ".join(f"{lt}={f:.2f}" for lt, f in fills_com_letra)
            print(f"Q{num_questao}: ⚠️ Baixa confiança sep={score_sep:.3f} "
                  f"→ {candidatos} [{fills_log}]")
        else:
            fills_log = ", ".join(
                f"{alternativas[j]}={b.get('fill_rate', 0):.2f}"
                for j, b in enumerate(questao) if j < len(alternativas)
            )
            print(f"Q{num_questao}: {letra} (sep={score_sep:.3f}) [{fills_log}]")

        # === FALLBACK AVANÇADO: desempate morfológico para ambiguidade extrema ===
        # Acionado apenas quando score < 0.10 E binary disponível
        fills_reais_vals = [b.get('fill_rate', 0.0) for b in bolhas_reais]
        max_fill = max(fills_reais_vals) if fills_reais_vals else 0.0

        if binary is not None and score_sep < 0.10:
            # Analisar as top-2 bolhas por fill_rate com análise avançada
            bolhas_com_idx = sorted(
                [(j, b) for j, b in enumerate(questao)
                 if j < len(alternativas) and not b.get('sintetica', False)],
                key=lambda x: x[1].get('fill_rate', 0.0),
                reverse=True
            )
            scores_adv = []
            for j, bolha in bolhas_com_idx[:2]:
                res_adv = analisar_preenchimento_avancado(binary, image, bolha)
                scores_adv.append((j, res_adv['score'], res_adv['confianca']))

            if scores_adv:
                scores_adv.sort(key=lambda x: x[1], reverse=True)
                melhor_j, melhor_score_adv, melhor_conf = scores_adv[0]
                if melhor_score_adv > 0.45:
                    letra_adv = alternativas[melhor_j] if melhor_j < len(alternativas) else letra
                    if letra_adv != letra:
                        print(f"Q{num_questao}: Análise avançada corrige "
                              f"{letra}→{letra_adv} (score_adv={melhor_score_adv:.2f})")
                        resultados[num_questao] = letra_adv
                    # Elevar confiança usando score avançado ponderado
                    confianca[num_questao] = max(score_sep, melhor_conf * 0.5)

    return resultados, confianca, questoes_baixa_confianca


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


def validar_resultado_razoavel(resultados, confianca, num_questoes, num_alternativas=5):
    """
    **PILAR 4: Validação de Razoabilidade Estatística**

    Verifica se o resultado faz sentido do ponto de vista estatístico.
    Se alguma validação falhar, o resultado é marcado como "suspeito"
    e pode ser rejeitado em favor de uma estratégia alternativa.

    Args:
        resultados: dict {num_questao: letra ou None}
        confianca: dict {num_questao: confidence_score}
        num_questoes: número esperado de questões
        num_alternativas: 5 (A-E)

    Returns:
        (valido: bool, motivo: str)
        Exemplo: (True, "OK") ou (False, "Alternativa C muito frequente")
    """
    from collections import Counter

    # CHECK 1: Nenhuma alternativa aparece muito mais que o esperado
    respostas_lidas = [r for r in resultados.values() if r is not None and not str(r).endswith('?')]
    alternativas_esperadas_por_alt = len(respostas_lidas) / num_alternativas if len(respostas_lidas) > 0 else 0

    if len(respostas_lidas) > 0:
        contagem = Counter(respostas_lidas)
        for alt, count in contagem.items():
            # Marcar como suspeito se alternativa aparece > 2.5x do esperado
            if count > alternativas_esperadas_por_alt * 2.5 and count > 2:
                return False, f"Alternativa {alt} aparece {count}x (esperado ~{alternativas_esperadas_por_alt:.1f})"

    # CHECK 2: Confiança média não está muito baixa
    valores_confianca = [v for v in confianca.values() if v is not None and v > 0]
    if len(valores_confianca) > 0:
        conf_media = float(np.mean(valores_confianca))
        if conf_media < 0.30:  # Confidence < 0.30 é MUITO baixa
            return False, f"Confiança média muito baixa: {conf_media:.2f}"

    # CHECK 3: Mínimo de questões lidas
    # Espera-se ler pelo menos 70% das questões
    num_questoes_lidas = sum(1 for r in resultados.values() if r is not None)
    if num_questoes_lidas < num_questoes * 0.70:
        return False, f"Apenas {num_questoes_lidas}/{num_questoes} questões lidas ({num_questoes_lidas/num_questoes*100:.0f}%)"

    # Se passou em todas as checagens, resultado é razoável
    return True, "OK"


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
        # Populado após cada chamada de analisar_gabarito; acessível pelo api_backend
        self.ultima_baixa_confianca = []
        # Armazenar bolhas realmente selecionadas durante análise
        self.bolhas_selecionadas_por_questao = {}

    def analisar_cartao_melhorado(self, image, binary, debug_image, num_questoes, num_colunas, sensitivity, quality_meta=None):
        # Limpar bolhas selecionadas
        self.bolhas_selecionadas_por_questao = {}

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

            bolhas, debug_area = detectar_bolhas_avancado(
                roi_cartao, roi_debug, sensitivity=sensitivity, quality_meta=quality_meta
            )
            debug_image[y:y+h, x:x+w] = debug_area

            for bolha in bolhas:
                bolha['centro'] = (bolha['centro'][0] + x, bolha['centro'][1] + y)
                bolha['x'] += x
                bolha['y'] += y

            if bolhas:
                # **PILAR 5: Usar processamento em cascata**
                questoes = agrupar_bolhas_por_questoes(bolhas, num_questoes, 5)
                resultados, confianca_res, estrategia_usada, valido = processar_cartao_com_cascata(
                    bolhas, num_questoes, 5,
                    binary=roi_cartao, image=image[y:y+h, x:x+w], debug=False
                )
                self.ultima_baixa_confianca = []

                # Armazenar bolhas realmente selecionadas
                for i, questao in enumerate(questoes):
                    if i >= num_questoes:
                        break
                    num_questao = i + 1
                    resposta = resultados.get(num_questao)

                    if resposta is not None and resposta[0] in self.alternativas:
                        try:
                            alt_index = self.alternativas.index(resposta[0])
                            if alt_index < len(questao) and not questao[alt_index].get('sintetica', False):
                                bolha_selecionada = questao[alt_index].copy()
                                self.bolhas_selecionadas_por_questao[num_questao] = bolha_selecionada
                        except (ValueError, IndexError):
                            pass
            else:
                for i in range(1, num_questoes + 1):
                    resultados[i] = None
        else:
            return self.analisar_cartao_fallback(
                image, binary, debug_image, num_questoes, num_colunas, sensitivity, quality_meta=quality_meta
            )

        for i in range(1, num_questoes + 1):
            if i not in resultados:
                resultados[i] = None
        return resultados

    def analisar_cartao_fallback(self, image, binary, debug_image, num_questoes, num_colunas, sensitivity, quality_meta=None):
        # Limpar bolhas selecionadas
        self.bolhas_selecionadas_por_questao = {}

        resultados = {i: None for i in range(1, num_questoes + 1)}

        if binary.max() <= 1.0:
            binary_proc = (binary * 255).astype(np.uint8)
        else:
            binary_proc = binary.copy()

        bolhas, debug_img = detectar_bolhas_avancado(
            binary_proc, debug_image, sensitivity=sensitivity, quality_meta=quality_meta
        )

        debug_image[:] = debug_img[:]

        if bolhas:
            # **PILAR 5: Usar processamento em cascata**
            # Tenta múltiplas estratégias até uma passar na validação
            questoes = agrupar_bolhas_por_questoes(bolhas, num_questoes, len(self.alternativas))
            resultados_analise, confianca_res, estrategia_usada, valido = processar_cartao_com_cascata(
                bolhas, num_questoes, len(self.alternativas),
                binary=binary_proc, image=image, debug=False
            )
            print(f"  → {estrategia_usada}")

            # Simular baixa_confianca (para compatibilidade)
            self.ultima_baixa_confianca = []

            # Armazenar bolhas realmente selecionadas
            for i, questao in enumerate(questoes):
                if i >= num_questoes:
                    break
                num_questao = i + 1
                resposta = resultados_analise.get(num_questao)

                if resposta is not None and resposta[0] in self.alternativas:
                    try:
                        alt_index = self.alternativas.index(resposta[0])
                        if alt_index < len(questao) and not questao[alt_index].get('sintetica', False):
                            bolha_selecionada = questao[alt_index].copy()
                            self.bolhas_selecionadas_por_questao[num_questao] = bolha_selecionada
                    except (ValueError, IndexError):
                        pass

            resultados = validar_resultados(resultados_analise, confianca_res, num_questoes)
        return resultados


def processar_cartao_com_cascata(bolhas, num_questoes, num_alternativas=5,
                                  binary=None, image=None, debug=False):
    """
    **PILAR 5: Processamento em Cascata com Múltiplas Estratégias**

    Tenta várias estratégias de agrupamento de bolhas em sequência.
    Cada estratégia é validada estatisticamente antes de passar para a próxima.

    Estratégias (em ordem):
    1. Agrupamento padrão (DBSCAN iterativo já aplicado em agrupar_bolhas_por_questoes)
    2. Re-análise com threshold reduzido (mais permissivo)
    3. Re-análise com threshold aumentado (mais restritivo)
    4. Retornar com confiança baixa

    Args:
        bolhas: Lista de bolhas detectadas
        num_questoes: Número de questões esperado
        num_alternativas: Número de alternativas (5 para A-E)
        binary: Imagem binária (para análise avançada)
        image: Imagem original (para análise avançada)
        debug: Se True, printa detalhes de cada tentativa

    Returns:
        (resultados, confianca, estrategia_usada, valido)
        - resultados: dict {num_questao: letra ou None}
        - confianca: dict {num_questao: confidence_score}
        - estrategia_usada: string descrevendo qual estratégia funcionou
        - valido: boolean se resultado passou na validação
    """
    from sklearn.cluster import KMeans

    if not bolhas:
        return {i: None for i in range(1, num_questoes + 1)}, {i: 0.0 for i in range(1, num_questoes + 1)}, "Nenhuma bolha detectada", False

    alternativas = ['A', 'B', 'C', 'D', 'E'][:num_alternativas]

    # === ESTRATÉGIA 1: Agrupamento padrão (DBSCAN iterativo já foi aplicado) ===
    if debug:
        print("\n  [Cascata] Estratégia 1: Agrupamento padrão (DBSCAN iterativo)")

    # Agrupar com a função padrão (que já usa DBSCAN iterativo)
    questoes_1 = agrupar_bolhas_por_questoes(bolhas, num_questoes, num_alternativas)
    resultados_1, confianca_1, _ = analisar_gabarito(questoes_1, num_questoes, alternativas, binary, image)
    valido_1, motivo_1 = validar_resultado_razoavel(resultados_1, confianca_1, num_questoes, num_alternativas)

    if valido_1:
        if debug:
            print(f"  ✅ Estratégia 1 passou: {motivo_1}")
        return resultados_1, confianca_1, "Estratégia 1: DBSCAN iterativo", True

    if debug:
        print(f"  ❌ Estratégia 1 falhou: {motivo_1}")

    # === ESTRATÉGIA 2: Forçar KMeans com número exato de questões ===
    if debug:
        print("  [Cascata] Estratégia 2: KMeans forçado com tolerância ±2")

    try:
        centros = np.array([[b['x'], b['y']] for b in bolhas])
        y_only = centros[:, 1].reshape(-1, 1)

        # Tentar KMeans com ±2 clusters
        for k_try in [num_questoes, num_questoes - 1, num_questoes + 1, num_questoes - 2, num_questoes + 2]:
            if k_try < 1:
                continue

            kmeans = KMeans(n_clusters=k_try, random_state=42, n_init=10)
            labels = kmeans.fit_predict(y_only)

            from collections import defaultdict
            clusters = defaultdict(list)
            for i, bolha in enumerate(bolhas):
                if labels[i] != -1:
                    clusters[labels[i]].append(bolha)

            sorted_clusters = sorted(
                clusters.values(),
                key=lambda c: np.mean([b['y'] for b in c])
            )

            questoes_2 = sorted_clusters[:num_questoes]
            resultados_2, confianca_2, _ = analisar_gabarito(questoes_2, num_questoes, alternativas, binary, image)
            valido_2, motivo_2 = validar_resultado_razoavel(resultados_2, confianca_2, num_questoes, num_alternativas)

            if valido_2:
                if debug:
                    print(f"  ✅ Estratégia 2 passou com k={k_try}: {motivo_2}")
                return resultados_2, confianca_2, f"Estratégia 2: KMeans(k={k_try})", True

        if debug:
            print(f"  ❌ Estratégia 2 falhou para todos k")
    except Exception as e:
        if debug:
            print(f"  ❌ Estratégia 2 exception: {e}")

    # === ESTRATÉGIA 3: Re-análise com threshold de confiança reduzido ===
    if debug:
        print("  [Cascata] Estratégia 3: Re-análise com confiança reduzida")

    # Usar resultado da estratégia 1, mas marcar como baixa confiança
    # (permitir respostas com confidence > 0.15 em vez de > 0.20)
    resultados_3 = resultados_1.copy()
    confianca_3 = {q: max(0.15, c) for q, c in confianca_1.items()}  # Boost minimum confidence

    # Aplicar validação menos estrita
    num_lidas_3 = sum(1 for r in resultados_3.values() if r is not None)
    if num_lidas_3 >= num_questoes * 0.60:  # Menos restritivo: 60% vs 70%
        if debug:
            print(f"  ✅ Estratégia 3 passou: {num_lidas_3}/{num_questoes} questões lidas (60% mínimo)")
        return resultados_3, confianca_3, "Estratégia 3: Re-análise com confiança reduzida", True

    if debug:
        print(f"  ❌ Estratégia 3 falhou: Apenas {num_lidas_3}/{num_questoes} questões")

    # === ESTRATÉGIA 4: Retornar com marcação de baixa confiança ===
    if debug:
        print("  [Cascata] Estratégia 4: Retornar com marcação de baixa confiança (fallback final)")

    # Marcar todas as respostas com baixa confiança
    resultados_4 = {q: f"{r}?" if r else None for q, r in resultados_1.items()}
    confianca_4 = {q: 0.1 for q in resultados_1.keys()}  # Confiança mínima

    if debug:
        print(f"  ⚠️ Estratégia 4 (fallback final): Retornando com confiança baixa")

    return resultados_4, confianca_4, "Estratégia 4: Fallback com confiança baixa", False


class MultiColumnCartaoAnalyzer:
    def __init__(self, analyzer):
        self.analyzer = analyzer
        self.alternativas = ['A', 'B', 'C', 'D', 'E']
        # Armazenar bolhas realmente selecionadas durante análise
        self.bolhas_selecionadas_por_questao = {}

    def ajustar_bolhas_para_global(self, offset_x, offset_y):
        """
        Ajusta todas as bolhas armazenadas em self.bolhas_selecionadas_por_questao
        para coordenadas globais, adicionando o offset.
        """
        for num_questao in self.bolhas_selecionadas_por_questao:
            bolha = self.bolhas_selecionadas_por_questao[num_questao]
            cx, cy = bolha['centro']
            bolha['centro'] = (cx + offset_x, cy + offset_y)
            if 'x' in bolha:
                bolha['x'] += offset_x
            if 'y' in bolha:
                bolha['y'] += offset_y

    def criar_visualizacao_simplificada(self, clean_image, resultados, binary, num_colunas):
        """
        Desenha as bolhas realmente selecionadas usando EXATAMENTE as coordenadas
        (x, y) e raio que foram processadas durante a cascata de análise.

        NÃO faz nenhuma detecção independente de bolhas — apenas desenha aquelas
        que foram realmente selecionadas e armazenadas em self.bolhas_selecionadas_por_questao.
        """
        h, w = clean_image.shape[:2]

        # Desenhar APENAS as bolhas realmente selecionadas
        for num_questao in sorted(self.bolhas_selecionadas_por_questao.keys()):
            bolha = self.bolhas_selecionadas_por_questao[num_questao]

            # Usar as coordenadas reais da bolha selecionada
            cx, cy = bolha['centro']
            raio = bolha['radius']

            # Limites de segurança
            if not (0 <= cx < w and 0 <= cy < h):
                continue

            # Desenhar bolha verde (preenchida)
            cv2.circle(clean_image, (cx, cy), raio, (0, 255, 0), -1)

    def analisar_cartao_multicolunas(self, image, binary, debug_image, num_questoes, num_colunas, sensitivity, threshold=150, return_debug_image=False, quality_meta=None):
        """
        v2: Usa detecção de retângulos impressos como âncora para as colunas.
        Fallback para segmentação por projeção se retângulos não forem encontrados.
        """
        from image_processing import detectar_retangulos_colunas

        # Limpar bolhas selecionadas da análise anterior
        self.bolhas_selecionadas_por_questao = {}

        h, w = binary.shape
        resultados = {}

        clean_image = image.copy()
        clean_debug = cv2.cvtColor(clean_image, cv2.COLOR_BGR2RGB)

        if num_colunas <= 1:
            resultados = self.analyzer.analisar_cartao_melhorado(
                image, binary, debug_image, num_questoes, num_colunas, sensitivity, quality_meta=quality_meta
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
                    questoes_nesta_coluna, 1, sensitivity, quality_meta=quality_meta
                )

                # Ajustar coordenadas das bolhas selecionadas para global
                self.ajustar_bolhas_para_global(rx, ry)

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
                    questoes_nesta_coluna, 1, sensitivity, quality_meta=quality_meta
                )

                # Ajustar coordenadas das bolhas selecionadas para global
                # (x_inicio é o offset horizontal, y é sempre 0 nesse caso)
                self.ajustar_bolhas_para_global(x_inicio, 0)

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
