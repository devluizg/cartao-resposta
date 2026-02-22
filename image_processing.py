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

    # 2. FLASH VIRTUAL — aplicado SEMPRE (idempotente)
    flash = aplicar_flash_virtual(l_norm)
    
    if has_shadow:
        print(f"  ⚡ Flash virtual aplicado (sombra detectada: quad={quad_range:.0f}, grid={grid_range:.0f})")
    
    # 3. CLAHE — Adaptativo para contraste baixo (baseline estável)
    # FIX B1+B2: Se contraste < 45 (imagem "lavada"), usar CLAHE agressivo
    if contrast < 45:
        clahe_limit, clahe_grid = 3.5, (10, 10)  # Mais agressivo
        print(f"  🔧 CLAHE AGRESSIVO (contraste={contrast:.0f}): clip={clahe_limit}, grid={clahe_grid}")
    else:
        clahe_limit, clahe_grid = 2.0, (8, 8)

    clahe = cv2.createCLAHE(clipLimit=clahe_limit, tileGridSize=clahe_grid)
    enhanced = clahe.apply(flash)
    
    # 4. Suavização leve
    filtered = cv2.GaussianBlur(enhanced, (3, 3), 0)
    
    # 5. Binarização — Otsu funciona perfeitamente com flash virtual
    # porque a distribuição bimodal (papel branco vs tinta preta) fica clara
    _, binary_otsu = cv2.threshold(filtered, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    
    # 6. Threshold adaptativo como complemento (captura detalhes finos)
    binary_adaptive = cv2.adaptiveThreshold(
        filtered, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV, 21, 8
    )
    
    # 7. Combinar: OR para não perder nenhuma bolha
    binary = cv2.bitwise_or(binary_otsu, binary_adaptive)
    
    # 8. Filtro de ruído: só manter pixels em regiões escuras
    _, mask_dark = cv2.threshold(filtered, 200, 255, cv2.THRESH_BINARY)
    mask_dark = cv2.bitwise_not(mask_dark)
    kernel_dilate = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask_dark = cv2.dilate(mask_dark, kernel_dilate)
    binary = cv2.bitwise_and(binary, mask_dark)
    
    # 9. Limpeza morfológica
    kernel_open = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    kernel_close = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel_open)
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel_close)

    print(f"Pré-processamento: brightness={brightness:.0f}, contrast={contrast:.0f}, "
          f"shadow={'YES' if has_shadow else 'NO'} (quad={quad_range:.0f}, grid={grid_range:.0f}), "
          f"profile={metadata['illumination_profile']}")

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

    inv = cv2.bitwise_not(binary)
    blurred = cv2.GaussianBlur(inv, (5, 5), 0)

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
            # MUDANÇA: Relaxar circularidade de 0.55 para 0.45
            if circularidade < 0.45:
                continue

            # NOVO: Verificar solidez
            hull = cv2.convexHull(cnt)
            hull_area = cv2.contourArea(hull)
            solidity = area / hull_area if hull_area > 0 else 0
            if solidity < 0.7:
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
    
    # CLAHE leve
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
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
    """
    h, w = binary.shape
    pixels_por_mm = min(w, h) / 100.0
    return max(pixels_por_mm, 1.0)


def _criar_template_bolha(raio_px):
    """Cria um template circular para template matching (usa cache)."""
    return _criar_template_bolha_cached(raio_px)


def _detectar_hough_adaptativo(binary, min_radius, max_radius):
    """Detecta círculos usando HoughCircles com parâmetros adaptativos."""
    img_for_circles = 255 - binary.copy()
    img_for_circles = cv2.GaussianBlur(img_for_circles, (5, 5), 0)

    circles = cv2.HoughCircles(
        img_for_circles,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=max(min_radius * 1.0, 10),
        param1=40,
        param2=18,
        minRadius=int(min_radius * 0.7),
        maxRadius=int(max_radius * 1.3)
    )

    if circles is not None:
        return np.uint16(np.around(circles[0]))
    return np.array([])


def _detectar_template_matching(binary, raio_px):
    """Detecta círculos usando template matching com NMS."""
    template = _criar_template_bolha(raio_px)

    if template.shape[0] > binary.shape[0] or template.shape[1] > binary.shape[1]:
        return np.array([])

    result = cv2.matchTemplate(binary, template, cv2.TM_CCOEFF_NORMED)
    threshold_template = 0.45

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


def _detectar_contornos_com_features(binary, min_radius, max_radius):
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
        if circularity < 0.70:
            continue

        M = cv2.moments(cnt)
        if M["m00"] != 0:
            cx = int(M["m10"] / M["m00"])
            cy = int(M["m01"] / M["m00"])

            radius = int(np.sqrt(area / np.pi))
            if min_radius * 0.7 <= radius <= max_radius * 1.3:
                circles.append([cx, cy, radius])

    return np.array(circles)


def _aplicar_voting_system(circle_lists, threshold_distancia):
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
    if len(bolhas_finais) < 10 and total_detections > len(bolhas_finais) * 2:
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

    return np.array(bolhas_finais) if bolhas_finais else np.array([])


def detectar_bolhas_avancado(binary, debug_image=None, threshold=100, sensitivity=0.5, quality_meta=None):
    """
    Detecta bolhas em um cartão resposta com método híbrido (4 detectores + voting system).

    Args:
        binary: Imagem binária pré-processada
        debug_image: Imagem para desenhar informações de debug (opcional)
        threshold: Valor de limiar para detecção de marcação (0-255)
        sensitivity: Sensibilidade para considerar uma bolha preenchida (0.0-1.0)
        quality_meta: Metadados de qualidade opcionais para diagnóstico

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

    raio_esperado_mm = 3
    raio_px = int(raio_esperado_mm * escala)
    min_radius = max(int(raio_px * 0.6), 4)
    max_radius = int(raio_px * 1.4)

    # Método 1: HoughCircles Adaptativo
    circles_hough = _detectar_hough_adaptativo(binary, min_radius, max_radius)

    # Método 2: Template Matching
    circles_template = _detectar_template_matching(binary, raio_px)

    # Método 3: MSER + Circularidade
    circles_mser = _detectar_mser(binary, min_radius, max_radius)

    # Método 4: Contornos com features
    circles_contour = _detectar_contornos_com_features(binary, min_radius, max_radius)

    # Voting System com concordância de 2+ métodos
    circle_lists = [circles_hough, circles_template, circles_mser, circles_contour]
    bolhas_votadas = _aplicar_voting_system(circle_lists, raio_px * 1.0)

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
    eps_base = max(raio_medio_bolhas * 1.5, 8.0)

    # **PILAR 3: DBSCAN ITERATIVO** — Tenta múltiplos eps até encontrar esperado
    labels = None
    eps_used = None

    for eps_factor in [0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.80, 0.90, 1.0]:
        eps_teste = eps_base * eps_factor
        db_teste = DBSCAN(eps=eps_teste, min_samples=1).fit(y_only)
        linhas_teste = len(set(db_teste.labels_[db_teste.labels_ != -1]))

        # Sucesso se encontra número esperado (com tolerância de ±1)
        if abs(linhas_teste - num_questoes) <= 1:
            labels = db_teste.labels_
            eps_used = eps_teste
            print(f"DBSCAN: {linhas_teste} linhas detectadas (esperado {num_questoes}). "
                  f"Usando DBSCAN com eps_factor={eps_factor:.2f}.")
            break

    # Se DBSCAN não convergiu, usar KMeans como último recurso
    if labels is None:
        db_linhas = DBSCAN(eps=eps_base, min_samples=1).fit(y_only)
        linhas_naturais = len(set(db_linhas.labels_[db_linhas.labels_ != -1]))
        print(f"Aviso: DBSCAN não convergiu mesmo com eps iterativo. "
              f"Detectadas {linhas_naturais} linhas, usando KMeans({num_questoes}).")
        try:
            kmeans = KMeans(n_clusters=num_questoes, random_state=42, n_init=10)
            labels = kmeans.fit_predict(y_only)
        except Exception:
            labels = db_linhas.labels_
    
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
        
        # Retângulo de coluna deve ter área entre 3% e 50% da imagem
        area_ratio = area / (h_img * w_img)
        if area_ratio < 0.03 or area_ratio > 0.50:
            continue
        
        # Aproximar polígono
        peri = cv2.arcLength(cnt, True)
        if peri == 0:
            continue
        approx = cv2.approxPolyDP(cnt, 0.02 * peri, True)
        
        # Deve ter 4 vértices (retângulo) ou próximo
        if len(approx) < 4 or len(approx) > 8:
            continue
        
        x, y, rw, rh = cv2.boundingRect(cnt)
        
        # Retângulo de coluna é robusto em altura
        if rh < h_img * 0.35:
            continue
        
        aspect = rh / rw if rw > 0 else 0
        
        # Verificar retangularidade (quanto da bounding box é preenchida)
        rect_area = rw * rh
        rectangularity = area / rect_area if rect_area > 0 else 0
        
        if rectangularity < 0.15:  # Muito pouco preenchimento = não é retângulo
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
    
    # Ordenar por área (maiores primeiro)
    candidatos.sort(key=lambda c: c['area'], reverse=True)
    
    # Filtrar candidatos que se sobrepõem
    selecionados = []
    for cand in candidatos:
        x1, y1, w1, h1 = cand['bbox']
        cx1 = x1 + w1 // 2
        
        sobrepoe = False
        for sel in selecionados:
            x2, y2, w2, h2 = sel['bbox']
            cx2 = x2 + w2 // 2
            
            # Verificar sobreposição horizontal
            overlap_x = max(0, min(x1+w1, x2+w2) - max(x1, x2))
            if overlap_x > min(w1, w2) * 0.3:
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

        # ✅ FIX C1: Validar ordem de bolhas por X (esquerda→direita = A→E)
        # Se bolhas não estão em ordem X, reordenar antes de mapear para alternativas
        xs_original = [b.get('x', 0) for b in questao]
        questao_ordenada = sorted(questao, key=lambda b: b.get('x', 0))
        xs_ordenada = [b.get('x', 0) for b in questao_ordenada]

        if xs_original != xs_ordenada:
            print(f"  🔄 [FIX C1] Q{num_questao}: Bolhas reordenadas por X")
            questao = questao_ordenada  # Usar versão ordenada

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
    resultados, confianca = analisar_gabarito(questoes, num_questoes, alternativas)
    
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
            
            resultados_coluna, confianca = analisar_gabarito(
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