#!/usr/bin/env python3
"""
processamento_imagem.py
Pipeline OpenCV determinístico para OMR (Optical Mark Recognition).

Modos de execução:
  (padrão)         Pré-processa a imagem (redimensiona, normaliza iluminação)
  detectar_documento  Detecta contorno da folha de respostas
  perspectiva      Aplica transformação de perspectiva (bird's-eye view)
  detectar_bolhas  Detecta e classifica bolhas preenchidas
  classificar      Combina resultado de bolhas com gabarito

Saída: JSON impresso em stdout + arquivo de imagem opcional.
"""

import argparse
import json
import sys
import os
import logging
import numpy as np

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)

# ─── Tentativa de importar OpenCV ───────────────────────────────────────────

try:
    import cv2
    import imutils
    from imutils.perspective import four_point_transform
    from imutils import contours as imutils_contours
    CV_DISPONIVEL = True
except ImportError:
    CV_DISPONIVEL = False
    log.warning("OpenCV/imutils não instalado. Instale com: pip install opencv-python-headless imutils")


# ═══════════════════════════════════════════════════════════════════════════
# FUNÇÕES AUXILIARES
# ═══════════════════════════════════════════════════════════════════════════

def _erro(mensagem: str) -> dict:
    return {"status": "erro", "mensagem": mensagem}


def _ok(dados: dict) -> dict:
    return {"status": "ok", **dados}


def _salvar_imagem(imagem, caminho: str) -> bool:
    if not CV_DISPONIVEL or imagem is None:
        return False
    try:
        cv2.imwrite(caminho, imagem)
        return True
    except Exception as e:
        log.error(f"Falha ao salvar imagem em {caminho}: {e}")
        return False


def _carregar_config(caminho_config: str) -> dict:
    """Carrega configurações de normalização do arquivo JSON."""
    defaults = {
        "resize_max_dim": 800,
        "gaussian_blur_kernel": 5,
        "clahe_clip_limit": 2.0,
        "clahe_tile_grid": 8,
        "canny_threshold1": 75,
        "canny_threshold2": 200,
        "min_bubble_width": 20,
        "min_bubble_height": 20,
        "aspect_ratio_tolerance": 0.1,
        "fill_threshold_pct": 0.50
    }
    if caminho_config and os.path.exists(caminho_config):
        with open(caminho_config) as f:
            overrides = json.load(f)
        defaults.update(overrides)
    return defaults


# ═══════════════════════════════════════════════════════════════════════════
# MODO: PRÉ-PROCESSAMENTO
# ═══════════════════════════════════════════════════════════════════════════

def preprocessar(input_path: str, output_path: str, config: dict) -> dict:
    """
    1. Redimensiona mantendo aspect ratio
    2. Converte para escala de cinza
    3. Avalia uniformidade de iluminação (desvio padrão do blur)
    4. Aplica CLAHE se necessário
    5. Aplica Gaussian Blur
    """
    if not CV_DISPONIVEL:
        return _erro("OpenCV não disponível. Instale opencv-python-headless.")

    imagem = cv2.imread(input_path)
    if imagem is None:
        return _erro(f"Não foi possível carregar a imagem: {input_path}")

    h_orig, w_orig = imagem.shape[:2]

    # Redimensiona
    max_dim = config["resize_max_dim"]
    scale = min(max_dim / h_orig, max_dim / w_orig, 1.0)
    nova_h, nova_w = int(h_orig * scale), int(w_orig * scale)
    imagem = cv2.resize(imagem, (nova_w, nova_h))

    # Cinza
    cinza = cv2.cvtColor(imagem, cv2.COLOR_BGR2GRAY)

    # Avaliação de iluminação (CLAHE se desvio padrão do laplaciano for baixo)
    blur_score = cv2.Laplacian(cinza, cv2.CV_64F).var()
    iluminacao_uniforme = True

    # Verifica gradiente de brilho por regiões
    h, w = cinza.shape
    regioes = [
        cinza[0:h//2, 0:w//2].mean(),
        cinza[0:h//2, w//2:].mean(),
        cinza[h//2:, 0:w//2].mean(),
        cinza[h//2:, w//2:].mean(),
    ]
    variacao_iluminacao = max(regioes) - min(regioes)
    if variacao_iluminacao > 40:
        iluminacao_uniforme = False
        log.info(f"Iluminação não uniforme (variação={variacao_iluminacao:.1f}). Aplicando CLAHE.")
        clahe = cv2.createCLAHE(
            clipLimit=config["clahe_clip_limit"],
            tileGridSize=(config["clahe_tile_grid"], config["clahe_tile_grid"])
        )
        cinza = clahe.apply(cinza)

    # Gaussian Blur para redução de ruído
    kernel = config["gaussian_blur_kernel"]
    blurred = cv2.GaussianBlur(cinza, (kernel, kernel), 0)

    # Salva imagem processada (BGR para compatibilidade com etapas seguintes)
    imagem_saida = cv2.cvtColor(blurred, cv2.COLOR_GRAY2BGR)
    _salvar_imagem(imagem_saida, output_path)

    nivel_contraste = round(blur_score / 1000.0, 3)
    return _ok({
        "resolucao_original": [h_orig, w_orig],
        "resolucao_processada": [nova_h, nova_w],
        "nivel_contraste": nivel_contraste,
        "iluminacao_uniforme": iluminacao_uniforme,
        "arquivo_saida": output_path
    })


# ═══════════════════════════════════════════════════════════════════════════
# MODO: DETECTAR DOCUMENTO
# ═══════════════════════════════════════════════════════════════════════════

def detectar_documento(input_path: str, output_path: str, config: dict) -> dict:
    """
    Usa detecção de bordas Canny + findContours para localizar a folha de respostas.
    Retorna os 4 pontos de canto do contorno retangular mais provável.
    """
    if not CV_DISPONIVEL:
        return _erro("OpenCV não disponível.")

    imagem = cv2.imread(input_path)
    if imagem is None:
        return _erro(f"Imagem não encontrada: {input_path}")

    cinza = cv2.cvtColor(imagem, cv2.COLOR_BGR2GRAY)
    edged = cv2.Canny(cinza, config["canny_threshold1"], config["canny_threshold2"])

    cnts = cv2.findContours(edged.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cnts = imutils.grab_contours(cnts)

    if not cnts:
        return _erro("Nenhum contorno encontrado na imagem.")

    # Ordena por área (maior primeiro) e busca retângulo (4 vértices)
    cnts = sorted(cnts, key=cv2.contourArea, reverse=True)
    doc_cnts = None
    for c in cnts:
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.02 * peri, True)
        if len(approx) == 4:
            doc_cnts = approx
            break

    if doc_cnts is None:
        return _ok({
            "contorno_encontrado": False,
            "pontos_corner": [],
            "area_contorno": 0
        })

    area = cv2.contourArea(doc_cnts)
    total_area = imagem.shape[0] * imagem.shape[1]
    pontos = doc_cnts.reshape(4, 2).tolist()

    # Desenha contorno na imagem de saída
    cv2.drawContours(imagem, [doc_cnts], -1, (0, 255, 0), 2)
    _salvar_imagem(imagem, output_path)

    return _ok({
        "contorno_encontrado": True,
        "pontos_corner": pontos,
        "area_contorno": int(area),
        "proporcao_area": round(area / total_area, 3)
    })


# ═══════════════════════════════════════════════════════════════════════════
# MODO: PERSPECTIVA
# ═══════════════════════════════════════════════════════════════════════════

def aplicar_perspectiva(input_path: str, pontos_json: str, output_path: str) -> dict:
    """
    Aplica transformação de perspectiva usando os 4 pontos de canto.
    Produz visão bird's-eye da folha de respostas.
    """
    if not CV_DISPONIVEL:
        return _erro("OpenCV não disponível.")

    imagem = cv2.imread(input_path)
    if imagem is None:
        return _erro(f"Imagem não encontrada: {input_path}")

    try:
        pontos = np.array(json.loads(pontos_json), dtype="float32")
    except Exception as e:
        return _erro(f"Pontos de canto inválidos: {e}")

    try:
        warped = four_point_transform(imagem, pontos)
    except Exception as e:
        return _erro(f"Falha na transformação de perspectiva: {e}")

    h, w = warped.shape[:2]
    _salvar_imagem(warped, output_path)

    return _ok({
        "arquivo_saida": output_path,
        "dimensoes_finais": [h, w]
    })


# ═══════════════════════════════════════════════════════════════════════════
# MODO: DETECTAR BOLHAS
# ═══════════════════════════════════════════════════════════════════════════

def detectar_bolhas(input_path: str, output_path: str, output_json: str, config: dict) -> dict:
    """
    1. Binariza com Otsu's thresholding
    2. Encontra contornos circulares (aspect ratio ≈ 1.0)
    3. Para cada questão, identifica a bolha mais preenchida
    4. Detecta ambiguidades (zero ou múltiplas marcações)
    """
    if not CV_DISPONIVEL:
        return _erro("OpenCV não disponível.")

    imagem = cv2.imread(input_path)
    if imagem is None:
        return _erro(f"Imagem não encontrada: {input_path}")

    cinza = cv2.cvtColor(imagem, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(cinza, (5, 5), 0)
    _, thresh = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    cnts = cv2.findContours(thresh.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cnts = imutils.grab_contours(cnts)

    min_w = config["min_bubble_width"]
    min_h = config["min_bubble_height"]
    tol = config["aspect_ratio_tolerance"]

    question_cnts = []
    for c in cnts:
        x, y, w, h = cv2.boundingRect(c)
        aspect = w / float(h) if h > 0 else 0
        if w >= min_w and h >= min_h and abs(1.0 - aspect) <= tol:
            question_cnts.append(c)

    if not question_cnts:
        return _erro("Nenhuma bolha detectada. Verifique a qualidade da imagem.")

    # Ordena bolhas de cima para baixo
    question_cnts, _ = imutils_contours.sort_contours(question_cnts, method="top-to-bottom")

    # Número de alternativas por questão (assume 5: A B C D E)
    alternativas_por_questao = 5
    alternativas = ["A", "B", "C", "D", "E"]
    total_bolhas = len(question_cnts)
    num_questoes = total_bolhas // alternativas_por_questao

    bolhas = []
    bolhas_ambiguas = []
    fill_threshold = config["fill_threshold_pct"]

    for q in range(num_questoes):
        inicio = q * alternativas_por_questao
        grupo = question_cnts[inicio: inicio + alternativas_por_questao]
        grupo_ordenado, _ = imutils_contours.sort_contours(grupo, method="left-to-right")

        pixels_por_alternativa = []
        for c in grupo_ordenado:
            mask = np.zeros(thresh.shape, dtype="uint8")
            cv2.drawContours(mask, [c], -1, 255, -1)
            mask = cv2.bitwise_and(thresh, thresh, mask=mask)
            total_pixels = cv2.countNonZero(mask)
            pixels_por_alternativa.append(total_pixels)

        max_pixels = max(pixels_por_alternativa)
        area_bolha = cv2.contourArea(grupo_ordenado[0]) if grupo_ordenado else 100
        marcadas = [
            i for i, px in enumerate(pixels_por_alternativa)
            if px > fill_threshold * area_bolha and max_pixels > 0
        ]

        for j, (c, px) in enumerate(zip(grupo_ordenado, pixels_por_alternativa)):
            marcada = len(marcadas) == 1 and j in marcadas
            alt = alternativas[j] if j < len(alternativas) else str(j)
            bolhas.append({
                "questao": q + 1,
                "alternativa": alt,
                "pixels_preenchidos": int(px),
                "marcada": marcada
            })

        if len(marcadas) == 0:
            bolhas_ambiguas.append({
                "questao": q + 1,
                "motivo": "sem_marcacao",
                "candidatos": []
            })
        elif len(marcadas) > 1:
            cands = [alternativas[i] for i in marcadas if i < len(alternativas)]
            bolhas_ambiguas.append({
                "questao": q + 1,
                "motivo": "dois_preenchimentos",
                "candidatos": cands
            })

    resultado = {
        "total_bolhas": total_bolhas,
        "bolhas_por_questao": alternativas_por_questao,
        "num_questoes": num_questoes,
        "bolhas": bolhas,
        "bolhas_ambiguas": bolhas_ambiguas
    }

    # Salva JSON
    with open(output_json, "w", encoding="utf-8") as f:
        json.dump(resultado, f, ensure_ascii=False, indent=2)

    # Salva imagem anotada
    _salvar_imagem(imagem, output_path)

    return _ok(resultado)


# ═══════════════════════════════════════════════════════════════════════════
# MODO: CLASSIFICAR
# ═══════════════════════════════════════════════════════════════════════════

def classificar(input_json: str, gabarito_path: str, output_json: str) -> dict:
    """
    Combina resultado de detecção de bolhas com gabarito.
    Produz dicionário de respostas por questão.
    """
    with open(input_json, encoding="utf-8") as f:
        dados = json.load(f)

    gabarito = {}
    if gabarito_path and os.path.exists(gabarito_path):
        with open(gabarito_path, encoding="utf-8") as f:
            raw = json.load(f)
            gabarito = {str(k): v for k, v in raw.get("gabarito", {}).items()}

    respostas = {}
    questoes_ambiguas = [b["questao"] for b in dados.get("bolhas_ambiguas", [])]

    for b in dados["bolhas"]:
        q = str(b["questao"])
        if b["questao"] in questoes_ambiguas:
            respostas[q] = "AMBIGUA"
        elif b["marcada"]:
            respostas[q] = b["alternativa"]
        elif q not in respostas:
            respostas[q] = "EM_BRANCO"

    # Confiança: proporção de questões não-ambíguas
    total_q = dados["num_questoes"]
    conf = (total_q - len(questoes_ambiguas)) / total_q if total_q > 0 else 0.0

    resultado = {
        "respostas_detectadas": respostas,
        "questoes_ambiguas": questoes_ambiguas,
        "confianca_media": round(conf, 3)
    }

    with open(output_json, "w", encoding="utf-8") as f:
        json.dump(resultado, f, ensure_ascii=False, indent=2)

    return _ok(resultado)


# ═══════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="Pipeline OpenCV para OMR")
    parser.add_argument("--input", required=False)
    parser.add_argument("--output", default="/tmp/omr_output.png")
    parser.add_argument("--mode", default="preprocessar",
                        choices=["preprocessar", "detectar_documento", "perspectiva",
                                 "detectar_bolhas", "classificar"])
    parser.add_argument("--config", default=None)
    parser.add_argument("--pontos", default=None, help="JSON com pontos de canto para perspectiva")
    parser.add_argument("--output-json", default="/tmp/omr_output.json")
    parser.add_argument("--input-json", default=None, help="JSON de entrada para modo classificar")
    parser.add_argument("--gabarito", default=None)
    args = parser.parse_args()

    config = _carregar_config(args.config)

    if args.mode == "preprocessar":
        resultado = preprocessar(args.input, args.output, config)
    elif args.mode == "detectar_documento":
        resultado = detectar_documento(args.input, args.output, config)
    elif args.mode == "perspectiva":
        resultado = aplicar_perspectiva(args.input, args.pontos, args.output)
    elif args.mode == "detectar_bolhas":
        resultado = detectar_bolhas(args.input, args.output, args.output_json, config)
    elif args.mode == "classificar":
        resultado = classificar(args.input_json, args.gabarito, args.output_json)
    else:
        resultado = _erro(f"Modo desconhecido: {args.mode}")

    print(json.dumps(resultado, ensure_ascii=False, indent=2))
    sys.exit(0 if resultado.get("status") == "ok" else 1)


if __name__ == "__main__":
    main()
