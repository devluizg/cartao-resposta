#!/usr/bin/env python3
"""
Teste Automático - Executa sem interação.
Gabarito fixo, processa todas as imagens em test_unified/ e salva relatório JSON.

Uso:
    python3 teste_auto.py
    python3 teste_auto.py --pasta outra_pasta --colunas 2 --questoes 24
"""

import cv2
import json
import argparse
import os
from pathlib import Path
from datetime import datetime

from image_processing import (
    melhorar_pre_processamento_adaptativo,
    corrigir_perspectiva,
    redimensionar_imagem_otimizada,
)
from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer

# ─── GABARITO FIXO ────────────────────────────────────────────────────────────
GABARITO = list("DCCBCDEECCBCDCBCCCDEDCBA")
# ──────────────────────────────────────────────────────────────────────────────

NUM_QUESTOES = 24
NUM_COLUNAS  = 2
SENSITIVITY  = 0.10
PASTA        = "test_unified"


def processar_imagem(image_path: Path, num_questoes: int, num_colunas: int,
                     sensitivity: float) -> tuple:
    """Processa uma imagem e retorna dicionário de respostas detectadas."""
    image = cv2.imread(str(image_path))
    if image is None:
        return None, f"Não foi possível ler: {image_path}"

    image, _ = redimensionar_imagem_otimizada(image)
    binary, metadata = melhorar_pre_processamento_adaptativo(image)

    img_corr, bin_corr, ok = corrigir_perspectiva(image, binary)
    if ok:
        image, binary = img_corr, bin_corr

    analyzer = CartaoRespostaAnalyzer()
    multi    = MultiColumnCartaoAnalyzer(analyzer)
    debug    = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

    resultados = multi.analisar_cartao_multicolunas(
        image, binary, debug,
        num_questoes=num_questoes,
        num_colunas=num_colunas,
        sensitivity=sensitivity,
        threshold=150,
        return_debug_image=False,
    )
    return resultados, None


def formatar_gabarito(resultados: dict, num_questoes: int) -> list:
    """Converte dicionário de resultados em lista de letras."""
    saida = []
    for q in range(1, num_questoes + 1):
        r = resultados.get(q)
        if r is None:
            saida.append("-")
        elif "ERRO" in str(r):
            saida.append("X")
        else:
            # Remove '?' de confiança baixa para comparação limpa
            saida.append(str(r).replace("?", ""))
    return saida


def comparar(detectado: list, gabarito: list) -> dict:
    """Compara resposta detectada com o gabarito e retorna estatísticas."""
    acertos, erros, detalhes = 0, 0, []
    for q, (det, real) in enumerate(zip(detectado, gabarito), 1):
        if det == real:
            acertos += 1
        else:
            erros += 1
            detalhes.append({"questao": q, "detectado": det, "esperado": real})
    taxa = acertos / len(gabarito) * 100 if gabarito else 0
    return {"acertos": acertos, "erros": erros, "taxa": taxa, "detalhes": detalhes}


def obter_imagens(pasta: str) -> list:
    p = Path(pasta)
    if not p.exists():
        return []
    imgs = []
    for ext in ("*.jpg", "*.jpeg", "*.png", "*.JPG", "*.JPEG", "*.PNG"):
        imgs.extend(p.glob(ext))
    return sorted(imgs)


def imprimir_linha(label: str, detectado: list, gabarito: list, acertos: int):
    det_str = " ".join(f"{d:1}" for d in detectado)
    print(f"  Detectado : {det_str}")
    gab_str = " ".join(f"{g:1}" for g in gabarito)
    print(f"  Gabarito  : {gab_str}")
    print(f"  Acertos   : {acertos}/{len(gabarito)}  ({acertos/len(gabarito)*100:.1f}%)")


def main():
    parser = argparse.ArgumentParser(description="Teste automático de cartão-resposta")
    parser.add_argument("--pasta",    default=PASTA,        help="Pasta com imagens")
    parser.add_argument("--questoes", default=NUM_QUESTOES, type=int)
    parser.add_argument("--colunas",  default=NUM_COLUNAS,  type=int)
    parser.add_argument("--sens",     default=SENSITIVITY,  type=float,
                        help="Sensibilidade de detecção (padrão 0.10)")
    args = parser.parse_args()

    gabarito    = GABARITO[: args.questoes]
    imagens     = obter_imagens(args.pasta)

    print("\n" + "=" * 70)
    print("  TESTE AUTOMÁTICO — CARTÃO RESPOSTA")
    print("=" * 70)
    print(f"  Pasta      : {args.pasta}")
    print(f"  Questões   : {args.questoes}  |  Colunas: {args.colunas}  |  Sens: {args.sens}")
    print(f"  Gabarito   : {' '.join(gabarito)}")
    print(f"  Imagens    : {len(imagens)}")
    print("=" * 70 + "\n")

    if not imagens:
        print(f"❌ Nenhuma imagem encontrada em '{args.pasta}'")
        return

    resultados_finais = []
    total_acertos = 0

    for i, img_path in enumerate(imagens, 1):
        print(f"[{i}/{len(imagens)}] {img_path.name}")
        res, erro = processar_imagem(img_path, args.questoes, args.colunas, args.sens)

        if erro or res is None:
            print(f"  ❌ Erro: {erro}\n")
            continue

        detectado = formatar_gabarito(res, args.questoes)
        comp      = comparar(detectado, gabarito)
        total_acertos += comp["acertos"]

        imprimir_linha(img_path.name, detectado, gabarito, comp["acertos"])

        # Mostrar erros individuais
        if comp["detalhes"]:
            erros_str = "  ".join(
                f"Q{d['questao']}:{d['detectado']}≠{d['esperado']}"
                for d in comp["detalhes"]
            )
            print(f"  Erros     : {erros_str}")

        nao_det = [d["questao"] for d in comp["detalhes"] if d["detectado"] == "-"]
        if nao_det:
            print(f"  Não det.  : Q{', Q'.join(map(str, nao_det))}")
        print()

        resultados_finais.append({
            "imagem":    img_path.name,
            "detectado": detectado,
            "acertos":   comp["acertos"],
            "erros":     comp["erros"],
            "taxa":      comp["taxa"],
            "detalhes":  comp["detalhes"],
        })

    total_questoes = len(imagens) * args.questoes
    taxa_geral     = total_acertos / total_questoes * 100 if total_questoes > 0 else 0

    print("=" * 70)
    print(f"  RESULTADO FINAL")
    print(f"  Imagens processadas : {len(resultados_finais)}")
    print(f"  Total de acertos    : {total_acertos} / {total_questoes}")
    print(f"  Taxa geral          : {taxa_geral:.1f}%")
    print("=" * 70)

    # Salvar JSON
    ts       = datetime.now().strftime("%Y%m%d_%H%M%S")
    arquivo  = f"relatorio_auto_{ts}.json"
    relatorio = {
        "data":            datetime.now().isoformat(),
        "gabarito_usado":  gabarito,
        "num_questoes":    args.questoes,
        "num_colunas":     args.colunas,
        "sensitivity":     args.sens,
        "total_imagens":   len(resultados_finais),
        "total_acertos":   total_acertos,
        "total_questoes":  total_questoes,
        "taxa_geral":      taxa_geral,
        "resultados":      resultados_finais,
    }
    with open(arquivo, "w", encoding="utf-8") as f:
        json.dump(relatorio, f, indent=2, ensure_ascii=False)

    print(f"\n✅ Relatório salvo: {arquivo}\n")


if __name__ == "__main__":
    main()
