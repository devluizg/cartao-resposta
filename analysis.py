# analysis.py
import numpy as np
from collections import defaultdict
from sklearn.cluster import DBSCAN
import cv2
from image_processing import detectar_bolhas_avancado, agrupar_bolhas_por_questoes

def analisar_gabarito(questoes, num_questoes, alternativas=['A', 'B', 'C', 'D', 'E']):
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
        max_preenchimento = 0.0
        alt_index = -1
        second_max = 0.0
        for j, bolha in enumerate(questao):
            if j >= len(alternativas):
                break
            preenchimento = bolha.get('fill_rate', bolha.get('preenchimento', 0.0))
            if preenchimento > max_preenchimento:
                second_max = max_preenchimento
                max_preenchimento = preenchimento
                alt_index = j
            elif preenchimento > second_max:
                second_max = preenchimento
        diferenca = max_preenchimento - second_max
        nivel_confianca = diferenca * 2
        nivel_confianca = min(max(nivel_confianca, 0.0), 1.0)
        if alt_index >= 0 and max_preenchimento > 0.3:
            resultados[num_questao] = alternativas[alt_index]
            confianca[num_questao] = nivel_confianca
    return resultados, confianca

def validar_resultados(resultados, confianca, num_questoes, num_alternativas=5):
    resultados_corrigidos = resultados.copy()
    for q in range(1, num_questoes + 1):
        if q in confianca and confianca[q] < 0.2:
            resultados_corrigidos[q] = f"{resultados[q]}?" if resultados[q] else None
    contagem = {'A': 0, 'B': 0, 'C': 0, 'D': 0, 'E': 0, None: 0}
    for alt in resultados.values():
        if alt in contagem:
            contagem[alt] += 1
    total_marcadas = sum(1 for alt in resultados.values() if alt is not None)
    return resultados_corrigidos

def detectar_colunas(binary_image):
    """Detecta automaticamente o número de colunas no cartão resposta"""
    # Projeção vertical da imagem binária
    projection = np.sum(binary_image, axis=0)
    
    # Normalizar e suavizar a projeção
    projection = projection / np.max(projection) if np.max(projection) > 0 else projection
    window_size = max(len(projection) // 100, 10)
    projection_smooth = np.convolve(projection, np.ones(window_size)/window_size, mode='same')
    
    # Encontrar vales na projeção (possíveis separadores de colunas)
    valleys = []
    for i in range(1, len(projection_smooth)-1):
        if projection_smooth[i] < projection_smooth[i-1] and projection_smooth[i] < projection_smooth[i+1]:
            valleys.append((i, projection_smooth[i]))
    
    # Filtrar vales significativos
    valleys = sorted(valleys, key=lambda x: x[1])
    significant_valleys = [v for v in valleys if v[1] < 0.3]  # Threshold ajustável
    
    # Determinar número de colunas
    if len(significant_valleys) >= 2:
        return 3
    elif len(significant_valleys) == 1:
        return 2
    else:
        return 1

def segmentar_colunas_com_bordas(binary, num_colunas):
    """
    Segmenta a imagem em colunas usando uma combinação de projeção vertical e detecção de bordas/retângulos.
    Esta abordagem é mais robusta para diferentes ângulos de captura e variações na perspectiva.
    
    Args:
        binary: Imagem binária (thresholded)
        num_colunas: Número esperado de colunas
        
    Returns:
        regioes: Lista de tuples (x_inicio, x_fim) para cada coluna
    """
    import numpy as np
    import cv2
    
    h, w = binary.shape
    
    # MÉTODO 1: Projeção vertical (similar ao método original)
    projection = np.sum(binary, axis=0)
    
    # Suavizar a projeção
    window_size = max(w // 100, 5)
    smooth_proj = np.convolve(projection, np.ones(window_size)/window_size, mode='same')
    
    # Normalizar
    max_val = np.max(smooth_proj)
    smooth_proj = smooth_proj / max_val if max_val > 0 else smooth_proj
    
    # Encontrar vales na projeção (possíveis divisões entre colunas)
    threshold = 0.2
    valleys = []
    
    for i in range(window_size, len(smooth_proj)-window_size):
        if smooth_proj[i] < threshold:
            # Verificar se é um vale local
            window = 20
            left_max = max(smooth_proj[max(0, i-window):i]) if i > 0 else 0
            right_max = max(smooth_proj[i+1:min(len(smooth_proj), i+window+1)]) if i < len(smooth_proj)-1 else 0
            
            if smooth_proj[i] <= left_max * 0.7 and smooth_proj[i] <= right_max * 0.7:
                valleys.append(i)
    
    # MÉTODO 2: Detecção de retângulos/contornos
    # Preparar imagem para detecção de contornos
    # Usar morfologia para conectar elementos e destacar estruturas retangulares
    kernel = np.ones((5, 5), np.uint8)
    morph = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)
    
    # Encontrar contornos externos principais
    contours, _ = cv2.findContours(morph, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    
    # Filtrar contornos por área para eliminar ruído
    min_area = (h * w) / (num_colunas * 10)  # Área mínima proporcional
    valid_contours = [cnt for cnt in contours if cv2.contourArea(cnt) > min_area]
    
    # Extrair os retângulos que possivelmente representam colunas
    rectangles = []
    for cnt in valid_contours:
        # Aproximar o contorno para um polígono
        epsilon = 0.02 * cv2.arcLength(cnt, True)
        approx = cv2.approxPolyDP(cnt, epsilon, True)
        
        # Verificar se é um retângulo (4 vértices) ou algo próximo
        if len(approx) >= 4 and len(approx) <= 8:  # Ser flexível com o número de vértices
            x, y, w_rect, h_rect = cv2.boundingRect(cnt)
            # Verificar proporção altura/largura para garantir que é uma coluna
            if h_rect > h/2:  # Altura mínima para ser considerado coluna
                rectangles.append((x, x + w_rect))
    
    # Ordenar retângulos da esquerda para a direita
    rectangles.sort(key=lambda r: r[0])
    
    # MÉTODO 3: Combinar os dois métodos para resultado mais robusto
    
    # Se encontramos retângulos suficientes, usá-los como base
    if len(rectangles) >= num_colunas:
        # Agrupar retângulos próximos (podem pertencer à mesma coluna)
        merged_rectangles = []
        current_group = rectangles[0]
        
        for i in range(1, len(rectangles)):
            # Se o retângulo atual está próximo do grupo atual, fundi-los
            if rectangles[i][0] - current_group[1] < w * 0.05:  # Threshold de proximidade
                current_group = (current_group[0], max(current_group[1], rectangles[i][1]))
            else:
                merged_rectangles.append(current_group)
                current_group = rectangles[i]
        
        merged_rectangles.append(current_group)
        
        # Se temos retângulos demais, selecionar os mais significativos
        if len(merged_rectangles) > num_colunas:
            # Ordenar por largura (assumindo que colunas principais são mais largas)
            merged_rectangles.sort(key=lambda r: r[1] - r[0], reverse=True)
            merged_rectangles = merged_rectangles[:num_colunas]
            # Reordenar da esquerda para a direita
            merged_rectangles.sort(key=lambda r: r[0])
        
        # Se temos retângulos de menos, complementar com divisão baseada em vales
        if len(merged_rectangles) < num_colunas:
            # Usar vales detectados para complementar
            if valleys:
                # Ordenar vales
                valleys.sort()
                
                # Adicionar vales que não conflitem com retângulos já detectados
                for valley in valleys:
                    # Verificar se o vale não está dentro de nenhum retângulo existente
                    is_valid = True
                    for rect in merged_rectangles:
                        if rect[0] <= valley <= rect[1]:
                            is_valid = False
                            break
                    
                    if is_valid:
                        # Encontrar posição correta para inserir
                        pos = 0
                        while pos < len(merged_rectangles) and merged_rectangles[pos][0] < valley:
                            pos += 1
                        
                        # Dividir o espaço usando este vale
                        if pos > 0 and pos < len(merged_rectangles):
                            # Vale entre dois retângulos - ajustar os limites
                            left_rect = merged_rectangles[pos-1]
                            right_rect = merged_rectangles[pos]
                            
                            # Criar dois novos retângulos a partir do vale
                            merged_rectangles[pos-1] = (left_rect[0], valley)
                            merged_rectangles.insert(pos, (valley, right_rect[1]))
                        
                        # Se ainda não temos retângulos suficientes, parar quando atingir o número desejado
                        if len(merged_rectangles) >= num_colunas:
                            break
        
        # Se ainda não temos retângulos suficientes, complementar com divisão uniforme
        rectangles = merged_rectangles
    
    # Se ainda não conseguimos número suficiente de divisões, recorrer à divisão baseada em vales
    if len(rectangles) < num_colunas:
        # Usar vales se tivermos o suficiente
        if len(valleys) >= num_colunas - 1:
            # Selecionar os vales mais significativos
            valleys.sort()  # Ordenar por posição
            
            # Verificar distribuição de vales e selecionar os melhores
            if len(valleys) > num_colunas - 1:
                # Calcular a distância ideal entre vales
                ideal_spacing = w / num_colunas
                
                # Selecionar vales para obter espaçamento mais uniforme
                selected_valleys = []
                start = 0
                
                for i in range(num_colunas - 1):
                    # Encontrar o vale mais próximo da posição ideal
                    target_pos = (i + 1) * w / num_colunas
                    best_valley = min(valleys, key=lambda v: abs(v - target_pos))
                    
                    selected_valleys.append(best_valley)
                    # Remover o vale selecionado e proximidades para evitar duplicação
                    valleys = [v for v in valleys if abs(v - best_valley) > w * 0.05]
                    
                    if not valleys:  # Se acabarem os vales
                        break
                
                valleys = sorted(selected_valleys)
            
            # Criar regiões a partir dos vales selecionados
            regioes = []
            inicio = 0
            
            for v in valleys[:num_colunas-1]:
                regioes.append((inicio, v))
                inicio = v
            
            regioes.append((inicio, w))
            return regioes
    
    # Combinação final: usar retângulos detectados + divisão uniforme se necessário
    if len(rectangles) == num_colunas:
        return rectangles
    
    # Se chegamos aqui, recorrer à divisão uniforme com ajustes
    # Ajustar com qualquer informação disponível (retângulos parciais e vales)
    divisoes = []
    
    if rectangles:
        # Usar as divisões de retângulos que temos
        for i, (start, end) in enumerate(rectangles):
            if i == 0 and start > 0:
                divisoes.append((0, start))
            divisoes.append((start, end))
            if i < len(rectangles) - 1 and end < rectangles[i+1][0]:
                divisoes.append((end, rectangles[i+1][0]))
        if rectangles[-1][1] < w:
            divisoes.append((rectangles[-1][1], w))
    
    # Se ainda não temos divisões suficientes, dividir espaços uniformemente
    if not divisoes or len(divisoes) != num_colunas:
        return [(i * w // num_colunas, (i+1) * w // num_colunas) for i in range(num_colunas)]
    
    # Se temos divisões demais, combinar as menores
    while len(divisoes) > num_colunas:
        # Encontrar o par de divisões adjacentes com menor largura combinada
        min_width = float('inf')
        min_index = 0
        
        for i in range(len(divisoes) - 1):
            width = divisoes[i+1][1] - divisoes[i][0]
            if width < min_width:
                min_width = width
                min_index = i
        
        # Combinar as duas divisões
        divisoes[min_index] = (divisoes[min_index][0], divisoes[min_index+1][1])
        divisoes.pop(min_index + 1)
    
    return divisoes

class CartaoRespostaAnalyzer:
    def __init__(self):
        self.alternativas = ['A', 'B', 'C', 'D', 'E']

    def analisar_cartao_melhorado(self, image, binary, debug_image, num_questoes, num_colunas, sensitivity):
        resultados = {}
        h, w = binary.shape
        
        # CORREÇÃO: Garantir que binary seja binário correto para o cv2.findContours
        if binary.max() <= 1.0:
            binary_contours = (binary * 255).astype(np.uint8)
        else:
            binary_contours = binary.copy()
            
        contornos, _ = cv2.findContours(binary_contours, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        potenciais_retangulos = []
        
        for contorno in contornos:
            area = cv2.contourArea(contorno)
            perimetro = cv2.arcLength(contorno, True)
            if area < 1000:
                continue
            approx = cv2.approxPolyDP(contorno, 0.02 * perimetro, True)
            if len(approx) == 4:
                potenciais_retangulos.append(approx)
                
        if potenciais_retangulos:
            potenciais_retangulos.sort(key=cv2.contourArea, reverse=True)
            retangulo_cartao = potenciais_retangulos[0]
            x, y, w, h = cv2.boundingRect(retangulo_cartao)
            
            # CORREÇÃO: Garantir que as coordenadas estão dentro dos limites
            x = max(0, x)
            y = max(0, y)
            w = min(w, binary.shape[1] - x)
            h = min(h, binary.shape[0] - y)
            
            cv2.rectangle(debug_image, (x, y), (x+w, y+h), (0, 255, 0), 2)
            
            # CORREÇÃO: Verificar se a ROI tem tamanho válido
            if w > 0 and h > 0:
                roi_cartao = binary[y:y+h, x:x+w]
                roi_debug = debug_image[y:y+h, x:x+w]
                
                # CORREÇÃO: Garantir que binary para detectar_bolhas_avancado esteja na faixa correta
                if roi_cartao.max() <= 1.0:
                    roi_cartao = (roi_cartao * 255).astype(np.uint8)
                
                bolhas, debug_area = detectar_bolhas_avancado(roi_cartao, roi_debug, sensitivity=sensitivity)
                
                # CORREÇÃO: Atualizar a região de debug com as marcações
                debug_image[y:y+h, x:x+w] = debug_area
                
                for bolha in bolhas:
                    bolha['centro'] = (bolha['centro'][0] + x, bolha['centro'][1] + y)
                    bolha['x'] += x
                    bolha['y'] += y
                
                if bolhas:
                    questoes = agrupar_bolhas_por_questoes(bolhas, num_questoes, 5)
                    for i, questao in enumerate(questoes):
                        num_questao = i + 1
                        print(f"Questão {num_questao}: {len(questao)} alternativas processadas")
                        alternativa_marcada = None
                        maior_preenchimento = 0.0
                        for j, bolha in enumerate(questao):
                            if j >= 5:
                                break
                            cv2.circle(debug_image, bolha['centro'], bolha['radius'], (255, 0, 0), 3)
                            alt_letra = self.alternativas[j]
                            cv2.putText(debug_image, alt_letra, (bolha['centro'][0] - 5, bolha['centro'][1] + 5), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 0, 0), 2)
                            percentual = int(bolha['fill_rate'] * 100)
                            texto_info = f"{percentual}%"
                            cv2.putText(debug_image, texto_info, (bolha['centro'][0] - 15, bolha['centro'][1] + bolha['radius'] + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 1)
                            if bolha['fill_rate'] > maior_preenchimento:
                                maior_preenchimento = bolha['fill_rate']
                                if bolha['fill_rate'] > sensitivity:
                                    alternativa_marcada = self.alternativas[j]
                        resultados[num_questao] = alternativa_marcada
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
        
        # CORREÇÃO: Garantir que binary esteja na faixa correta para detectar_bolhas_avancado
        if binary.max() <= 1.0:
            binary_proc = (binary * 255).astype(np.uint8)
        else:
            binary_proc = binary.copy()
            
        bolhas, debug_img = detectar_bolhas_avancado(binary_proc, debug_image, sensitivity=sensitivity)
        
        # CORREÇÃO: Atualizar debug_image com as marcações
        debug_image[:] = debug_img[:]
        
        if bolhas:
            questoes = agrupar_bolhas_por_questoes(bolhas, num_questoes, len(self.alternativas))
            resultados_analise, confianca = analisar_gabarito(questoes, num_questoes, self.alternativas)
            resultados = validar_resultados(resultados_analise, confianca, num_questoes)
        return resultados

class MultiColumnCartaoAnalyzer:
    def __init__(self, analyzer):
        """
        Inicializa o analisador de múltiplas colunas
        
        Args:
            analyzer: Instância de CartaoRespostaAnalyzer para delegar a análise
        """
        self.analyzer = analyzer
        self.alternativas = ['A', 'B', 'C', 'D', 'E']
    
    def analisar_cartao_multicolunas(self, image, binary, debug_image, num_questoes, num_colunas, sensitivity, threshold=150, return_debug_image=False):
        """
        Analisa um cartão resposta com múltiplas colunas

        Args:
            image: Imagem original do cartão
            binary: Imagem binária processada
            debug_image: Imagem para debug
            num_questoes: Número total de questões
            num_colunas: Número de colunas no cartão
            sensitivity: Sensibilidade para detecção de marcações (0-1)
            threshold: Valor de limiar para binarização da imagem (padrão: 150)
            return_debug_image: Se True, retorna também a imagem de debug (padrão: False)

        Returns:
            resultados: Dicionário com resultados para todas as questões
            debug_image: A imagem com as marcações de debug (apenas se return_debug_image=True)
        """
        h, w = binary.shape
        resultados = {}

        if num_colunas <= 1:
            resultados = self.analyzer.analisar_cartao_melhorado(image, binary, debug_image,
                                                            num_questoes, num_colunas, sensitivity)
            if return_debug_image:
                return resultados, debug_image
            return resultados

        # Obter regiões das colunas
        regioes_colunas = segmentar_colunas_com_bordas(binary, num_colunas)

        # 🟩 VISUALIZAÇÃO: desenhar linhas verticais dos cortes das colunas
        for idx, (x_inicio, x_fim) in enumerate(regioes_colunas):
            cv2.line(debug_image, (x_inicio, 0), (x_inicio, h), (0, 255, 0), 2)
            cv2.putText(debug_image, f"Coluna {idx+1}", (x_inicio + 10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
        # Linha final (último x_fim)
        cv2.line(debug_image, (regioes_colunas[-1][1], 0), (regioes_colunas[-1][1], h), (0, 255, 0), 2)

        # Distribuir questões entre colunas
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

            # CORREÇÃO: Criar uma região segura para a coluna
            # Garantir que as coordenadas estejam dentro dos limites da imagem
            x_inicio = max(0, min(x_inicio, w-1))
            x_fim = max(0, min(x_fim, w))
            
            # CORREÇÃO: Somente processar se a coluna tiver largura válida
            if x_fim <= x_inicio:
                continue
                
            coluna_bin = binary[:, x_inicio:x_fim]
            coluna_img = image[:, x_inicio:x_fim].copy()
            coluna_debug = debug_image[:, x_inicio:x_fim]  # CORREÇÃO: Criar cópia da região de debug
            
            questoes_nesta_coluna = questoes_por_coluna[idx]

            if questoes_nesta_coluna <= 0:
                continue

            # CORREÇÃO: Usar debug_image específico para esta coluna
            resultados_coluna = self.analyzer.analisar_cartao_melhorado(
                coluna_img,
                coluna_bin,
                coluna_debug,  # CORREÇÃO: Usar a região correta para debug
                questoes_nesta_coluna, 1, sensitivity
            )

            # CORREÇÃO: Atualizar region do debug_image original com as alterações
            debug_image[:, x_inicio:x_fim] = coluna_debug
            
            # Mapear resultados para questão global
            for q, resposta in resultados_coluna.items():
                if q <= questoes_nesta_coluna:
                    resultados[questao_atual + q - 1] = resposta

            questao_atual += questoes_nesta_coluna

        # Preenche questões faltantes com None
        for q in range(1, num_questoes + 1):
            if q not in resultados:
                resultados[q] = None

        if return_debug_image:
            return resultados, debug_image

        return resultados