#utils.py

import numpy as np
from warnings import filters
import cv2

def calibrar_sensibilidade_dinamica(bolhas):
    """
    Calibra dinamicamente o parâmetro de sensibilidade baseado nos dados.
    
    Args:
        bolhas: Lista de dicionários com informações das bolhas
    
    Returns:
        sensitivity: Valor de sensibilidade calibrado
    """
    if not bolhas:
        return 0.3  # Valor padrão se não houver dados
    
    # Extrair valores de preenchimento
    preenchimentos = [b['fill_rate'] for b in bolhas]
    
    # Ordenar valores
    preenchimentos.sort()
    
    # Análise de distribuição
    if len(preenchimentos) < 10:
        return 0.3  # Valor padrão para poucos dados
    
    # Usar análise de Otsu para encontrar threshold ótimo (bimodal)
    try:
        hist, bin_edges = np.histogram(preenchimentos, bins=20, range=(0, 1))
        threshold = filters.threshold_otsu(hist)
        return threshold
    except:
        # Fallback: Usar método baseado em percentil
        q25 = np.percentile(preenchimentos, 25)
        q75 = np.percentile(preenchimentos, 75)
        iqr = q75 - q25
        
        # Estimar threshold entre os dois modos
        threshold = q25 + (iqr * 0.8)
        
        # Limitar entre 0.15 e 0.5
        return min(max(threshold, 0.15), 0.5)

def gerar_imagem_debug_avancada(original_image, binary, questoes, resultados, confianca=None):
    """
    Gera uma imagem de debug avançada para visualização dos resultados
    
    Args:
        original_image: Imagem original
        binary: Imagem binária processada
        questoes: Lista de questões com bolhas
        resultados: Dicionário com resultados por questão
        confianca: Dicionário com níveis de confiança por questão
        
    Returns:
        debug_image: Imagem com visualizações de debug
    """
    # Criar cópia colorida da imagem original
    debug_image = original_image.copy()
    
    # Criar uma visualização lado a lado
    h, w = original_image.shape[:2]
    binary_color = cv2.cvtColor(binary, cv2.COLOR_GRAY2BGR)
    side_by_side = np.zeros((h, w*2, 3), dtype=np.uint8)
    side_by_side[:, :w] = debug_image
    side_by_side[:, w:] = binary_color
    
    # Desenhar retângulos ao redor de cada questão
    for i, questao in enumerate(questoes):
        num_questao = i + 1
        resposta = resultados.get(num_questao)
        
        if not questao:
            continue
        
        # Calcular bounding box da questão
        min_x = min(bolha['centro'][0] - bolha['raio'] for bolha in questao)
        max_x = max(bolha['centro'][0] + bolha['raio'] for bolha in questao)
        min_y = min(bolha['centro'][1] - bolha['raio'] for bolha in questao)
        max_y = max(bolha['centro'][1] + bolha['raio'] for bolha in questao)
        
        # Definir cor baseada na confiança
        cor = (0, 255, 0)  # Verde por padrão
        if confianca and num_questao in confianca:
            conf = confianca[num_questao]
            if conf < 0.5:
                r_ratio = 1.0
                g_ratio = conf * 2
                cor = (0, int(255 * g_ratio), 255)
            else:
                r_ratio = 2 * (1 - conf)
                g_ratio = 1.0
                cor = (0, 255, int(255 * r_ratio))
        
        # Desenhar retângulo na imagem original
        cv2.rectangle(side_by_side, (min_x, min_y), (max_x, max_y), cor, 2)
        cv2.rectangle(side_by_side, (min_x + w, min_y), (max_x + w, max_y), cor, 2)
        
        # Adicionar texto com número da questão e resposta
        label = f"Q{num_questao}: {resposta if resposta else '-'}"
        cv2.putText(side_by_side, label, (min_x, min_y - 5), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, cor, 2)
        cv2.putText(side_by_side, label, (min_x + w, min_y - 5), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, cor, 2)
        
        # Destacar a alternativa selecionada
        if resposta:
            alternativas = ['A', 'B', 'C', 'D', 'E']
            if resposta in alternativas:
                idx = alternativas.index(resposta)
                if idx < len(questao):
                    bolha = questao[idx]
                    cv2.circle(side_by_side, bolha['centro'], bolha['raio'], (0, 0, 255), 3)
                    cv2.circle(side_by_side, (bolha['centro'][0] + w, bolha['centro'][1]), 
                              bolha['raio'], (0, 0, 255), 3)
    
    return side_by_side