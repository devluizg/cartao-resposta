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

def segmentar_colunas(binary, num_colunas):
    """
    Segmenta a imagem em colunas de forma inteligente, procurando por regiões vazias
    
    Args:
        binary: Imagem binária
        num_colunas: Número esperado de colunas
        
    Returns:
        regioes: Lista de tuples (x_inicio, x_fim) para cada coluna
    """
    h, w = binary.shape
    
    # Projeção vertical
    projection = np.sum(binary, axis=0)
    
    # Suavizar a projeção
    window_size = max(w // 100, 5)
    smooth_proj = np.convolve(projection, np.ones(window_size)/window_size, mode='same')
    
    # Normalizar
    max_val = np.max(smooth_proj)
    smooth_proj = smooth_proj / max_val if max_val > 0 else smooth_proj
    
    # Encontrar possíveis divisões entre colunas (vales na projeção)
    threshold = 0.15  # Reduzido para capturar divisões mais sutis
    valleys = []
    
    for i in range(window_size, len(smooth_proj)-window_size):
        if smooth_proj[i] < threshold:
            # Verificar se é um vale local em uma janela maior
            window = 20  # Janela maior para encontrar vales mais significativos
            left_max = max(smooth_proj[max(0, i-window):i]) if i > 0 else 0
            right_max = max(smooth_proj[i+1:min(len(smooth_proj), i+window+1)]) if i < len(smooth_proj)-1 else 0
            
            if smooth_proj[i] <= left_max * 0.7 and smooth_proj[i] <= right_max * 0.7:
                valleys.append(i)
    
    # Se não encontrou vales suficientes, procurar vales menos profundos
    if len(valleys) < num_colunas - 1:
        valley_depths = []
        for i in range(window_size, len(smooth_proj)-window_size):
            left_max = max(smooth_proj[max(0, i-window_size):i]) if i > 0 else 0
            right_max = max(smooth_proj[i+1:min(len(smooth_proj), i+window_size+1)]) if i < len(smooth_proj)-1 else 0
            depth = min(left_max, right_max) - smooth_proj[i]
            if depth > 0:
                valley_depths.append((i, depth))
        
        # Ordenar por profundidade
        valley_depths.sort(key=lambda x: x[1], reverse=True)
        additional_valleys = [v[0] for v in valley_depths[:num_colunas-1-len(valleys)]]
        valleys.extend(additional_valleys)
    
    # Se ainda não encontrou vales suficientes, fazer divisão uniforme
    if len(valleys) < num_colunas - 1:
        return [(i * w // num_colunas, (i+1) * w // num_colunas) for i in range(num_colunas)]
    
    # Selecionar os vales mais espaçados (para evitar detecções muito próximas)
    valleys.sort()  # Ordenar por posição
    
    # Remover vales muito próximos (manter o mais profundo)
    min_distance = w // (num_colunas * 2)  # Distância mínima entre vales
    i = 0
    while i < len(valleys) - 1:
        if valleys[i+1] - valleys[i] < min_distance:
            # Remover o vale menos profundo
            if smooth_proj[valleys[i]] > smooth_proj[valleys[i+1]]:
                valleys.pop(i)
            else:
                valleys.pop(i+1)
        else:
            i += 1
    
    # Selecionar os vales mais significativos
    if len(valleys) > num_colunas - 1:
        # Calcular a distância ideal entre vales
        ideal_spacing = w / num_colunas
        
        # Função para avaliar uma configuração de vales
        def evaluate_valleys(selected):
            if not selected:
                return float('inf')
            
            selected = sorted(selected)
            # Avaliar o espaçamento entre colunas
            widths = [selected[0]] + [selected[i] - selected[i-1] for i in range(1, len(selected))] + [w - selected[-1]]
            std_dev = np.std(widths)
            return std_dev
        
        # Usar combinações de vales para encontrar a melhor configuração
        import itertools
        best_valleys = valleys[:num_colunas-1]  # Padrão
        best_score = evaluate_valleys(best_valleys)
        
        # Tentar encontrar uma configuração melhor
        if len(valleys) <= 10:  # Limitar para evitar explosão combinatória
            for combo in itertools.combinations(valleys, num_colunas-1):
                score = evaluate_valleys(combo)
                if score < best_score:
                    best_score = score
                    best_valleys = combo
        
        valleys = sorted(best_valleys)
    
    # Criar regiões a partir dos vales selecionados
    regioes = []
    inicio = 0
    
    for v in valleys[:num_colunas-1]:  # Garantir que usamos o número correto de vales
        regioes.append((inicio, v))
        inicio = v
    
    regioes.append((inicio, w))
    
    return regioes

class CartaoRespostaAnalyzer:
    def __init__(self):
        self.alternativas = ['A', 'B', 'C', 'D', 'E']

    def analisar_cartao_melhorado(self, image, binary, debug_image, num_questoes, num_colunas, sensitivity):
        resultados = {}
        h, w = binary.shape
        contornos, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
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
            cv2.rectangle(debug_image, (x, y), (x+w, y+h), (0, 255, 0), 2)
            roi_cartao = binary[y:y+h, x:x+w]
            roi_debug = debug_image[y:y+h, x:x+w]
            bolhas, debug_area = detectar_bolhas_avancado(roi_cartao, roi_debug, sensitivity=sensitivity)
            for bolha in bolhas:
                bolha['centro'] = (bolha['centro'][0] + x, bolha['centro'][1] + y)
                bolha['x'] += x
                bolha['y'] += y
            debug_image[y:y+h, x:x+w] = debug_area
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
        bolhas, debug_img = detectar_bolhas_avancado(binary, debug_image, sensitivity=sensitivity)
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
    
    def analisar_cartao_multicolunas(self, image, binary, debug_image, num_questoes, num_colunas, sensitivity, threshold=150):
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
            
        Returns:
            resultados: Dicionário com resultados para todas as questões
        """
        h, w = binary.shape
        resultados = {}
        
        # Se for apenas uma coluna, use o método original
        if num_colunas <= 1:
            return self.analyzer.analisar_cartao_melhorado(image, binary, debug_image, 
                                                        num_questoes, num_colunas, sensitivity)
        
        # Obter uma segmentação inteligente das colunas
        regioes_colunas = segmentar_colunas(binary, num_colunas)
        
        # Para múltiplas colunas, dividimos as questões entre as colunas
        # Novo: Calcular questões por coluna de forma mais precisa
        # A primeira coluna pode ter uma quantidade diferente das demais
        questoes_coluna_1 = num_questoes // 2 if num_colunas == 2 else num_questoes // 3
        if num_colunas == 2:
            # Para 2 colunas, dividir igualmente (arredondando para cima na primeira coluna se necessário)
            questoes_por_coluna = [
                (num_questoes + 1) // 2,  # Primeira coluna
                num_questoes // 2         # Segunda coluna
            ]
        elif num_colunas == 3:
            # Para 3 colunas, tentar distribuir igualmente
            base_per_column = num_questoes // 3
            remainder = num_questoes % 3
            questoes_por_coluna = [
                base_per_column + (1 if remainder > 0 else 0),
                base_per_column + (1 if remainder > 1 else 0),
                base_per_column
            ]
        else:
            # Fallback para qualquer outro número de colunas
            base_per_column = num_questoes // num_colunas
            remainder = num_questoes % num_colunas
            questoes_por_coluna = [base_per_column + (1 if i < remainder else 0) for i in range(num_colunas)]
        
        # Debug: imprimir divisão de questões
        print(f"Divisão de questões por coluna: {questoes_por_coluna}")
        
        # Contador para acompanhar a questão atual no cartão
        questao_atual = 1
        
        for idx, (x_inicio, x_fim) in enumerate(regioes_colunas):
            if idx >= len(questoes_por_coluna):
                break
                
            # Recortar a região da coluna
            coluna_width = x_fim - x_inicio
            # Para colunas muito estreitas, expandir um pouco a região
            if coluna_width < w / (num_colunas * 1.5):
                margin = int(w * 0.05)
                x_inicio = max(0, x_inicio - margin)
                x_fim = min(w, x_fim + margin)
                
            coluna_bin = binary[:, x_inicio:x_fim]
            coluna_debug = debug_image[:, x_inicio:x_fim].copy()
            coluna_img = image[:, x_inicio:x_fim].copy()
            
            # Pegar o número de questões para esta coluna específica
            questoes_nesta_coluna = questoes_por_coluna[idx]
            
            if questoes_nesta_coluna <= 0:
                continue
                
            # Desenhar separador de coluna no debug_image
            cv2.line(debug_image, (x_inicio, 0), (x_inicio, h), (0, 255, 0), 2)
            cv2.putText(debug_image, f"Coluna {idx+1}: Q{questao_atual}-Q{questao_atual+questoes_nesta_coluna-1}", 
                        (x_inicio + 10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
            
            # Analisar a coluna atual
            resultados_coluna = self.analyzer.analisar_cartao_melhorado(
                coluna_img, coluna_bin, coluna_debug,
                questoes_nesta_coluna, 1, sensitivity
            )
            
            # Ajustar numeração das questões e adicionar ao resultado final
            for q, resposta in resultados_coluna.items():
                if q <= questoes_nesta_coluna:  # Verificar se a questão está dentro do range esperado
                    num_questao_global = questao_atual + q - 1
                    resultados[num_questao_global] = resposta
            
            # Transferir marcações de debug para a imagem completa
            debug_image[:, x_inicio:x_fim] = coluna_debug
            
            # Atualizar contador de questões
            questao_atual += questoes_nesta_coluna
        
        # Garantir que todas as questões esperadas tenham um resultado
        for q in range(1, num_questoes + 1):
            if q not in resultados:
                resultados[q] = None
                
        return resultados