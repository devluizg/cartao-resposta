# image_processing.py - VERSÃO COMPLETA CORRIGIDA
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
        return image, 1.0

    scale = max_width / w
    new_h = int(h * scale)

    resized = cv2.resize(image, (max_width, new_h), interpolation=cv2.INTER_AREA)
    return resized, scale


def _criar_template_bolha_cached(raio_px):
    """Cria ou recupera template bolha do cache (thread-safe)."""
    cache_key = f"template_{raio_px}"

    with _template_cache_lock:
        if cache_key in _template_cache:
            return _template_cache[cache_key]

        if raio_px < 3:
            raio_px = 3

        size = raio_px * 2 + 1
        template = np.zeros((size, size), dtype=np.uint8)
        cv2.circle(template, (raio_px, raio_px), raio_px, 255, -1)

        _template_cache[cache_key] = template

        return template


def limpar_cache_templates():
    """Limpa o cache de templates para liberar memória."""
    global _template_cache
    with _template_cache_lock:
        _template_cache.clear()


# ============================================================================
#  MÓDULO: FLASH VIRTUAL (substitui todo o módulo de remoção de sombra)
# ============================================================================

def aplicar_flash_virtual(gray):
    """
    Simula o efeito de um flash de celular na imagem.
    
    O flash faz 3 coisas que replicamos digitalmente:
    1. Estima a iluminação ambiente (blur gaussiano grande)
    2. Divide cada pixel pela iluminação local (remove sombras)
    3. Estica o contraste para que branco=255 e preto=0
    
    Resultado: imagem como se tivesse sido tirada com flash.
    Se a imagem já tinha boa iluminação, quase não muda (idempotente).
    
    Args:
        gray: Imagem em escala de cinza (uint8)
    
    Returns:
        flash_image: Imagem com "flash virtual" aplicado (uint8)
    """
    h, w = gray.shape
    gray_float = gray.astype(np.float64)
    
    # PASSO 1: Estimar a iluminação ambiente
    # Usar blur gaussiano muito grande - captura apenas variações de luz
    # (sombras, gradientes) mas não as bolhas/texto (alta frequência)
    # Tamanho = ~20% da menor dimensão, garante cobertura de sombras grandes
    ksize = int(min(h, w) * 0.2)
    if ksize % 2 == 0:
        ksize += 1
    ksize = max(ksize, 51)
    
    iluminacao = cv2.GaussianBlur(gray_float, (ksize, ksize), ksize // 3)
    
    # Evitar divisão por zero
    iluminacao = np.maximum(iluminacao, 1.0)
    
    # PASSO 2: Normalizar pela iluminação (como se toda a folha 
    # recebesse a mesma quantidade de luz)
    # Isso é equivalente ao que o flash faz fisicamente
    flash = (gray_float * 255.0) / iluminacao
    
    # PASSO 3: Clip e converter
    flash = np.clip(flash, 0, 255).astype(np.uint8)
    
    # PASSO 4: Esticar contraste para usar o range completo 0-255
    # Isso simula a saturação que o flash causa (branco=255, preto=0)
    # Usar percentis para ignorar outliers
    p_low = np.percentile(flash, 2)
    p_high = np.percentile(flash, 98)
    
    if p_high > p_low:
        flash = np.clip((flash.astype(np.float64) - p_low) * 255.0 / (p_high - p_low), 0, 255).astype(np.uint8)
    else:
        flash = cv2.normalize(flash, None, 0, 255, cv2.NORM_MINMAX)
    
    return flash


def _detectar_presenca_sombra(l_channel):
    """
    Detecta se a imagem possui sombra significativa.
    Mantida para log/diagnóstico, mas o flash virtual é aplicado sempre.
    """
    h, w = l_channel.shape
    quadrants = [
        l_channel[0:h//2, 0:w//2],
        l_channel[0:h//2, w//2:w],
        l_channel[h//2:h, 0:w//2],
        l_channel[h//2:h, w//2:w]
    ]
    quad_means = [float(np.mean(q)) for q in quadrants]
    quad_range = max(quad_means) - min(quad_means)
    
    grid_means = []
    step_h, step_w = h // 3, w // 3
    for i in range(3):
        for j in range(3):
            block = l_channel[i*step_h:(i+1)*step_h, j*step_w:(j+1)*step_w]
            if block.size > 0:
                grid_means.append(float(np.mean(block)))
    
    grid_range = max(grid_means) - min(grid_means) if grid_means else 0
    
    has_shadow = quad_range > 30 or grid_range > 40
    return has_shadow, quad_range, grid_range


# ============================================================================
#  PRÉ-PROCESSAMENTO
# ============================================================================

def melhorar_pre_processamento(image):
    """
    Pré-processamento avançado da imagem para melhorar detecção de bolhas.
    (Versão legada mantida para compatibilidade)
    
    Args:
        image: Imagem original em BGR
    
    Returns:
        binary: Imagem binária otimizada para detecção de bolhas
        normalized: Imagem normalizada para visualização
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(16, 16))
    equalized = clahe.apply(gray)
    
    denoised = cv2.GaussianBlur(equalized, (5, 5), 0)
    
    normalized = cv2.normalize(denoised, None, 0, 255, cv2.NORM_MINMAX)
    
    binary_adaptive = cv2.adaptiveThreshold(
        normalized, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
        cv2.THRESH_BINARY_INV, 21, 10
    )
    
    _, binary_otsu = cv2.threshold(normalized, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    
    binary = cv2.bitwise_or(binary_adaptive, binary_otsu)
    
    kernel_open = np.ones((3, 3), np.uint8)
    kernel_close = np.ones((7, 7), np.uint8)
    
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel_open)
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel_close)
    
    return binary, normalized


def melhorar_pre_processamento_adaptativo(image):
    """
    Pré-processamento com Flash Virtual.
    
    Filosofia: Em vez de ter pipelines diferentes para sombra/sem sombra,
    aplicar SEMPRE o flash virtual. Se a foto já é boa, não estraga.
    Se tem sombra, conserta. Igual flash real de celular.
    
    Pipeline simplificado:
    1. Extrair luminância (canal L do LAB)
    2. Aplicar flash virtual (normaliza iluminação)
    3. CLAHE leve (melhora contraste local)
    4. Binarização Otsu (funciona porque iluminação é uniforme)
    5. Limpeza morfológica
    """
    # 1. Extrair luminância
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l_channel, _, _ = cv2.split(lab)
    l_norm = cv2.normalize(l_channel, None, 0, 255, cv2.NORM_MINMAX)

    # Metadata para diagnóstico
    brightness = float(np.mean(l_norm))
    contrast = float(np.std(l_norm))
    has_shadow, quad_range, grid_range = _detectar_presenca_sombra(l_norm)
    
    metadata = {
        'brightness': brightness,
        'contrast': contrast,
        'illumination_profile': 'shadow_detected' if has_shadow else (
            'low_light' if brightness < 100 else (
                'high_light' if brightness > 180 else 'normal'
            )
        )
    }

    # 2. Correção de gamma para baixa luminosidade (antes do flash virtual)
    gamma = 1.0
    if brightness < 110:
        # Quanto mais escuro, maior a correção (clareia a imagem)
        # 70 -> ~1.8, 100 -> ~1.2
        gamma = float(np.clip(2.2 - (brightness / 100.0), 1.2, 2.2))
    if gamma != 1.0:
        inv_gamma = 1.0 / gamma
        table = (np.array([((i / 255.0) ** inv_gamma) * 255 for i in range(256)])
                 .astype("uint8"))
        l_norm = cv2.LUT(l_norm, table)
        metadata['gamma'] = gamma
    else:
        metadata['gamma'] = 1.0

    # 3. FLASH VIRTUAL — aplicado SEMPRE (idempotente)
    flash = aplicar_flash_virtual(l_norm)
    
    if has_shadow:
        print(f"  ⚡ Flash virtual aplicado (sombra detectada: quad={quad_range:.0f}, grid={grid_range:.0f})")
    
    # 4. CLAHE — Adaptativo baseado em contraste
    # ✅ FIX B1: Reduzir threshold de contraste de 40 para 45
    # ✅ FIX B2: Aumentar agressividade para contraste < 45
    # Filosofia: Se contraste < 45, a imagem é "lavada" e precisa de reforço maior
    if brightness < 110:
        clahe_limit, clahe_grid = 3.0, (12, 12)
    elif contrast < 45:  # ← CHANGED: 40 → 45 (detecção mais sensível)
        clahe_limit, clahe_grid = 4.0, (10, 10)  # ← CHANGED: 3.5 → 4.0, (12,12) → (10,10) mais agressivo
        print(f"  🔧 CLAHE AGRESSIVO para baixo contraste ({contrast:.0f}): clip={clahe_limit}, grid={clahe_grid}")
    else:
        clahe_limit, clahe_grid = 2.0, (8, 8)
    clahe = cv2.createCLAHE(clipLimit=clahe_limit, tileGridSize=clahe_grid)
    enhanced = clahe.apply(flash)
    
    # 5. Suavização leve
    filtered = cv2.GaussianBlur(enhanced, (3, 3), 0)
    
    # 6. Binarização — Otsu funciona perfeitamente com flash virtual
    # porque a distribuição bimodal (papel branco vs tinta preta) fica clara
    _, binary_otsu = cv2.threshold(filtered, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    
    # 7. Threshold adaptativo como complemento (captura detalhes finos)
    # Em baixa luz, usar janela maior e C menor para manter bolhas
    if brightness < 110 or contrast < 40:
        block_size = 31
        c_value = 6
    else:
        block_size = 21
        c_value = 8
    binary_adaptive = cv2.adaptiveThreshold(
        filtered, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV, block_size, c_value
    )
    
    # 8. Combinar: OR para não perder nenhuma bolha
    binary = cv2.bitwise_or(binary_otsu, binary_adaptive)
    
    # 9. Filtro de ruído: só manter pixels em regiões escuras
    # dark_thresh: pixels mais claros que isso no `filtered` são mascarados (descartados).
    # Para imagens lavadas/baixo contraste, reduzir threshold para não mascarar bolhas fracas.
    if brightness < 110:
        dark_thresh = int(np.clip(140 + (contrast * 0.5), 120, 170))
    elif contrast < 40:
        dark_thresh = int(np.clip(170 + (contrast * 0.5), 170, 195))  # lavada: mais permissivo
    else:
        dark_thresh = 200
    _, mask_dark = cv2.threshold(filtered, dark_thresh, 255, cv2.THRESH_BINARY)
    mask_dark = cv2.bitwise_not(mask_dark)
    kernel_dilate = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask_dark = cv2.dilate(mask_dark, kernel_dilate)
    binary = cv2.bitwise_and(binary, mask_dark)
    
    # 10. Limpeza morfológica
    kernel_open = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (3, 3) if brightness >= 110 else (5, 5)
    )
    kernel_close = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (5, 5) if brightness >= 110 else (7, 7)
    )
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel_open)
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel_close)

    # Métrica simples de densidade de pixels pretos para diagnóstico
    black_ratio = float(np.mean(binary > 0))
    metadata['black_ratio'] = black_ratio

    print(f"Pré-processamento: brightness={brightness:.0f}, contrast={contrast:.0f}, "
          f"shadow={'YES' if has_shadow else 'NO'} (quad={quad_range:.0f}, grid={grid_range:.0f}), "
          f"profile={metadata['illumination_profile']}, gamma={metadata['gamma']:.2f}, "
          f"black_ratio={black_ratio:.3f}")

    return binary, metadata


# ============================================================================
#  DETECÇÃO DE PERSPECTIVA
# ============================================================================

def _detectar_bordas_papel(image):
    """
    Detecta as bordas do papel usando Canny direto no grayscale.
    Não depende de binarização.
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    shadow_free = aplicar_flash_virtual(gray)
    blurred = cv2.GaussianBlur(shadow_free, (5, 5), 0)
    edges = cv2.Canny(blurred, 30, 100)
    kernel = np.ones((3, 3), np.uint8)
    edges = cv2.dilate(edges, kernel, iterations=1)
    return edges


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

    hull = cv2.convexHull(largest_contour)
    approx = cv2.approxPolyDP(hull, 0.02 * cv2.arcLength(hull, True), True)

    if len(approx) == 4:
        return approx.reshape(4, 2)

    return None


def _detectar_retangulo_por_ransac(binary):
    """Tenta detectar o retângulo usando Hough Lines e RANSAC."""
    lines = cv2.HoughLinesP(binary, 1, np.pi/180, 50, minLineLength=50, maxLineGap=10)

    if lines is None or len(lines) < 4:
        return None

    points = []
    for line in lines:
        x1, y1, x2, y2 = line[0]
        points.append([x1, y1])
        points.append([x2, y2])

    if len(points) < 4:
        return None

    points = np.array(points, dtype=np.float32)

    hull = cv2.convexHull(points)

    if len(hull) >= 4:
        perimeter = cv2.arcLength(hull, True)
        approx = cv2.approxPolyDP(hull, 0.02 * perimeter, True)

        if len(approx) == 4:
            return approx.reshape(4, 2)

    return None


def _detectar_retangulo_por_hough(image):
    """
    Detecta o retângulo do papel usando Hough Lines no espaço de Canny.
    Não depende de binarização - trabalha direto na imagem original.
    """
    edges = _detectar_bordas_papel(image)
    
    lines = cv2.HoughLinesP(edges, 1, np.pi/180, 80, 
                             minLineLength=min(image.shape[:2]) // 4,
                             maxLineGap=20)
    
    if lines is None or len(lines) < 4:
        return None
    
    h_lines = []
    v_lines = []
    
    for line in lines:
        x1, y1, x2, y2 = line[0]
        angle = np.abs(np.arctan2(y2 - y1, x2 - x1) * 180 / np.pi)
        
        if angle < 20 or angle > 160:
            h_lines.append(line[0])
        elif 70 < angle < 110:
            v_lines.append(line[0])
    
    if len(h_lines) < 2 or len(v_lines) < 2:
        return None
    
    h_lines.sort(key=lambda l: (l[1] + l[3]) / 2)
    v_lines.sort(key=lambda l: (l[0] + l[2]) / 2)
    
    top_line = h_lines[0]
    bottom_line = h_lines[-1]
    left_line = v_lines[0]
    right_line = v_lines[-1]
    
    def line_intersection(l1, l2):
        x1, y1, x2, y2 = l1
        x3, y3, x4, y4 = l2
        denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        if abs(denom) < 1e-10:
            return None
        t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom
        px = x1 + t * (x2 - x1)
        py = y1 + t * (y2 - y1)
        return (int(px), int(py))
    
    tl = line_intersection(top_line, left_line)
    tr = line_intersection(top_line, right_line)
    br = line_intersection(bottom_line, right_line)
    bl = line_intersection(bottom_line, left_line)
    
    if None in (tl, tr, br, bl):
        return None
    
    return np.array([tl, tr, br, bl], dtype=np.float32)


def _validar_proporcoes_a4(rect, tolerance=0.3):
    """Valida se o retângulo tem proporções A4 (1.414)."""
    if rect is None or len(rect) < 4:
        return False

    width_A = np.sqrt(((rect[2][0] - rect[3][0]) ** 2) + ((rect[2][1] - rect[3][1]) ** 2))
    height_A = np.sqrt(((rect[1][0] - rect[2][0]) ** 2) + ((rect[1][1] - rect[2][1]) ** 2))

    if max(width_A, height_A) == 0:
        return False

    ratio = max(width_A, height_A) / min(width_A, height_A)

    return (1.414 * (1 - tolerance) < ratio < 1.414 * (1 + tolerance))


def detectar_marcadores_de_canto(binary):
    """
    Detecta os 4 marcadores de canto sólidos (círculos pretos) do cartão v2.

    MUDANÇA: Agora usa Otsu LOCAL na ROI do canto (em vez de threshold fixo=60)
    e relaxa circularidade para 0.45 para lidar com bordas levemente distorcidas
    após remoção de sombra. Também adiciona verificação de solidez.

    Returns:
        np.ndarray shape (4,2) float32 com os centros, ou None se não detectar.
    """
    h, w = binary.shape

    # CORREÇÃO: usar binary diretamente (marcadores=branco em fundo preto).
    # Antes usava bitwise_not(binary) que invertia a polaridade e quebrava
    # o findContours (que detecta objetos BRANCOS em fundo PRETO).
    blurred = cv2.GaussianBlur(binary, (5, 5), 0)

    raio_min = int(min(h, w) * 0.02)
    raio_max = int(min(h, w) * 0.12)

    margin_x = w // 4
    margin_y = h // 4

    regioes = [
        (0, 0, margin_x, margin_y,          'TL'),
        (w - margin_x, 0, w, margin_y,      'TR'),
        (w - margin_x, h - margin_y, w, h, 'BR'),
        (0, h - margin_y, margin_x, h,      'BL'),
    ]

    centros = {}

    for (x1, y1, x2, y2, label) in regioes:
        roi = blurred[y1:y2, x1:x2]
        if roi.size == 0:
            continue

        # MUDANÇA: Usar Otsu LOCAL na ROI em vez de threshold fixo
        _, thresh_roi = cv2.threshold(roi, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        contornos, _ = cv2.findContours(thresh_roi, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        melhor = None
        melhor_score = 0

        for cnt in contornos:
            area = cv2.contourArea(cnt)
            if area < (raio_min ** 2 * 3.14) or area > (raio_max ** 2 * 3.14):
                continue

            perimeter = cv2.arcLength(cnt, True)
            if perimeter == 0:
                continue
            circularidade = 4 * np.pi * area / (perimeter ** 2)
            # Relaxar circularidade para 0.35 (lidar com distorção leve de perspectiva)
            if circularidade < 0.35:
                continue

            # Verificar solidez (relaxado para 0.6 para tolerar bordas imperfeitas)
            hull = cv2.convexHull(cnt)
            hull_area = cv2.contourArea(hull)
            solidity = area / hull_area if hull_area > 0 else 0
            if solidity < 0.6:
                continue

            score = area * circularidade * solidity
            if score > melhor_score:
                melhor_score = score
                M = cv2.moments(cnt)
                if M['m00'] > 0:
                    cx = int(M['m10'] / M['m00']) + x1
                    cy = int(M['m01'] / M['m00']) + y1
                    melhor = (cx, cy)

        if melhor is not None:
            centros[label] = melhor
        else:
            # Fallback: HoughCircles na ROI
            circles = cv2.HoughCircles(
                roi,
                cv2.HOUGH_GRADIENT,
                dp=1.2,
                minDist=raio_min * 2,
                param1=50,
                param2=15,  # MUDANÇA: Reduzido de 20 para 15 (mais sensível)
                minRadius=raio_min,
                maxRadius=raio_max,
            )
            if circles is not None:
                circles = np.round(circles[0]).astype(int)
                maior = max(circles, key=lambda c: c[2])
                centros[label] = (int(maior[0]) + x1, int(maior[1]) + y1)

    if len(centros) < 4:
        print(f"Marcadores de canto: detectados {len(centros)}/4 — fallback para contorno")
        return None

    tl = centros.get('TL')
    tr = centros.get('TR')
    br = centros.get('BR')
    bl = centros.get('BL')

    if None in (tl, tr, br, bl):
        return None

    pts = np.array([tl, tr, br, bl], dtype=np.float32)
    print(f"✅ Marcadores de canto detectados: TL={tl} TR={tr} BR={br} BL={bl}")
    return pts


def corrigir_perspectiva(image, binary):
    """
    Correção de perspectiva usando flash virtual para o binary de detecção.
    """
    h, w = binary.shape

    # Criar binary para perspectiva usando flash virtual
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    
    # Flash virtual para normalizar iluminação
    flash = aplicar_flash_virtual(gray)
    
    # CLAHE mais agressivo para detectar marcadores de canto em imagens com sombra.
    # tileGridSize=(4,4) com clipLimit=4.0 melhora regiões de canto com iluminação irregular.
    clahe = cv2.createCLAHE(clipLimit=4.0, tileGridSize=(4, 4))
    enhanced = clahe.apply(flash)
    
    # Suavização
    filtered = cv2.GaussianBlur(enhanced, (3, 3), 0)
    
    # Binarização
    _, binary_for_persp = cv2.threshold(filtered, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    
    binary_adaptive = cv2.adaptiveThreshold(
        filtered, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV, 21, 10
    )
    binary_for_persp = cv2.bitwise_or(binary_for_persp, binary_adaptive)
    
    # Limpeza
    kernel_open = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    kernel_close = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    binary_for_persp = cv2.morphologyEx(binary_for_persp, cv2.MORPH_OPEN, kernel_open)
    binary_for_persp = cv2.morphologyEx(binary_for_persp, cv2.MORPH_CLOSE, kernel_close)

    # === Método 0: Marcadores de canto ===
    ordered_rect = None
    pts_marcadores = detectar_marcadores_de_canto(binary_for_persp)
    if pts_marcadores is not None:
        ordered_rect = pts_marcadores
        print("✅ Usando marcadores de canto para correção de perspectiva")

    if ordered_rect is None:
        # Método 1: Contornos
        rect = _detectar_retangulo_por_contorno(binary_for_persp)

        # Método 2: Hough Lines (independente de binary)
        if rect is None:
            rect_hough = _detectar_retangulo_por_hough(image)
            if rect_hough is not None:
                ordered_rect = rect_hough
                print("✅ Perspectiva via Hough Lines")

        # Método 3: RANSAC
        if rect is None and ordered_rect is None:
            rect = _detectar_retangulo_por_ransac(binary_for_persp)

        # Método 4: Bounding box
        if rect is None and ordered_rect is None:
            contours, _ = cv2.findContours(binary_for_persp, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if not contours:
                return image, binary, False
            largest = max(contours, key=cv2.contourArea)
            x, y, w_rect, h_rect = cv2.boundingRect(largest)
            rect = np.array([[x, y], [x + w_rect, y], [x + w_rect, y + h_rect], [x, y + h_rect]], dtype=np.float32)

        if rect is None and ordered_rect is None:
            return image, binary, False

        if ordered_rect is None:
            rect = rect.reshape(4, 2).astype(np.float32)
            sum_coords = rect.sum(axis=1)
            diff_coords = np.diff(rect, axis=1)
            ordered_rect = np.zeros((4, 2), dtype=np.float32)
            ordered_rect[0] = rect[np.argmin(sum_coords)]
            ordered_rect[1] = rect[np.argmin(diff_coords)]
            ordered_rect[2] = rect[np.argmax(sum_coords)]
            ordered_rect[3] = rect[np.argmax(diff_coords)]

    if not _validar_proporcoes_a4(ordered_rect):
        pass

    width_A = np.sqrt(((ordered_rect[2][0] - ordered_rect[3][0]) ** 2) + ((ordered_rect[2][1] - ordered_rect[3][1]) ** 2))
    width_B = np.sqrt(((ordered_rect[1][0] - ordered_rect[0][0]) ** 2) + ((ordered_rect[1][1] - ordered_rect[0][1]) ** 2))
    max_width = max(int(width_A), int(width_B))

    height_A = np.sqrt(((ordered_rect[1][0] - ordered_rect[2][0]) ** 2) + ((ordered_rect[1][1] - ordered_rect[2][1]) ** 2))
    height_B = np.sqrt(((ordered_rect[0][0] - ordered_rect[3][0]) ** 2) + ((ordered_rect[0][1] - ordered_rect[3][1]) ** 2))
    max_height = max(int(height_A), int(height_B))

    area = max_width * max_height
    if area < (h * w) * 0.2:
        return image, binary, False
    if max_width > w * 2 or max_height > h * 2:
        return image, binary, False
    if max_width < 100 or max_height < 100:
        return image, binary, False

    dst = np.array([
        [0, 0], [max_width - 1, 0],
        [max_width - 1, max_height - 1], [0, max_height - 1]
    ], dtype=np.float32)

    try:
        transform_matrix = cv2.getPerspectiveTransform(ordered_rect, dst)
        corrected_image = cv2.warpPerspective(image, transform_matrix, (max_width, max_height))
        corrected_binary = cv2.warpPerspective(binary, transform_matrix, (max_width, max_height))
        return corrected_image, corrected_binary, True
    except Exception as e:
        print(f"Erro na perspectiva: {e}")
        return image, binary, False


# ============================================================================
#  DETECÇÃO DE BOLHAS
# ============================================================================

def _estimar_escala_imagem(binary):
    """
    Estima a escala da imagem (pixels por mm) baseado na análise
    da estrutura do cartão resposta.

    ✅ VERSÃO V6 - CÁLCULO MATEMÁTICO (não empírico)

    Referência de design (PDF atual):
    - Largura real da caixa de bolhas: 43mm (5 bolhas × 7mm + margens)
    - Raio real da bolha: 2.5mm
    - Imagem completa (A4): ~210mm de largura

    LÓGICA:
    Se a imagem ROI tem width_px pixels
    E a caixa real tem 43mm de largura
    Então: 1mm na imagem = width_px / 43 pixels
    Logo: raio_px = 2.5mm * (width_px / 43)

    MATEMÁTICO:
    - ROI 384px → 384/43 = 8.93 px/mm → raio = 2.5 * 8.93 = 22.3px ✓
    - ROI 244px → 244/43 = 5.67 px/mm → raio = 2.5 * 5.67 = 14.2px (antes era 9.4px com divisor=70)
    - ROI 175px → 175/43 = 4.07 px/mm → raio = 2.5 * 4.07 = 10.2px (antes era 2.5px com divisor=70)
    """
    h, w = binary.shape
    min_dim = min(w, h)

    # Cálculo matemático
    CAIXA_BOLHAS_MM = 43.0  # Largura real da caixa de bolhas em mm
    RAIO_BOLHA_MM = 2.5     # Raio real da bolha em mm

    # Pixels por milímetro
    px_per_mm = min_dim / CAIXA_BOLHAS_MM

    # Raio da bolha em pixels
    raio_px = RAIO_BOLHA_MM * px_per_mm

    # Log de debug
    print(f"  📐 Escala matemática: {min_dim}px / {CAIXA_BOLHAS_MM}mm = {px_per_mm:.2f} px/mm → raio={raio_px:.1f}px")

    return max(px_per_mm, 1.0)


def _criar_template_bolha(raio_px):
    """Cria um template circular para template matching (usa cache)."""
    return _criar_template_bolha_cached(raio_px)


def _detectar_hough_adaptativo(binary, min_radius, max_radius, param2=12):
    """Detecta círculos usando HoughCircles com parâmetros adaptativos."""
    img_for_circles = 255 - binary.copy()
    img_for_circles = cv2.GaussianBlur(img_for_circles, (5, 5), 0)

    circles = cv2.HoughCircles(
        img_for_circles,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=max(min_radius * 1.0, 10),
        param1=40,
        param2=param2,
        minRadius=int(min_radius * 0.7),
        maxRadius=int(max_radius * 1.3)
    )

    if circles is not None:
        return np.uint16(np.around(circles[0]))
    return np.array([])


def _detectar_template_matching(binary, raio_px, threshold_template=0.45):
    """Detecta círculos usando template matching com NMS."""
    template = _criar_template_bolha(raio_px)

    if template.shape[0] > binary.shape[0] or template.shape[1] > binary.shape[1]:
        return np.array([])

    result = cv2.matchTemplate(binary, template, cv2.TM_CCOEFF_NORMED)
    mask = (result >= threshold_template).astype(np.uint8)

    if not mask.any():
        return np.array([])

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

            contour = np.array(region, dtype=np.int32).reshape(-1, 1, 2)

            area = cv2.contourArea(contour)
            if area < np.pi * (min_radius ** 2) or area > np.pi * (max_radius ** 2):
                continue

            radius_equiv = np.sqrt(area / np.pi)

            M = cv2.moments(contour)
            if M["m00"] != 0:
                cx = int(M["m10"] / M["m00"])
                cy = int(M["m01"] / M["m00"])
                circles.append([cx, cy, int(radius_equiv)])

        return np.array(circles)
    except:
        return np.array([])


def _detectar_contornos_com_features(binary, min_radius, max_radius, circularity_min=0.70):
    """Detecta círculos por contornos com filtro de circularidade."""
    contours, _ = cv2.findContours(binary, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)

    circles = []
    for cnt in contours:
        area = cv2.contourArea(cnt)

        min_area = np.pi * (min_radius ** 2) * 0.5
        max_area = np.pi * (max_radius ** 2) * 1.5
        if area < min_area or area > max_area:
            continue

        perimeter = cv2.arcLength(cnt, True)
        if perimeter == 0:
            continue

        circularity = 4 * np.pi * area / (perimeter * perimeter)
        if circularity < circularity_min:
            continue

        M = cv2.moments(cnt)
        if M["m00"] != 0:
            cx = int(M["m10"] / M["m00"])
            cy = int(M["m01"] / M["m00"])

            radius = int(np.sqrt(area / np.pi))
            if min_radius * 0.7 <= radius <= max_radius * 1.3:
                circles.append([cx, cy, radius])

    return np.array(circles)


def _aplicar_voting_system(circle_lists, threshold_distancia, min_expected_bolhas=60):
    """
    v2: Voting adaptativo - 2 métodos quando há muitas detecções,
    1 método quando há poucas (região difícil).
    """
    if all(len(circles) == 0 for circles in circle_lists):
        return np.array([])

    # Contar total de detecções brutas
    total_detections = sum(len(c) for c in circle_lists)
    
    # Criar lista de (circulo, metodo_idx) 
    todos = []
    for method_idx, circles in enumerate(circle_lists):
        for c in circles:
            todos.append((c, method_idx))

    if len(todos) == 0:
        return np.array([])

    bolhas_finais = []
    usados = set()

    for i, (circulo, metodo_i) in enumerate(todos):
        if i in usados:
            continue

        grupo = [(circulo, metodo_i)]
        metodos_no_grupo = {metodo_i}

        for j, (outro, metodo_j) in enumerate(todos):
            if i != j and j not in usados:
                dist = np.sqrt((int(circulo[0]) - int(outro[0]))**2 + (int(circulo[1]) - int(outro[1]))**2)
                if dist < threshold_distancia:
                    grupo.append((outro, metodo_j))
                    metodos_no_grupo.add(metodo_j)
                    usados.add(j)

        # Requer 2+ métodos
        if len(metodos_no_grupo) >= 2:
            circulos_grupo = [c for c, _ in grupo]
            cx_medio = int(np.mean([c[0] for c in circulos_grupo]))
            cy_medio = int(np.mean([c[1] for c in circulos_grupo]))
            r_medio = int(np.mean([c[2] for c in circulos_grupo]))
            bolhas_finais.append([cx_medio, cy_medio, r_medio])

        usados.add(i)

    # FALLBACK ADAPTATIVO: Se votação rigorosa encontrou poucas bolhas
    # e há detecções disponíveis, relaxar para 1 método
    if len(bolhas_finais) < min_expected_bolhas and total_detections > len(bolhas_finais):
        print(f"  ⚠️ Voting encontrou apenas {len(bolhas_finais)} bolhas de {total_detections} detecções, relaxando...")

        # Priorizar Template Matching (índice 1 no circle_lists)
        for method_idx, circles in enumerate(circle_lists):
            # No relaxamento, se detectou pelo menos pelo template matching,
            # damos uma chance, pois ele é robusto à iluminação ruim
            if method_idx != 1 and len(circle_lists[1]) > 0:
                continue

            for c in circles:
                cx, cy, r = int(c[0]), int(c[1]), int(c[2])

                # Verificar se já existe bolha próxima nas finais
                conflito = False
                for bf in bolhas_finais:
                    dist = np.sqrt((cx - bf[0])**2 + (cy - bf[1])**2)
                    if dist < threshold_distancia:
                        conflito = True
                        break

                if not conflito:
                    bolhas_finais.append([cx, cy, r])

    # PASSE ADICIONAL: Sempre incluir detecções do Template Matching (índice 1)
    # que NÃO foram aceitas pelo voting. O template é um disco sólido branco,
    # então template matches = bolhas MARCADAS/PREENCHIDAS — exatamente o que queremos.
    # Bolhas vazias (anéis) raramente correspondem ao template sólido.
    if len(circle_lists) > 1 and len(circle_lists[1]) > 0:
        template_adicionados = 0
        for c in circle_lists[1]:
            cx, cy, r = int(c[0]), int(c[1]), int(c[2])
            conflito = False
            for bf in bolhas_finais:
                dist = np.sqrt((cx - bf[0])**2 + (cy - bf[1])**2)
                if dist < threshold_distancia:
                    conflito = True
                    break
            if not conflito:
                bolhas_finais.append([cx, cy, r])
                template_adicionados += 1
        if template_adicionados > 0:
            print(f"  ℹ️ Template Matching adicionou {template_adicionados} bolha(s) preenchida(s) ao voting")

    return np.array(bolhas_finais) if bolhas_finais else np.array([])


def detectar_bolhas_avancado(binary, debug_image=None, threshold=100, sensitivity=0.5, quality_meta=None):
    """
    Detecta bolhas em um cartão resposta com método híbrido (4 detectores + voting system).

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

    escala = _estimar_escala_imagem(binary)

    # Raio calibrado para o novo cartão resposta: bolhas Ø 5 mm (raio 2.5 mm)
    raio_esperado_mm = 2.5
    raio_px = int(raio_esperado_mm * escala)
    min_radius = max(int(raio_px * 0.6), 4)
    max_radius = int(raio_px * 1.4)

    # Ajustes para baixa luminosidade/baixo contraste
    brightness = None
    contrast = None
    black_ratio = None
    if isinstance(quality_meta, dict):
        brightness = quality_meta.get('brightness')
        contrast = quality_meta.get('contrast')
        black_ratio = quality_meta.get('black_ratio')

    low_light = False
    if brightness is not None and contrast is not None:
        low_light = brightness < 110 or contrast < 40

    if low_light or (black_ratio is not None and black_ratio < 0.01):
        # Relaxar limites de raio e circularidade em baixa luz
        min_radius = max(int(raio_px * 0.5), 3)
        max_radius = int(raio_px * 1.6)

    # Método 1: HoughCircles Adaptativo
    # param2 baixo (12) detecta discos sólidos (bolhas marcadas, apenas 1 borda de gradiente)
    # sem deixar de detectar anéis vazios (que têm 2 bordas = acumulação Hough mais forte)
    hough_param2 = 12 if not low_light else 9
    circles_hough = _detectar_hough_adaptativo(binary, min_radius, max_radius, param2=hough_param2)

    # Método 2: Template Matching
    template_thresh = 0.45 if not low_light else 0.35
    circles_template = _detectar_template_matching(binary, raio_px, threshold_template=template_thresh)

    # Método 3: MSER + Circularidade
    circles_mser = _detectar_mser(binary, min_radius, max_radius)

    # Método 4: Contornos com features
    circularity_min = 0.70 if not low_light else 0.60
    circles_contour = _detectar_contornos_com_features(
        binary, min_radius, max_radius, circularity_min=circularity_min
    )

    # Voting System com concordância de 2+ métodos
    circle_lists = [circles_hough, circles_template, circles_mser, circles_contour]
    min_expected = 50
    if low_light or (black_ratio is not None and black_ratio < 0.01):
        min_expected = 30
    bolhas_votadas = _aplicar_voting_system(circle_lists, raio_px * 1.0, min_expected_bolhas=min_expected)

    # ── EXCLUSÃO DE ZONA DE CABEÇALHO ────────────────────────────────────────
    # Dois modos dependendo se estamos processando a imagem completa ou ROI de coluna:
    #
    # IMAGEM COMPLETA (h > 1200px): exclui 20% do topo.
    #   → Cobre QR code + título (grade começa em ~23-33% do topo).
    #
    # ROI DE COLUNA (h <= 1200px): exclui 9% do topo.
    #   → A-E header fica a ~13mm do topo da caixa de coluna ≈ 7% da altura do ROI.
    #   → 9% garante margem para imagens com zoom maior (ROI mais alto).
    #   → Primeira bolha está a ~18.5mm ≈ 10% do topo → bolhas preservadas.
    #   → 8% é seguro: primeira bolha está a ~9.25mm do topo da caixa (~10% do ROI).
    #   → 9% cortava a primeira bolha para ROIs grandes (h=1013, primeira bolha em y=88px).
    if h > 1200:
        zona_cabecalho = int(h * 0.20)   # imagem completa: cobre QR + título
    else:
        zona_cabecalho = int(h * 0.08)   # ROI de coluna: cobre A-E header (8%)

    bolhas_antes = len(bolhas_votadas)
    bolhas_votadas = [c for c in bolhas_votadas if int(c[1]) > zona_cabecalho]
    if len(bolhas_votadas) < bolhas_antes:
        modo = "imagem completa" if h > 1200 else "ROI coluna"
        print(f"  🔳 Cabeçalho ({modo}): {bolhas_antes - len(bolhas_votadas)} detecção(ões) "
              f"removida(s) acima de y={zona_cabecalho}px")

    # Decidir polaridade do preenchimento (branco vs preto) com base nas bolhas detectadas
    use_dark_fill = False
    if len(bolhas_votadas) > 0:
        sample_rates = []
        for circulo in bolhas_votadas:
            x, y, r = int(circulo[0]), int(circulo[1]), int(circulo[2])
            if x - r < 0 or y - r < 0 or x + r >= w or y + r >= h:
                continue
            inner_mask = np.zeros_like(binary)
            inner_r = int(r * 0.75)
            cv2.circle(inner_mask, (x, y), inner_r, 255, -1)
            roi = cv2.bitwise_and(binary, inner_mask)
            inner_area = np.pi * inner_r * inner_r
            if inner_area <= 0:
                continue
            white_rate = cv2.countNonZero(roi) / inner_area
            dark_rate = 1.0 - white_rate
            sample_rates.append((white_rate, dark_rate))

        if sample_rates:
            avg_white = float(np.mean([r[0] for r in sample_rates]))
            avg_dark = float(np.mean([r[1] for r in sample_rates]))
            # Se a maioria das bolhas tem interior mais escuro, usar preenchimento escuro
            if avg_dark > avg_white * 1.2:
                use_dark_fill = True

    # Converter para formato de bolhas
    bolhas = []
    for circulo in bolhas_votadas:
        x, y, r = int(circulo[0]), int(circulo[1]), int(circulo[2])

        if x - r < 0 or y - r < 0 or x + r >= w or y + r >= h:
            continue

        # Analisar preenchimento com raio interno
        mask = np.zeros_like(binary)
        cv2.circle(mask, (x, y), r, 255, -1)

        inner_mask = np.zeros_like(binary)
        inner_r = int(r * 0.75)
        cv2.circle(inner_mask, (x, y), inner_r, 255, -1)

        roi = cv2.bitwise_and(binary, inner_mask)
        inner_area = np.pi * inner_r * inner_r
        filled_pixels = cv2.countNonZero(roi)
        white_rate = filled_pixels / inner_area if inner_area > 0 else 0
        fill_rate = (1.0 - white_rate) if use_dark_fill else white_rate

        # Em baixa luz, reduzir a sensibilidade para não perder preenchimentos
        effective_sens = sensitivity
        if low_light:
            effective_sens = max(0.35, sensitivity * 0.8)
        is_filled = fill_rate > effective_sens

        bolhas.append({
            'x': x,
            'y': y,
            'centro': (x, y),
            'radius': r,
            'fill_rate': fill_rate,
            'filled': is_filled
        })

        color = (0, 0, 255) if is_filled else (0, 255, 0)
        cv2.circle(debug_img, (x, y), r, color, 2)
        cv2.putText(debug_img, f"{int(fill_rate * 100)}%", (x - 20, y - 15),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, color, 1)

    return bolhas, debug_img


# ============================================================================
#  AGRUPAMENTO DE BOLHAS
# ============================================================================

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

    if 'centro' in bolhas[0]:
        centros = np.array([bolha['centro'] for bolha in bolhas])
    else:
        centros = np.array([[bolha['x'], bolha['y']] for bolha in bolhas])

    from sklearn.cluster import KMeans

    y_coords = np.array([c[1] for c in centros])
    y_only = y_coords.reshape(-1, 1)

    raio_medio_bolhas = float(np.median([b.get('radius', 10) for b in bolhas]))

    # Eps adaptativo: usa espaçamento estimado entre linhas para evitar
    # que DBSCAN fragmente linhas levemente inclinadas OU mescle linhas adjacentes.
    y_range = float(np.max(y_coords) - np.min(y_coords)) if len(y_coords) > 1 else 100.0
    if num_questoes > 1 and y_range > 0:
        estimated_spacing = y_range / (num_questoes - 1)
        # Até 40% do espaçamento entre linhas: absorve inclinação sem cruzar para a próxima fila
        eps_from_spacing = estimated_spacing * 0.40
    else:
        eps_from_spacing = raio_medio_bolhas * 2.0
    # Garante um mínimo tolerante (para bolhas com raio grande) mas nunca maior que o spacing
    eps_linha = max(min(eps_from_spacing, raio_medio_bolhas * 2.5), 8.0)
    print(f"  DBSCAN eps adaptativo: {eps_linha:.1f}px "
          f"(spacing_est={y_range/(max(num_questoes-1,1)):.1f}px, raio={raio_medio_bolhas:.1f}px)")

    db_linhas = DBSCAN(eps=eps_linha, min_samples=1).fit(y_only)
    linhas_labels = db_linhas.labels_
    linhas_naturais = len(set(linhas_labels[linhas_labels != -1]))

    if num_questoes <= linhas_naturais <= int(num_questoes * 1.5):
        labels = linhas_labels
        print(f"DBSCAN: {linhas_naturais} linhas físicas detectadas (esperado {num_questoes}). Usando DBSCAN.")
    else:
        effective_clusters = linhas_naturais if (0 < linhas_naturais < num_questoes) else num_questoes
        if 0 < linhas_naturais < num_questoes:
            print(f"Aviso: DBSCAN detectou apenas {linhas_naturais} linhas (esperado {num_questoes}). "
                  f"Usando KMeans({effective_clusters}).")
        try:
            kmeans = KMeans(n_clusters=effective_clusters, random_state=42, n_init=10)
            labels = kmeans.fit_predict(y_only)
        except Exception:
            labels = linhas_labels
    
    clusters = defaultdict(list)
    for i, bolha in enumerate(bolhas):
        if labels[i] != -1:
            clusters[labels[i]].append(bolha)
    
    sorted_clusters = sorted(
        clusters.values(),
        key=lambda cluster: np.mean([b['centro'][1] if 'centro' in b else b['y'] for b in cluster])
    )
    
    if len(sorted_clusters) != num_questoes:
        print(f"Aviso: Detectadas {len(sorted_clusters)} linhas de questões (esperado {num_questoes}).")

        if len(sorted_clusters) > num_questoes:
            y_means = np.array([
                np.mean([b['centro'][1] if 'centro' in b else b['y'] for b in c])
                for c in sorted_clusters
            ])
            n = len(sorted_clusters)
            k = num_questoes

            min_bolhas = 2
            candidatos = [(i, c) for i, c in enumerate(sorted_clusters)
                         if len(c) >= min_bolhas]

            if len(candidatos) < k:
                candidatos = list(enumerate(sorted_clusters))

            if len(candidatos) == k:
                sorted_clusters = [c for _, c in candidatos]
            else:
                idxs_cands = [i for i, _ in candidatos]
                y_cands = y_means[idxs_cands]

                melhor_var = float('inf')
                melhor_escolha = idxs_cands[:k]

                from itertools import combinations
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
                    clusters_info = []
                    for i, c in enumerate(sorted_clusters):
                        nb = len(c)
                        clusters_info.append((nb, i, c))
                    clusters_info.sort(reverse=True)
                    melhor_escolha = sorted([info[1] for info in clusters_info[:k]])

                sorted_clusters = [sorted_clusters[i] for i in melhor_escolha]

            sorted_clusters = sorted(
                sorted_clusters,
                key=lambda cluster: np.mean([b['centro'][1] if 'centro' in b else b['y'] for b in cluster])
            )
    
    sorted_clusters = sorted_clusters[:num_questoes]
    
    questoes = []
    for cluster in sorted_clusters:
        if not cluster:
            questoes.append([])
            continue
            
        if 'centro' in cluster[0]:
            bolhas_ordenadas = sorted(cluster, key=lambda b: b['centro'][0])
        else:
            bolhas_ordenadas = sorted(cluster, key=lambda b: b['x'])
        
        if len(bolhas_ordenadas) > num_alternativas:
            y_vals = [b.get('y', b['centro'][1]) for b in bolhas_ordenadas]
            y_range = max(y_vals) - min(y_vals)
            raio_cluster = float(np.median([b.get('radius', 10) for b in bolhas_ordenadas]))
            if y_range > raio_cluster * 2:
                y_med = float(np.median(y_vals))
                bolhas_ordenadas = [b for b in bolhas_ordenadas
                                    if abs(b.get('y', b['centro'][1]) - y_med) <= raio_cluster * 1.5]
                bolhas_ordenadas = sorted(bolhas_ordenadas,
                                         key=lambda b: b['centro'][0] if 'centro' in b else b['x'])

            if len(bolhas_ordenadas) > num_alternativas:
                # Find the best contiguous sequence of exactly num_alternativas bubbles
                # Criteria: most uniform horizontal spacing
                melhor_seq = bolhas_ordenadas[:num_alternativas]
                menor_var_espaco = float('inf')
                
                for i in range(len(bolhas_ordenadas) - num_alternativas + 1):
                    seq = bolhas_ordenadas[i:i + num_alternativas]
                    xs = [b['centro'][0] if 'centro' in b else b['x'] for b in seq]
                    espacos = np.diff(np.sort(xs))
                    if len(espacos) > 0:
                        var = np.std(espacos)
                        if var < menor_var_espaco:
                            menor_var_espaco = var
                            melhor_seq = seq
                
                bolhas_ordenadas = melhor_seq
        
        if len(bolhas_ordenadas) < num_alternativas:
            if len(bolhas_ordenadas) >= 2:
                x_coords = [b['centro'][0] if 'centro' in b else b['x'] for b in bolhas_ordenadas]
                x_sorted = np.sort(x_coords)
                x_diffs = np.diff(x_sorted)
                if len(x_diffs) > 0:
                    espaco_medio = np.mean(x_diffs)
                    y_medio = np.mean([b['centro'][1] if 'centro' in b else b['y'] for b in bolhas_ordenadas])
                    raio_medio = np.mean([b.get('radius', 10) for b in bolhas_ordenadas])
                    
                    x_coords_esperados = []
                    if len(x_coords) >= num_alternativas:
                        inicio = np.min(x_coords)
                    else:
                        possiveis_inicios = [x_sorted[0] - i * espaco_medio for i in range(num_alternativas)]
                        melhor_inicio = x_sorted[0]
                        melhor_score = float('inf')
                        
                        for inicio in possiveis_inicios:
                            posicoes = [inicio + i * espaco_medio for i in range(num_alternativas)]
                            erros = []
                            for pos in posicoes:
                                min_dist = min([abs(pos - x) for x in x_coords], default=float('inf'))
                                erros.append(min_dist)
                            score = sum(erros)
                            if score < melhor_score:
                                melhor_score = score
                                melhor_inicio = inicio
                        
                        inicio = max(0, melhor_inicio)
                    
                    x_coords_esperados = [inicio + i * espaco_medio for i in range(num_alternativas)]
                    
                    bolhas_completas = []
                    bolhas_usadas = set()
                    
                    for x_esperado in x_coords_esperados:
                        melhor_bolha = None
                        menor_distancia = float('inf')
                        
                        for i, bolha in enumerate(bolhas_ordenadas):
                            if i in bolhas_usadas:
                                continue
                                
                            x_atual = bolha['centro'][0] if 'centro' in bolha else bolha['x']
                            distancia = abs(x_atual - x_esperado)
                            
                            if distancia < espaco_medio * 0.5 and distancia < menor_distancia:
                                menor_distancia = distancia
                                melhor_bolha = bolha
                        
                        if melhor_bolha:
                            idx = bolhas_ordenadas.index(melhor_bolha)
                            bolhas_usadas.add(idx)
                            bolhas_completas.append(melhor_bolha)
                        else:
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
                    
                    if bolhas_completas:
                        bolhas_ordenadas = sorted(bolhas_completas, 
                                                key=lambda b: b['centro'][0] if 'centro' in b else b['x'])
        
        questoes.append(bolhas_ordenadas[:num_alternativas])
    
    return questoes

def detectar_retangulos_colunas(binary, image, num_colunas):
    """
    Detecta os retângulos impressos que contornam as colunas de bolhas.
    Usa a imagem shadow-free para encontrar os retângulos de forma robusta.
    
    Returns:
        lista de (x, y, w, h) ordenados da esquerda para direita,
        ou None se não conseguir detectar.
    """
    h_img, w_img = binary.shape
    
    # Tentar na binary primeiro
    retangulos = _encontrar_retangulos_em_binary(binary, h_img, w_img, num_colunas)
    
    if retangulos is not None and len(retangulos) == num_colunas:
        print(f"  ✅ Retângulos de colunas detectados na binary: {len(retangulos)}")
        return retangulos
    
    # Fallback: usar imagem shadow-free com Canny
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image
    shadow_free = aplicar_flash_virtual(gray)
    
    # Binarizar shadow-free
    _, sf_binary = cv2.threshold(shadow_free, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    
    retangulos = _encontrar_retangulos_em_binary(sf_binary, h_img, w_img, num_colunas)
    
    if retangulos is not None and len(retangulos) == num_colunas:
        print(f"  ✅ Retângulos de colunas detectados na shadow-free: {len(retangulos)}")
        return retangulos
    
    # Fallback 2: Canny edges
    edges = cv2.Canny(shadow_free, 30, 100)
    kernel = np.ones((3, 3), np.uint8)
    edges = cv2.dilate(edges, kernel, iterations=2)
    
    retangulos = _encontrar_retangulos_em_binary(edges, h_img, w_img, num_colunas)
    
    if retangulos is not None and len(retangulos) >= num_colunas:
        print(f"  ✅ Retângulos de colunas detectados via Canny: {len(retangulos)}")
        return retangulos[:num_colunas]
    
    print(f"  ⚠️ Não foi possível detectar retângulos de colunas")
    return None


def _encontrar_retangulos_em_binary(binary, h_img, w_img, num_colunas):
    """
    Encontra retângulos que são candidatos a bordas de colunas.
    """
    # Fechar gaps nas linhas dos retângulos
    kernel_close = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    closed = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel_close)
    
    contours, hierarchy = cv2.findContours(closed, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)
    
    if not contours:
        return None
    
    candidatos = []
    
    for i, cnt in enumerate(contours):
        area = cv2.contourArea(cnt)
        
        # Retângulo de coluna deve ter área entre 1% e 50% da imagem
        area_ratio = area / (h_img * w_img)
        if area_ratio < 0.01 or area_ratio > 0.50:
            continue
        
        # Aproximar polígono
        peri = cv2.arcLength(cnt, True)
        if peri == 0:
            continue
        approx = cv2.approxPolyDP(cnt, 0.02 * peri, True)
        
        # Deve ter 4 vértices (retângulo) ou próximo
        if len(approx) < 4 or len(approx) > 12:
            continue
        
        x, y, rw, rh = cv2.boundingRect(cnt)
        
        # Retângulo de coluna é robusto em altura e não pode ser muito largo
        if rh < h_img * 0.25 or rw > w_img * 0.60:
            continue
        
        aspect = rh / rw if rw > 0 else 0
        if aspect < 1.2:  # Colunas devem ser mais altas que largas
            continue
        
        # Verificar retangularidade (quanto da bounding box é preenchida)
        rect_area = rw * rh
        rectangularity = area / rect_area if rect_area > 0 else 0
        
        if rectangularity < 0.05:  # Muito pouco preenchimento = não é retângulo
            continue
        
        candidatos.append({
            'bbox': (x, y, rw, rh),
            'area': area,
            'aspect': aspect,
            'rectangularity': rectangularity,
            'contour': cnt
        })
    
    if not candidatos:
        return None
    
    candidatos.sort(key=lambda c: c['area'] * c['rectangularity'], reverse=True)
    
    # Filtrar candidatos que se sobrepõem
    selecionados = []
    for cand in candidatos:
        x1, y1, w1, h1 = cand['bbox']
        
        sobrepoe = False
        for sel in selecionados:
            x2, y2, w2, h2 = sel['bbox']
            
            # Verificar sobreposição horizontal e vertical
            overlap_x = max(0, min(x1+w1, x2+w2) - max(x1, x2))
            overlap_y = max(0, min(y1+h1, y2+h2) - max(y1, y2))
            
            if overlap_x > min(w1, w2) * 0.3 and overlap_y > min(h1, h2) * 0.3:
                sobrepoe = True
                break
        
        if not sobrepoe:
            selecionados.append(cand)
        
        if len(selecionados) >= num_colunas:
            break
    
    if len(selecionados) < num_colunas:
        return None
    
    # Ordenar da esquerda para direita
    selecionados.sort(key=lambda c: c['bbox'][0])
    
    return [c['bbox'] for c in selecionados[:num_colunas]]


# ============================================================================
#  VALIDAÇÃO E UTILIDADES
# ============================================================================

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

    y_coords = np.array([b['y'] for b in bolhas])
    x_coords = np.array([b['x'] for b in bolhas])
    raios = np.array([b['radius'] for b in bolhas])

    y_mean = np.mean(y_coords)
    y_std = np.std(y_coords)
    raio_medio = np.mean(raios)

    if y_std > raio_medio * 0.05:
        return False, 0.3, f"Desalinhamento vertical: {y_std:.1f}px (esperado < {raio_medio * 0.05:.1f}px)"

    x_sorted = np.sort(x_coords)
    espacos = np.diff(x_sorted)

    if len(espacos) > 0:
        media_espacos = np.mean(espacos)
        if media_espacos > 0:
            cv_espacos = np.std(espacos) / media_espacos
        else:
            cv_espacos = float('inf')

        if cv_espacos > 0.15:
            return False, 0.4, f"Espaçamento irregular: CV={cv_espacos:.2f} (esperado < 0.15)"
    else:
        cv_espacos = 0

    try:
        z_scores = np.abs(stats.zscore(x_coords))
        if np.any(z_scores > 2.5):
            outliers = np.where(z_scores > 2.5)[0]
            return False, 0.5, f"Outliers detectados em índices: {outliers.tolist()}"
    except:
        pass

    if len(espacos) > 0:
        largura_total = x_sorted[-1] - x_sorted[0]
        espaco_esperado = largura_total / (num_alternativas - 1)
        desvios = np.abs(espacos - espaco_esperado)
        desvio_max = np.max(desvios)

        if desvio_max > raio_medio:
            return False, 0.6, f"Desvio de espaçamento: {desvio_max:.1f}px (esperado < {raio_medio:.1f}px)"
    else:
        desvio_max = 0

    penalty_alignment = min(y_std / (raio_medio * 0.05), 1.0) if raio_medio > 0 else 0
    penalty_spacing = min(cv_espacos / 0.15, 1.0)
    penalty_deviation = min(desvio_max / raio_medio, 1.0) if raio_medio > 0 else 0

    quality_score = max(0.0, 1.0 - (penalty_alignment + penalty_spacing + penalty_deviation) / 3)

    return True, quality_score, "OK"


def calcular_resposta_por_intensidade_relativa(bolhas_da_linha, binary=None, alternativas=None):
    """
    Decide qual bolha está marcada por comparação relativa de intensidade intra-linha.

    Filosofia: em vez de comparar cada bolha com um threshold absoluto global,
    normaliza as intensidades das 5 bolhas pelo máximo local da própria linha.
    Isso elimina o efeito de sombras ou iluminação desuniforme que afeta todas
    as bolhas da questão igualmente — a bolha mais escura/preenchida relativa
    às outras é a marcada, independente do valor absoluto.

    ✅ FIX C1 - VALIDAÇÃO DE ORDEM:
    As bolhas podem não estar em ordem (A,B,C,D,E) após detecção.
    Reordenar por coordenada X antes de mapear para índices.

    Pipeline:
    1. [FIX C1] Ordenar bolhas por X (esquerda→direita = A→E)
    2. Para cada bolha, obter intensidade (da binary ou do fill_rate já calculado)
    3. Normalizar pelo máximo local: intensity / max_of_row
    4. A bolha com maior valor normalizado é a marcada
    5. Score de separação = (max_norm - second_max_norm)
       Como max_norm == 1.0 após normalização: score = 1.0 - second_max_norm
       = (max_fill - second_max_fill) / max_fill  ∈ [0, 1]
    6. Score < 0.15 → candidatos muito próximos → sinalizar baixa confiança

    Args:
        bolhas_da_linha: Lista de dicts de bolhas de uma questão (máx 5)
        binary:          Imagem binária para re-extrair intensidade (opcional).
                         Se None, usa 'fill_rate' já armazenado em cada bolha.
        alternativas:    Lista de letras ['A','B','C','D','E']

    Returns:
        (letra_marcada, score_separacao)
        - letra_marcada:   str ('A'-'E') ou None se lista vazia / todas zero
        - score_separacao: float em [0, 1]; baixo (<0.15) = alta ambiguidade
    """
    if alternativas is None:
        alternativas = ['A', 'B', 'C', 'D', 'E']

    if not bolhas_da_linha:
        return None, 0.0

    # ✅ FIX C1: Reordenar bolhas por coordenada X (esquerda→direita)
    # Isso garante que índice 0→A, 1→B, 2→C, 3→D, 4→E
    bolhas_ordenadas = sorted(bolhas_da_linha, key=lambda b: b.get('x', 0))

    # Verificar se estava desordenada (diagnóstico)
    xs_original = [b.get('x', 0) for b in bolhas_da_linha]
    xs_ordenadas = [b.get('x', 0) for b in bolhas_ordenadas]
    if xs_original != xs_ordenadas:
        print(f"  🔄 [FIX C1] Bolhas reordenadas por X: {xs_original} → {xs_ordenadas}")

    intensidades = []
    for bolha in bolhas_ordenadas:
        # Bolhas sintéticas (completadas artificialmente) não contribuem
        if bolha.get('sintetica', False):
            intensidades.append(0.0)
            continue

        if binary is not None:
            # Re-extrair intensidade diretamente da imagem binária: mais preciso
            # pois evita re-uso do fill_rate calculado com outro threshold
            cx = bolha.get('x', 0)
            cy = bolha.get('y', 0)
            if 'centro' in bolha:
                cx, cy = bolha['centro']
            r = bolha.get('radius', 10)
            inner_r = max(1, int(r * 0.75))

            h_img, w_img = binary.shape
            if cx - inner_r < 0 or cy - inner_r < 0 or cx + inner_r >= w_img or cy + inner_r >= h_img:
                # Fora dos limites: usar fill_rate como fallback
                intensidades.append(float(bolha.get('fill_rate', 0.0)))
                continue

            mask = np.zeros_like(binary)
            cv2.circle(mask, (int(cx), int(cy)), inner_r, 255, -1)
            roi = cv2.bitwise_and(binary, mask)
            inner_area = np.pi * inner_r * inner_r
            filled_pixels = cv2.countNonZero(roi)
            intensidade = filled_pixels / inner_area if inner_area > 0 else 0.0
        else:
            # Usar fill_rate pré-calculado por detectar_bolhas_avancado
            intensidade = float(bolha.get('fill_rate', 0.0))

        intensidades.append(intensidade)

    if not intensidades:
        return None, 0.0

    intensidades = np.array(intensidades, dtype=np.float64)

    # Normalização local: dividir pelo máximo da linha
    # Transforma o problema de threshold absoluto em comparação relativa:
    # sombra que escurece todas as bolhas igualmente → cancelada pela divisão
    max_intensidade = float(np.max(intensidades))

    if max_intensidade < 1e-6:
        # Todas as bolhas têm intensidade ~0: cartão em branco ou falha de leitura
        # Retornar None indicando que não há resposta detectável
        return None, 0.0

    intensidades_norm = intensidades / max_intensidade  # max vira 1.0

    # Índice da bolha com maior intensidade relativa
    idx_max = int(np.argmax(intensidades_norm))

    # Score de separação: quão clara é a dominância do máximo sobre o segundo
    # sorted descrescente → [1.0, second, ...]
    sorted_norm = np.sort(intensidades_norm)[::-1]
    second_norm = sorted_norm[1] if len(sorted_norm) > 1 else 0.0

    # score = max_norm - second_norm = 1.0 - second_norm (pois max_norm == 1.0)
    # Equivale a (max_fill - second_max_fill) / max_fill
    score_separacao = float(1.0 - second_norm)

    letra = alternativas[idx_max] if idx_max < len(alternativas) else None
    return letra, score_separacao


def analisar_gabarito(questoes, num_questoes, alternativas=['A', 'B', 'C', 'D', 'E'], binary=None, image=None):
    """
    Analisa as questões agrupadas para determinar respostas marcadas com análise estatística robusta.
    Usa análise avançada se binary estiver disponível.
    
    Args:
        questoes: Lista de listas de bolhas agrupadas por questão
        num_questoes: Número esperado de questões
        alternativas: Lista de alternativas possíveis
        binary: Imagem binária para análise avançada (opcional)
        image: Imagem original para intensidade (opcional)
    
    Returns:
        resultados: Dicionário com resultados por questão
        confianca: Dicionário com níveis de confiança por questão
    """
    import numpy as np
    from analysis import analisar_preenchimento_avancado
    
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
        threshold_base = max(0.3, media_global + 0.5 * desvio_global)
    else:
        threshold_base = 0.3
    
    for i, questao in enumerate(questoes):
        num_questao = i + 1
        
        if num_questao > num_questoes:
            break
            
        if not questao:
            continue
            
        max_preenchimento = 0.0
        alt_index = -1
        second_max = 0.0
        preenchimentos = []
        
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
        
        if preenchimentos:
            media_questao = np.mean(preenchimentos)
            desvio_questao = np.std(preenchimentos)
            
            if desvio_questao > 0.1 and max_preenchimento > 0.4:
                threshold = media_questao + 0.8 * desvio_questao
            else:
                threshold = max(threshold_base, media_questao + 1.0 * desvio_questao)
            
            if second_max > 0:
                diferenca_norm = (max_preenchimento - second_max) / max(max_preenchimento, 0.1)
                nivel_confianca = min(1.0, diferenca_norm * 2)
            else:
                nivel_confianca = 1.0 if max_preenchimento > threshold else 0.0
            
            nivel_confianca = min(max(nivel_confianca, 0.0), 1.0)
            
            # --- SE BINARY, REAVALIAR COM ANÁLISE AVANÇADA PARA AMBIGUIDADES ---
            usou_avancado = False
            if binary is not None and (nivel_confianca < 0.6 or max_preenchimento < threshold * 1.2 or second_max > threshold * 0.8):
                # Ambíguo ou baixa confiança -> acionar Advanced Score para todas as bolhas > 0.10
                scores_avancados = []
                for j, bolha in enumerate(questao):
                    if j >= len(alternativas):
                        break
                    if 'sintetica' in bolha and bolha['sintetica']:
                        continue
                    
                    if bolha.get('fill_rate', 0) > 0.10:
                        resultado_avancado = analisar_preenchimento_avancado(binary, image, bolha)
                        scores_avancados.append((j, resultado_avancado['score'], resultado_avancado['confianca']))
                
                if scores_avancados:
                    scores_avancados.sort(key=lambda x: x[1], reverse=True)
                    melhor_score_avancado = scores_avancados[0]
                    alt_idx_avanc = melhor_score_avancado[0]
                    score_val = melhor_score_avancado[1]
                    conf_val = melhor_score_avancado[2]
                    
                    if score_val > 0.45: # Ponto de corte do analisar_preenchimento_avancado para 'marcada'
                        usou_avancado = True
                        alt_index = alt_idx_avanc
                        nivel_confianca = conf_val
                        max_preenchimento = score_val
                        threshold = 0.45 # Update threshold para logging
            
            if (usou_avancado and max_preenchimento > threshold) or (not usou_avancado and alt_index >= 0 and max_preenchimento > threshold):
                resultados[num_questao] = alternativas[alt_index]
                confianca[num_questao] = nivel_confianca
                if len(preenchimentos) > 1:
                    taxa_formatada = [f"{p:.2f}" for p in preenchimentos]
                    print(f"Q{num_questao}: Alternativa {alternativas[alt_index]} (preench. {max_preenchimento:.2f}, conf. {nivel_confianca:.2f}, threshold {threshold:.2f})")
                    print(f"   Preenchimentos: {taxa_formatada}")
            else:
                print(f"Q{num_questao}: Nenhuma alternativa atinge o threshold ({threshold:.2f}). Maior: {max_preenchimento:.2f}")

    # Terceiro retorno vazio para compatibilidade com a versão de analysis.py
    return resultados, confianca, []


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
        esperado_por_alternativa = total_respostas / num_alternativas
        
        for alt, count in contagem.items():
            if count > esperado_por_alternativa * 2.0 and count > 3:
                print(f"Aviso: Alternativa '{alt}' aparece {count} vezes (esperado ~{esperado_por_alternativa:.1f})")
                
                for q in range(1, num_questoes + 1):
                    if resultados[q] == alt and confianca[q] < 0.4:
                        resultados_corrigidos[q] = f"{alt}?"
    
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
    image = cv2.imread(imagem_path)
    if image is None:
        raise ValueError(f"Não foi possível carregar a imagem: {imagem_path}")
    
    binary, normalized = melhorar_pre_processamento(image)
    
    corrected_image, corrected_binary, success = corrigir_perspectiva(image, binary)
    if success:
        image = corrected_image
        binary = corrected_binary
    
    debug_image = image.copy()
    
    bolhas, debug_image = detectar_bolhas_avancado(binary, debug_image, threshold, sensitivity)
    
    questoes = agrupar_bolhas_por_questoes(bolhas, num_questoes, num_alternativas)
    
    alternativas = ['A', 'B', 'C', 'D', 'E'][:num_alternativas]
    resultados, confianca, _ = analisar_gabarito(questoes, num_questoes, alternativas)
    
    resultados_validados = validar_resultados(resultados, confianca, num_questoes, num_alternativas)
    
    return resultados_validados, debug_image


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
    bolhas, debug_image = detectar_bolhas_avancado(binary, debug_image, sensitivity=sensitivity)
    
    questoes_por_coluna = num_questoes // num_colunas
    resultados = {}
    
    if bolhas:
        questoes = agrupar_bolhas_por_questoes(bolhas, num_questoes, 5)
        
        for col in range(num_colunas):
            inicio = col * questoes_por_coluna
            fim = min((col + 1) * questoes_por_coluna, len(questoes))
            
            resultados_coluna, confianca, _ = analisar_gabarito(
                questoes[inicio:fim],
                questoes_por_coluna,
                ['A', 'B', 'C', 'D', 'E']
            )
            
            for q, resposta in resultados_coluna.items():
                num_questao = q + col * questoes_por_coluna
                resultados[num_questao] = resposta
    
    for q in range(1, num_questoes + 1):
        if q not in resultados:
            resultados[q] = None
    
    return resultados
