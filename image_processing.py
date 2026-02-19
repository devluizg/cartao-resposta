#image_processing.py
import cv2
import numpy as np
from collections import defaultdict
from sklearn.cluster import DBSCAN
import functools
import threading

# Cache thread-safe para templates
_template_cache = {}
_template_cache_lock = threading.Lock()

# Constantes de otimização
MAX_IMAGE_WIDTH = 1500
MAX_IMAGE_HEIGHT = 2000

def redimensionar_imagem_otimizada(image, max_width=MAX_IMAGE_WIDTH):
    """
    Redimensiona a imagem para um tamanho padrão otimizado para processamento.
    Mantém a proporção aspect ratio.
    """
    h, w = image.shape[:2]

    if w <= max_width:
        return image, 1.0  # Sem redimensionamento

    # Calcular fator de escala
    scale = max_width / w
    new_h = int(h * scale)

    # Redimensionar
    resized = cv2.resize(image, (max_width, new_h), interpolation=cv2.INTER_AREA)
    return resized, scale

def _criar_template_bolha_cached(raio_px):
    """Cria ou recupera template bolha do cache (thread-safe)."""
    cache_key = f"template_{raio_px}"

    with _template_cache_lock:
        if cache_key in _template_cache:
            return _template_cache[cache_key]

        # Criar novo template
        if raio_px < 3:
            raio_px = 3

        size = raio_px * 2 + 1
        template = np.zeros((size, size), dtype=np.uint8)
        cv2.circle(template, (raio_px, raio_px), raio_px, 255, -1)

        # Armazenar em cache
        _template_cache[cache_key] = template

        return template

def limpar_cache_templates():
    """Limpa o cache de templates para liberar memória."""
    global _template_cache
    with _template_cache_lock:
        _template_cache.clear()

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

def melhorar_pre_processamento_adaptativo(image):
    """
    Pré-processamento adaptativo avançado da imagem com múltiplas técnicas
    para melhorar detecção de bolhas em diferentes condições de iluminação.

    Args:
        image: Imagem original em BGR

    Returns:
        binary: Imagem binária otimizada para detecção de bolhas
        metadata: Dicionário com informações sobre o pré-processamento
    """
    # 1. Converter para LAB e normalizar L channel
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)

    # Normalizar L channel (0-255)
    l_norm = cv2.normalize(l, None, 0, 255, cv2.NORM_MINMAX)

    # 2. Detectar perfil de iluminação
    hist = cv2.calcHist([l_norm], [0], None, [256], [0, 256])
    brightness = np.mean(l_norm)
    contrast = np.std(l_norm)

    # Perfil de iluminação para log
    metadata = {
        'brightness': float(brightness),
        'contrast': float(contrast),
        'illumination_profile': None
    }

    # 3. Aplicar CLAHE adaptativo baseado no perfil de iluminação
    if brightness < 100:  # Luz baixa
        clahe = cv2.createCLAHE(clipLimit=5.0, tileGridSize=(8, 8))
        metadata['illumination_profile'] = 'low_light'
    elif brightness > 180:  # Luz alta
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(16, 16))
        metadata['illumination_profile'] = 'high_light'
    else:  # Normal
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(12, 12))
        metadata['illumination_profile'] = 'normal'

    l_clahe = clahe.apply(l_norm)

    # 4. Shadow removal com top-hat morphological
    kernel_tophat = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    tophat = cv2.morphologyEx(l_clahe, cv2.MORPH_TOPHAT, kernel_tophat)
    l_corrected = cv2.add(l_clahe, tophat)

    # 5. Bilateral filter (preserva bordas enquanto suaviza)
    filtered = cv2.bilateralFilter(l_corrected.astype(np.uint8), 9, 75, 75)

    # 6. Multi-threshold combinado
    # Threshold adaptativo
    binary_adaptive = cv2.adaptiveThreshold(
        filtered, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV, 21, 10
    )

    # Threshold Otsu
    _, binary_otsu = cv2.threshold(filtered, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    # Threshold Triangle (alternativa)
    _, binary_triangle = cv2.threshold(filtered, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_TRIANGLE)

    # Combinar com pesos
    binary = cv2.addWeighted(binary_adaptive, 0.5, binary_otsu, 0.3, 0)
    binary = cv2.bitwise_or(binary, (binary_triangle.astype(np.uint8) * 0.2).astype(np.uint8))

    # 7. Limpeza morfológica otimizada
    kernel_open = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    kernel_close = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))

    # Opening: remove pequenos ruídos
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel_open)

    # Closing: fecha pequenas quebras
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel_close)

    return binary, metadata

def _detectar_retangulo_por_contorno(binary):
    """Tenta detectar o retângulo do cartão usando contornos."""
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    if not contours:
        return None

    contours = sorted(contours, key=cv2.contourArea, reverse=True)
    largest_contour = contours[0]

    perimeter = cv2.arcLength(largest_contour, True)
    approx = cv2.approxPolyDP(largest_contour, 0.02 * perimeter, True)

    if len(approx) == 4:
        return approx.reshape(4, 2)

    # Fallback para convex hull
    hull = cv2.convexHull(largest_contour)
    approx = cv2.approxPolyDP(hull, 0.02 * cv2.arcLength(hull, True), True)

    if len(approx) == 4:
        return approx.reshape(4, 2)

    return None

def _detectar_retangulo_por_ransac(binary):
    """Tenta detectar o retângulo usando Hough Lines e RANSAC."""
    # Detectar linhas retas na imagem
    lines = cv2.HoughLinesP(binary, 1, np.pi/180, 50, minLineLength=50, maxLineGap=10)

    if lines is None or len(lines) < 4:
        return None

    # Extrair pontos das linhas
    points = []
    for line in lines:
        x1, y1, x2, y2 = line[0]
        points.append([x1, y1])
        points.append([x2, y2])

    if len(points) < 4:
        return None

    points = np.array(points, dtype=np.float32)

    # Encontrar convex hull dos pontos
    hull = cv2.convexHull(points)

    if len(hull) >= 4:
        # Aproximar para um retângulo (4 vértices)
        perimeter = cv2.arcLength(hull, True)
        approx = cv2.approxPolyDP(hull, 0.02 * perimeter, True)

        if len(approx) == 4:
            return approx.reshape(4, 2)

    return None

def _validar_proporcoes_a4(rect, tolerance=0.2):
    """Valida se o retângulo tem proporções A4 (1.414)."""
    if rect is None or len(rect) < 4:
        return False

    # Calcular dimensões
    width_A = np.sqrt(((rect[2][0] - rect[3][0]) ** 2) + ((rect[2][1] - rect[3][1]) ** 2))
    height_A = np.sqrt(((rect[1][0] - rect[2][0]) ** 2) + ((rect[1][1] - rect[2][1]) ** 2))

    if max(width_A, height_A) == 0:
        return False

    ratio = max(width_A, height_A) / min(width_A, height_A)

    # A4 ratio é 1.414 (±tolerance)
    return (1.414 * (1 - tolerance) < ratio < 1.414 * (1 + tolerance))

def corrigir_perspectiva(image, binary):
    """
    Detecta e corrige a perspectiva do cartão de respostas com fallback robusto.

    Args:
        image: Imagem original em BGR
        binary: Imagem binária pré-processada

    Returns:
        corrected_image: Imagem corrigida em perspectiva
        corrected_binary: Binária corrigida em perspectiva
        success: Boolean indicando sucesso na correção
    """
    h, w = binary.shape

    # Método 1: Detectar por contornos
    rect = _detectar_retangulo_por_contorno(binary)

    # Método 2: Fallback para Hough Lines + RANSAC
    if rect is None:
        rect = _detectar_retangulo_por_ransac(binary)

    # Método 3: Fallback para bounding box
    if rect is None:
        contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            return image, binary, False

        largest = max(contours, key=cv2.contourArea)
        x, y, w_rect, h_rect = cv2.boundingRect(largest)
        rect = np.array([[x, y], [x + w_rect, y], [x + w_rect, y + h_rect], [x, y + h_rect]], dtype=np.float32)

    if rect is None:
        return image, binary, False

    # Ordenar pontos do retângulo
    rect = rect.reshape(4, 2).astype(np.float32)
    sum_coords = rect.sum(axis=1)
    diff_coords = np.diff(rect, axis=1)

    ordered_rect = np.zeros((4, 2), dtype=np.float32)
    ordered_rect[0] = rect[np.argmin(sum_coords)]      # Top-left
    ordered_rect[2] = rect[np.argmax(sum_coords)]      # Bottom-right
    ordered_rect[1] = rect[np.argmin(diff_coords)]     # Top-right
    ordered_rect[3] = rect[np.argmax(diff_coords)]     # Bottom-left

    # Validar proporções A4
    if not _validar_proporcoes_a4(ordered_rect):
        # Se não é A4, usar método direto sem validação
        pass

    # Calcular dimensões de saída
    width_A = np.sqrt(((ordered_rect[2][0] - ordered_rect[3][0]) ** 2) + ((ordered_rect[2][1] - ordered_rect[3][1]) ** 2))
    width_B = np.sqrt(((ordered_rect[1][0] - ordered_rect[0][0]) ** 2) + ((ordered_rect[1][1] - ordered_rect[0][1]) ** 2))
    max_width = max(int(width_A), int(width_B))

    height_A = np.sqrt(((ordered_rect[1][0] - ordered_rect[2][0]) ** 2) + ((ordered_rect[1][1] - ordered_rect[2][1]) ** 2))
    height_B = np.sqrt(((ordered_rect[0][0] - ordered_rect[3][0]) ** 2) + ((ordered_rect[0][1] - ordered_rect[3][1]) ** 2))
    max_height = max(int(height_A), int(height_B))

    # Validar área mínima (30% da imagem)
    area = max_width * max_height
    min_area = (h * w) * 0.3

    if area < min_area:
        return image, binary, False

    # Limitar tamanho máximo razoável
    if max_width > w * 2 or max_height > h * 2:
        return image, binary, False

    dst = np.array([
        [0, 0],
        [max_width - 1, 0],
        [max_width - 1, max_height - 1],
        [0, max_height - 1]
    ], dtype=np.float32)

    try:
        transform_matrix = cv2.getPerspectiveTransform(ordered_rect, dst)
        corrected_image = cv2.warpPerspective(image, transform_matrix, (max_width, max_height))
        corrected_binary = cv2.warpPerspective(binary, transform_matrix, (max_width, max_height))

        return corrected_image, corrected_binary, True
    except Exception as e:
        print(f"Erro na transformação de perspectiva: {e}")
        return image, binary, False

def _estimar_escala_imagem(binary):
    """
    Estima a escala da imagem (pixels por mm) baseado na análise
    da estrutura do cartão resposta.
    """
    h, w = binary.shape
    # Assumindo cartão A4: ~210mm x 297mm
    # Estimativa conservadora: pixels_por_mm = min(w, h) / 100
    pixels_por_mm = min(w, h) / 100.0
    return max(pixels_por_mm, 1.0)

def _criar_template_bolha(raio_px):
    """Cria um template circular para template matching (usa cache)."""
    return _criar_template_bolha_cached(raio_px)

def _detectar_hough_adaptativo(binary, min_radius, max_radius):
    """Detecta círculos usando HoughCircles com parâmetros adaptativos (mais sensível)."""
    img_for_circles = 255 - binary.copy()
    img_for_circles = cv2.GaussianBlur(img_for_circles, (5, 5), 0)

    circles = cv2.HoughCircles(
        img_for_circles,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=max(min_radius * 0.8, 10),  # Reduzido para melhor detecção
        param1=40,  # Reduzido de 50 para mais sensibilidade
        param2=20,  # Reduzido de 25 para mais sensibilidade
        minRadius=int(min_radius * 0.8),  # Reduzido para aceitar círculos menores
        maxRadius=int(max_radius * 1.2)   # Aumentado para aceitar círculos maiores
    )

    if circles is not None:
        return np.uint16(np.around(circles[0]))
    return np.array([])

def _detectar_template_matching(binary, raio_px):
    """Detecta círculos usando template matching com NMS (dilation + contornos)."""
    template = _criar_template_bolha(raio_px)

    if template.shape[0] > binary.shape[0] or template.shape[1] > binary.shape[1]:
        return np.array([])

    # Usar correlação normalizada com threshold fixo (evita threshold relativo instável)
    result = cv2.matchTemplate(binary, template, cv2.TM_CCOEFF_NORMED)
    threshold_template = 0.50

    # Criar máscara de regiões acima do threshold
    mask = (result >= threshold_template).astype(np.uint8)

    if not mask.any():
        return np.array([])

    # NMS via dilatação + contornos: agrupa pixels próximos em um único candidato
    kernel_size = max(3, raio_px * 2 - 1)
    if kernel_size % 2 == 0:
        kernel_size += 1
    kernel = np.ones((kernel_size, kernel_size), np.uint8)
    dilated = cv2.dilate(mask, kernel)

    contornos, _ = cv2.findContours(dilated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    circles = []
    for cnt in contornos:
        M = cv2.moments(cnt)
        if M["m00"] == 0:
            continue
        cx = int(M["m10"] / M["m00"])
        cy = int(M["m01"] / M["m00"])
        circles.append([cx + raio_px, cy + raio_px, raio_px])

    return np.array(circles)

def _detectar_mser(binary, min_radius, max_radius):
    """Detecta regiões extremais estáveis (MSER) e filtra por circularidade."""
    try:
        mser = cv2.MSER_create()
        regions, _ = mser.detectRegions(binary)

        circles = []
        for region in regions:
            if len(region) < 5:
                continue

            # Converter região para contour (formato esperado)
            contour = np.array(region, dtype=np.int32).reshape(-1, 1, 2)

            # Calcular propriedades geométricas
            area = cv2.contourArea(contour)
            if area < np.pi * (min_radius ** 2) or area > np.pi * (max_radius ** 2):
                continue

            # Círculo equivalente
            radius_equiv = np.sqrt(area / np.pi)

            # Calcular centroide
            M = cv2.moments(contour)
            if M["m00"] != 0:
                cx = int(M["m10"] / M["m00"])
                cy = int(M["m01"] / M["m00"])
                circles.append([cx, cy, int(radius_equiv)])

        return np.array(circles)
    except:
        # Fallback se MSER falhar
        return np.array([])

def _detectar_contornos_com_features(binary, min_radius, max_radius):
    """Detecta círculos por contornos com filtro de Hu Moments."""
    contours, _ = cv2.findContours(binary, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)

    circles = []
    for cnt in contours:
        area = cv2.contourArea(cnt)

        # Filtrar por área
        min_area = np.pi * (min_radius ** 2)
        max_area = np.pi * (max_radius ** 2)
        if area < min_area or area > max_area:
            continue

        perimeter = cv2.arcLength(cnt, True)
        if perimeter == 0:
            continue

        # Calcular circularidade
        circularity = 4 * np.pi * area / (perimeter * perimeter)
        if circularity < 0.6:  # Menos rigoroso que antes
            continue

        # Calcular centroide
        M = cv2.moments(cnt)
        if M["m00"] != 0:
            cx = int(M["m10"] / M["m00"])
            cy = int(M["m01"] / M["m00"])

            # Estimar raio
            radius = int(np.sqrt(area / np.pi))
            if min_radius <= radius <= max_radius:
                circles.append([cx, cy, radius])

    return np.array(circles)

def _aplicar_voting_system(circle_lists, threshold_distancia):
    """
    Aplica voting system: círculos precisam estar em acordo
    com pelo menos 1 dos 4 métodos de detecção (mais sensível).
    """
    if all(len(circles) == 0 for circles in circle_lists):
        return np.array([])

    # Combinar todos os círculos
    todos_circulos = []
    for circles in circle_lists:
        todos_circulos.extend(circles)

    if len(todos_circulos) == 0:
        return np.array([])

    # Clustering de círculos próximos
    bolhas_finais = []
    usados = set()

    for i, circulo in enumerate(todos_circulos):
        if i in usados:
            continue

        # Encontrar todos os círculos próximos
        grupo = [circulo]
        for j, outro in enumerate(todos_circulos):
            if i != j and j not in usados:
                dist = np.sqrt((int(circulo[0]) - int(outro[0]))**2 + (int(circulo[1]) - int(outro[1]))**2)
                if dist < threshold_distancia:
                    grupo.append(outro)
                    usados.add(j)

        # Verificar se o grupo tem concordância (1+ métodos é suficiente agora)
        if len(grupo) >= 1:  # Reduzido de 2 para 1 (mais sensível)
            # Média do grupo
            cx_medio = int(np.mean([c[0] for c in grupo]))
            cy_medio = int(np.mean([c[1] for c in grupo]))
            r_medio = int(np.mean([c[2] for c in grupo]))
            bolhas_finais.append([cx_medio, cy_medio, r_medio])

        usados.add(i)

    return np.array(bolhas_finais)

def detectar_bolhas_avancado(binary, debug_image=None, threshold=100, sensitivity=0.5):
    """
    Detecta bolhas em um cartão resposta com método híbrido (4 detctores + voting system).

    Args:
        binary: Imagem binária pré-processada
        debug_image: Imagem para desenhar informações de debug (opcional)
        threshold: Valor de limiar para detecção de marcação (0-255)
        sensitivity: Sensibilidade para considerar uma bolha preenchida (0.0-1.0)

    Returns:
        bolhas: Lista de dicionários com informações de cada bolha detectada
        debug_img: Imagem com visualização do processamento
    """
    if debug_image is None:
        debug_img = cv2.cvtColor(binary, cv2.COLOR_GRAY2BGR)
    else:
        debug_img = debug_image.copy()

    h, w = binary.shape

    # Calcular escala da imagem
    escala = _estimar_escala_imagem(binary)

    # Adaptar parâmetros de raio baseado na escala
    raio_esperado_mm = 3  # 3mm de diâmetro típico
    raio_px = int(raio_esperado_mm * escala)
    min_radius = max(int(raio_px * 0.7), 5)
    max_radius = int(raio_px * 1.3)

    # Método 1: HoughCircles Adaptativo
    circles_hough = _detectar_hough_adaptativo(binary, min_radius, max_radius)

    # Método 2: Template Matching
    circles_template = _detectar_template_matching(binary, raio_px)

    # Método 3: MSER + Circularidade
    circles_mser = _detectar_mser(binary, min_radius, max_radius)

    # Método 4: Contornos com features
    circles_contour = _detectar_contornos_com_features(binary, min_radius, max_radius)

    # Voting System: agrupa círculos próximos de diferentes métodos
    # Threshold aumentado de 0.3 para 0.8 para melhor fusão entre métodos
    circle_lists = [circles_hough, circles_template, circles_mser, circles_contour]
    bolhas_votadas = _aplicar_voting_system(circle_lists, raio_px * 0.8)

    # Converter para formato de bolhas
    bolhas = []
    for circulo in bolhas_votadas:
        x, y, r = int(circulo[0]), int(circulo[1]), int(circulo[2])

        # Validar limites
        if x - r < 0 or y - r < 0 or x + r >= w or y + r >= h:
            continue

        # Analisar preenchimento
        mask = np.zeros_like(binary)
        cv2.circle(mask, (x, y), r, 255, -1)

        inner_mask = np.zeros_like(binary)
        inner_r = int(r * 0.8)
        cv2.circle(inner_mask, (x, y), inner_r, 255, -1)

        roi = cv2.bitwise_and(binary, inner_mask)
        inner_area = np.pi * inner_r * inner_r
        filled_pixels = cv2.countNonZero(roi)
        fill_rate = filled_pixels / inner_area if inner_area > 0 else 0

        is_filled = fill_rate > sensitivity

        bolhas.append({
            'x': x,
            'y': y,
            'centro': (x, y),
            'radius': r,
            'fill_rate': fill_rate,
            'filled': is_filled
        })

        # Desenhar para debug
        color = (0, 0, 255) if is_filled else (0, 255, 0)
        cv2.circle(debug_img, (x, y), r, color, 2)
        cv2.putText(debug_img, f"{int(fill_rate * 100)}%", (x - 20, y - 15),
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

    # ── ESTRATÉGIA PRINCIPAL: DBSCAN sobre coordenadas Y ─────────────────────
    # eps = 1.5× raio médio: bolhas da mesma linha ficam juntas,
    # bolhas de linhas adjacentes ficam em clusters separados.
    # Isso elimina o problema de KMeans juntar 2 linhas físicas num mesmo cluster
    # (sintoma: fill_rate ~0.97 em múltiplas bolhas da mesma "questão").
    from sklearn.cluster import KMeans

    y_coords = np.array([c[1] for c in centros])
    y_only = y_coords.reshape(-1, 1)

    raio_medio_bolhas = float(np.median([b.get('radius', 10) for b in bolhas]))
    eps_linha = max(raio_medio_bolhas * 1.5, 8.0)

    db_linhas = DBSCAN(eps=eps_linha, min_samples=1).fit(y_only)
    linhas_labels = db_linhas.labels_
    linhas_naturais = len(set(linhas_labels[linhas_labels != -1]))

    # Se DBSCAN encontrou um número coerente com o esperado → usar direto.
    # Tolerância superior de 1.5× cobre detecções com pequeno ruído extra.
    if num_questoes <= linhas_naturais <= int(num_questoes * 1.5):
        labels = linhas_labels
        print(f"DBSCAN: {linhas_naturais} linhas físicas detectadas (esperado {num_questoes}). Usando DBSCAN.")
    else:
        # Fallback: KMeans com número efetivo
        effective_clusters = linhas_naturais if (0 < linhas_naturais < num_questoes) else num_questoes
        if 0 < linhas_naturais < num_questoes:
            print(f"Aviso: DBSCAN detectou apenas {linhas_naturais} linhas (esperado {num_questoes}). "
                  f"Usando KMeans({effective_clusters}).")
        try:
            kmeans = KMeans(n_clusters=effective_clusters, random_state=42, n_init=10)
            labels = kmeans.fit_predict(y_only)
        except Exception:
            labels = linhas_labels  # último recurso
    
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
            # Estratégia: selecionar os N clusters cujos centros Y formam a
            # progressão aritmética mais uniforme (menor variância dos gaps).
            # Questões reais de cartão-resposta sempre têm espaçamento regular.
            y_means = np.array([
                np.mean([b['centro'][1] if 'centro' in b else b['y'] for b in c])
                for c in sorted_clusters
            ])
            n = len(sorted_clusters)
            k = num_questoes

            # Pré-filtrar clusters com menos de 2 bolhas (provável artefato)
            min_bolhas = 2
            candidatos = [(i, c) for i, c in enumerate(sorted_clusters)
                         if len(c) >= min_bolhas]

            if len(candidatos) < k:
                # Se candidatos insuficientes, usar todos
                candidatos = list(enumerate(sorted_clusters))

            if len(candidatos) == k:
                sorted_clusters = [c for _, c in candidatos]
            else:
                # Busca greedy: percorre todos os subconjuntos de tamanho k
                # escolhendo o de menor variância nos gaps (O(n*k) aprox.)
                idxs_cands = [i for i, _ in candidatos]
                y_cands = y_means[idxs_cands]

                melhor_var = float('inf')
                melhor_escolha = idxs_cands[:k]

                # Janela deslizante não serve aqui pois candidatos podem
                # não ser contíguos. Usamos combinações parciais com poda.
                from itertools import combinations
                # Limitar busca se muitos candidatos (para performance)
                if len(candidatos) <= 20:
                    for combo in combinations(range(len(candidatos)), k):
                        ys_sel = y_cands[list(combo)]
                        gaps = np.diff(np.sort(ys_sel))
                        if len(gaps) > 0:
                            var = float(np.std(gaps))
                            if var < melhor_var:
                                melhor_var = var
                                melhor_escolha = [idxs_cands[j] for j in combo]
                else:
                    # Fallback: remover os clusters com menos bolhas e mais isolados
                    clusters_info = []
                    for i, c in enumerate(sorted_clusters):
                        nb = len(c)
                        clusters_info.append((nb, i, c))
                    # Manter os k com mais bolhas
                    clusters_info.sort(reverse=True)
                    melhor_escolha = sorted([info[1] for info in clusters_info[:k]])

                sorted_clusters = [sorted_clusters[i] for i in melhor_escolha]

            # Reordenar verticalmente após seleção
            sorted_clusters = sorted(
                sorted_clusters,
                key=lambda cluster: np.mean([b['centro'][1] if 'centro' in b else b['y'] for b in cluster])
            )
    
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
            # Bug 3 fix: filtrar bolhas que estejam muito longe do centro-Y do cluster
            # (evita que KMeans misture bolhas de linhas físicas adjacentes)
            y_vals = [b.get('y', b['centro'][1]) for b in bolhas_ordenadas]
            y_range = max(y_vals) - min(y_vals)
            raio_cluster = float(np.median([b.get('radius', 10) for b in bolhas_ordenadas]))
            if y_range > raio_cluster * 2:
                y_med = float(np.median(y_vals))
                bolhas_ordenadas = [b for b in bolhas_ordenadas
                                    if abs(b.get('y', b['centro'][1]) - y_med) <= raio_cluster * 1.5]
                bolhas_ordenadas = sorted(bolhas_ordenadas,
                                         key=lambda b: b['centro'][0] if 'centro' in b else b['x'])

            # Se após o filtro ainda há mais bolhas que alternativas, usar bucket assignment
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
                    # Bug 4 fix: usar floor com clamp explícito para evitar off-by-one na borda
                    raw_idx = (x - x_min) / largura_grupo if largura_grupo > 0 else 0
                    idx = min(int(raw_idx), num_alternativas - 1)
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

def validar_geometria_questao(bolhas, num_alternativas=5):
    """
    Valida a geometria de um grupo de bolhas (questão).
    Verifica alinhamento horizontal, espaçamento uniforme e outliers.

    Args:
        bolhas: Lista de bolhas de uma questão
        num_alternativas: Número esperado de alternativas

    Returns:
        is_valid: Boolean indicando se a questão é válida
        quality_score: Score de qualidade da detecção (0-1)
        message: Mensagem descritiva
    """
    from scipy import stats

    if len(bolhas) != num_alternativas:
        return False, 0.0, f"Número de bolhas incorreto: {len(bolhas)} (esperado {num_alternativas})"

    # Extrair coordenadas
    y_coords = np.array([b['y'] for b in bolhas])
    x_coords = np.array([b['x'] for b in bolhas])
    raios = np.array([b['radius'] for b in bolhas])

    y_mean = np.mean(y_coords)
    y_std = np.std(y_coords)
    raio_medio = np.mean(raios)

    # 1. Validar alinhamento horizontal (5% do raio)
    if y_std > raio_medio * 0.05:
        return False, 0.3, f"Desalinhamento vertical: {y_std:.1f}px (esperado < {raio_medio * 0.05:.1f}px)"

    # 2. Validar espaçamento uniforme
    x_sorted = np.sort(x_coords)
    espacos = np.diff(x_sorted)

    if len(espacos) > 0:
        media_espacos = np.mean(espacos)
        if media_espacos > 0:
            cv_espacos = np.std(espacos) / media_espacos  # Coeficiente de variação
        else:
            cv_espacos = float('inf')

        if cv_espacos > 0.15:  # 15%
            return False, 0.4, f"Espaçamento irregular: CV={cv_espacos:.2f} (esperado < 0.15)"
    else:
        cv_espacos = 0

    # 3. Detectar outliers (Z-score > 2.5)
    try:
        z_scores = np.abs(stats.zscore(x_coords))
        if np.any(z_scores > 2.5):
            outliers = np.where(z_scores > 2.5)[0]
            return False, 0.5, f"Outliers detectados em índices: {outliers.tolist()}"
    except:
        pass  # Se não conseguir calcular z-score, continua

    # 4. Validar proporções de espaçamento
    if len(espacos) > 0:
        largura_total = x_sorted[-1] - x_sorted[0]
        espaco_esperado = largura_total / (num_alternativas - 1)
        desvios = np.abs(espacos - espaco_esperado)
        desvio_max = np.max(desvios)

        if desvio_max > raio_medio:
            return False, 0.6, f"Desvio de espaçamento: {desvio_max:.1f}px (esperado < {raio_medio:.1f}px)"

    # Calcular score de qualidade
    penalty_alignment = min(y_std / (raio_medio * 0.05), 1.0) if raio_medio > 0 else 0
    penalty_spacing = min(cv_espacos / 0.15, 1.0)
    penalty_deviation = min(desvio_max / raio_medio, 1.0) if raio_medio > 0 else 0

    quality_score = max(0.0, 1.0 - (penalty_alignment + penalty_spacing + penalty_deviation) / 3)

    return True, quality_score, "OK"

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
