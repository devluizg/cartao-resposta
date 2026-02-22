#!/usr/bin/env python3
"""
metricas_acuracia.py
Pontuação final e geração de relatório anotado para OMR.

Combina respostas detectadas (OpenCV + fallback Claude Vision)
com o gabarito oficial para calcular nota, acertos, erros e gerar
imagem anotada com indicadores visuais.

Saída:
  /tmp/resultado_final.json    — Resultado completo em JSON
  /tmp/omr_resultado_anotado.png — Imagem com anotações visuais (se disponível)
"""

import argparse
import json
import os
import sys
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)

try:
    import cv2
    import numpy as np
    CV_DISPONIVEL = True
except ImportError:
    CV_DISPONIVEL = False


def _carregar_json(caminho: str) -> dict:
    with open(caminho, encoding="utf-8") as f:
        return json.load(f)


def _mesclar_respostas(respostas_opencv: dict, resolucoes_claude: dict) -> dict:
    """
    Mescla respostas do OpenCV com resoluções do Claude Vision.
    Claude tem prioridade para questões marcadas como AMBIGUA.
    """
    respostas_finais = dict(respostas_opencv)
    for questao, resposta in resolucoes_claude.items():
        chave = str(questao)
        if respostas_finais.get(chave) == "AMBIGUA" or chave not in respostas_finais:
            if resposta != "IMPOSSIVEL_DETERMINAR":
                respostas_finais[chave] = resposta
            else:
                respostas_finais[chave] = "EM_BRANCO"
    return respostas_finais


def calcular_pontuacao(respostas: dict, gabarito: dict, config_pontuacao: dict) -> dict:
    """
    Calcula acertos, erros, em branco e nota final.
    Suporta penalidade por erro e pontuação customizada.
    """
    pontos_acerto = config_pontuacao.get("pontos_acerto", 1.0)
    pontos_erro = config_pontuacao.get("pontos_erro", 0.0)
    pontos_branco = config_pontuacao.get("pontos_branco", 0.0)
    nota_maxima = config_pontuacao.get("nota_maxima", 10.0)

    acertos = 0
    erros = 0
    em_branco = 0
    impossivel = 0
    detalhes = []

    for questao_str, gabarito_resp in gabarito.items():
        resposta_aluno = respostas.get(str(questao_str), "EM_BRANCO")

        if resposta_aluno == "EM_BRANCO":
            situacao = "em_branco"
            em_branco += 1
            pontos_obtidos = pontos_branco
        elif resposta_aluno == "AMBIGUA":
            situacao = "ambigua_nao_resolvida"
            impossivel += 1
            pontos_obtidos = pontos_branco
        elif resposta_aluno.upper() == gabarito_resp.upper():
            situacao = "acerto"
            acertos += 1
            pontos_obtidos = pontos_acerto
        else:
            situacao = "erro"
            erros += 1
            pontos_obtidos = pontos_erro

        detalhes.append({
            "questao": int(questao_str),
            "gabarito": gabarito_resp,
            "resposta_aluno": resposta_aluno,
            "situacao": situacao,
            "pontos": pontos_obtidos
        })

    total_questoes = len(gabarito)
    total_pontos = acertos * pontos_acerto + erros * pontos_erro + em_branco * pontos_branco
    nota = round((total_pontos / total_questoes) * nota_maxima, 2) if total_questoes > 0 else 0.0
    percentual = round((acertos / total_questoes) * 100, 1) if total_questoes > 0 else 0.0

    return {
        "acertos": acertos,
        "erros": erros,
        "em_branco": em_branco,
        "impossivel_determinar": impossivel,
        "total_questoes": total_questoes,
        "nota": nota,
        "nota_maxima": nota_maxima,
        "percentual_acerto": percentual,
        "detalhes_por_questao": sorted(detalhes, key=lambda x: x["questao"])
    }


def anotar_imagem(input_path: str, output_path: str, detalhes: list) -> bool:
    """
    Gera imagem anotada com marcadores visuais de acerto/erro.
    Verde = acerto, Vermelho = erro, Amarelo = em branco/ambíguo.
    (Requer imagem do gabarito bird's-eye view processado)
    """
    if not CV_DISPONIVEL:
        log.warning("OpenCV não disponível — imagem anotada não será gerada.")
        return False

    if not os.path.exists(input_path):
        log.warning(f"Imagem de entrada não encontrada: {input_path}")
        return False

    imagem = cv2.imread(input_path)
    if imagem is None:
        return False

    h, w = imagem.shape[:2]

    # Painel de resumo no topo
    cv2.rectangle(imagem, (0, 0), (w, 60), (30, 30, 30), -1)

    acertos = sum(1 for d in detalhes if d["situacao"] == "acerto")
    erros = sum(1 for d in detalhes if d["situacao"] == "erro")
    total = len(detalhes)
    pct = round(acertos / total * 100, 1) if total > 0 else 0.0

    texto = f"Acertos: {acertos}/{total} ({pct}%)  |  Erros: {erros}"
    cv2.putText(imagem, texto, (10, 40), cv2.FONT_HERSHEY_SIMPLEX,
                0.8, (255, 255, 255), 2)

    # Anotações por questão (simplificado — posição estimada por linha)
    margem_topo = 80
    altura_linha = max(10, (h - margem_topo) // max(total, 1))
    for i, detalhe in enumerate(detalhes):
        y = margem_topo + i * altura_linha + altura_linha // 2
        if y > h - 10:
            break

        cor = (0, 200, 0) if detalhe["situacao"] == "acerto" else \
              (0, 0, 220) if detalhe["situacao"] == "erro" else \
              (0, 200, 200)

        label = f"Q{detalhe['questao']}: {detalhe['resposta_aluno']} (G:{detalhe['gabarito']})"
        cv2.putText(imagem, label, (10, y), cv2.FONT_HERSHEY_SIMPLEX,
                    0.4, cor, 1)

    cv2.imwrite(output_path, imagem)
    return True


def main():
    parser = argparse.ArgumentParser(description="Métricas e relatório final OMR")
    parser.add_argument("--respostas", required=True,
                        help="JSON de respostas classificadas (output do modo classificar)")
    parser.add_argument("--gabarito", required=True,
                        help="JSON com gabarito oficial")
    parser.add_argument("--resolucoes-claude", default=None,
                        help="JSON de resoluções do fallback Claude (opcional)")
    parser.add_argument("--imagem-anotada", default=None,
                        help="Caminho da imagem processada para anotar")
    parser.add_argument("--output-json", default="/tmp/resultado_final.json")
    parser.add_argument("--output-imagem", default="/tmp/omr_resultado_anotado.png")
    parser.add_argument("--aluno-id", default="desconhecido")
    args = parser.parse_args()

    # Carrega respostas
    dados_respostas = _carregar_json(args.respostas)
    respostas_opencv = dados_respostas.get("respostas_detectadas", {})
    questoes_ambiguas = dados_respostas.get("questoes_ambiguas", [])
    confianca_opencv = dados_respostas.get("confianca_media", 0.0)

    # Carrega e mescla resoluções Claude (se existir)
    resolucoes_claude = {}
    if args.resolucoes_claude and os.path.exists(args.resolucoes_claude):
        dados_claude = _carregar_json(args.resolucoes_claude)
        resolucoes_claude = dados_claude.get("resolucoes", {})

    respostas_finais = _mesclar_respostas(respostas_opencv, resolucoes_claude)

    # Carrega gabarito
    gabarito_raw = _carregar_json(args.gabarito)
    gabarito = {str(k): v for k, v in gabarito_raw.get("gabarito", {}).items()}

    config_pontuacao = gabarito_raw.get("config_pontuacao", {})

    # Calcula pontuação
    pontuacao = calcular_pontuacao(respostas_finais, gabarito, config_pontuacao)

    # Determina método de processamento
    metodo = "opencv"
    if resolucoes_claude:
        metodo = "opencv+claude_vision_fallback"
    elif not respostas_opencv and questoes_ambiguas:
        metodo = "claude_vision_completo"

    # Alertas
    alertas = []
    nao_resolvidas = [d for d in pontuacao["detalhes_por_questao"]
                      if d["situacao"] == "ambigua_nao_resolvida"]
    if nao_resolvidas:
        qs = [str(d["questao"]) for d in nao_resolvidas]
        alertas.append(f"Questões impossíveis de determinar (contadas como em branco): {', '.join(qs)}")

    # Monta resultado final
    resultado_final = {
        "aluno_id": args.aluno_id,
        **pontuacao,
        "metodo_processamento": metodo,
        "confianca_opencv": confianca_opencv,
        "confianca_claude": _carregar_json(args.resolucoes_claude).get("confianca", None)
                            if args.resolucoes_claude and os.path.exists(args.resolucoes_claude) else None,
        "alertas": alertas
    }

    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(resultado_final, f, ensure_ascii=False, indent=2)
    log.info(f"Resultado salvo em: {args.output_json}")

    # Anotação visual
    imagem_entrada = args.imagem_anotada or "/tmp/omr_warped.png"
    anotar_imagem(imagem_entrada, args.output_imagem, pontuacao["detalhes_por_questao"])

    # Imprime resumo
    print(json.dumps(resultado_final, ensure_ascii=False, indent=2))
    sys.exit(0)


if __name__ == "__main__":
    main()
