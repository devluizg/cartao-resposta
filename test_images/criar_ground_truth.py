#!/usr/bin/env python3
"""
Script auxiliar para criar arquivo ground_truth.json de forma interativa.

Uso:
    python criar_ground_truth.py
"""

import json
import os
from pathlib import Path

def obter_imagens_no_diretorio(caminho="."):
    """Obtém todas as imagens JPG/PNG no diretório."""
    imagens = []
    for ext in ["*.jpg", "*.jpeg", "*.png", "*.JPG", "*.JPEG", "*.PNG"]:
        imagens.extend(Path(caminho).glob(ext))

    # Remover duplicatas e ordenar
    imagens = sorted(set(str(i) for i in imagens))
    return imagens

def criar_ground_truth_interativo():
    """Cria ground_truth.json de forma interativa."""
    print("\n" + "="*70)
    print("CRIADOR DE GROUND TRUTH - CARTÃO RESPOSTA")
    print("="*70 + "\n")

    # Perguntar número de questões
    while True:
        try:
            num_questoes = int(input("Quantas questões tem cada cartão? (padrão: 10): ") or "10")
            if num_questoes > 0:
                break
            print("❌ Digite um número positivo")
        except ValueError:
            print("❌ Digite um número válido")

    # Perguntar alternativas
    num_alternativas = 5
    alternativas = ['A', 'B', 'C', 'D', 'E']
    print(f"Alternativas: {', '.join(alternativas[:num_alternativas])}\n")

    # Obter imagens
    imagens = obter_imagens_no_diretorio()

    if not imagens:
        print("❌ Nenhuma imagem encontrada no diretório!")
        return

    print(f"📸 Encontradas {len(imagens)} imagens:\n")
    for i, img in enumerate(imagens, 1):
        print(f"  {i:2d}. {Path(img).name}")

    # Confirmar
    resposta = input(f"\n✅ Processar essas {len(imagens)} imagens? (s/n): ")
    if resposta.lower() not in ['s', 'sim', 'y', 'yes']:
        print("❌ Cancelado")
        return

    # Coletar gabaritos
    ground_truth = {}

    for img_path in imagens:
        nome_arquivo = Path(img_path).stem  # Remove extensão

        print(f"\n{'='*70}")
        print(f"Imagem: {Path(img_path).name}")
        print(f"{'='*70}")

        gabarito = {}

        for q in range(1, num_questoes + 1):
            while True:
                resposta = input(f"  Q{q:2d}: ").strip().upper()

                if resposta in alternativas[:num_alternativas]:
                    gabarito[str(q)] = resposta
                    break
                elif resposta == "PULA":
                    gabarito[str(q)] = None
                    break
                elif resposta in ["VOLTA", "V"]:
                    # Voltar à questão anterior
                    if q > 1:
                        del gabarito[str(q-1)]
                        q -= 2  # Voltar 2 porque o loop incrementa 1
                    continue
                else:
                    print(f"    ❌ Digite uma das alternativas: {', '.join(alternativas[:num_alternativas])} ou PULA")
                    continue

        ground_truth[nome_arquivo] = gabarito

        # Mostrar resumo
        print(f"\n  ✅ Gabarito registrado: {gabarito}")

    # Salvar arquivo
    output_file = "ground_truth.json"

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(ground_truth, f, indent=2, ensure_ascii=False)

    print(f"\n{'='*70}")
    print(f"✅ Ground truth salvo em: {output_file}")
    print(f"📊 Total de imagens: {len(ground_truth)}")
    print(f"{'='*70}\n")

    # Oferecer teste
    resposta = input("Deseja testar agora? (s/n): ")
    if resposta.lower() in ['s', 'sim', 'y', 'yes']:
        print("\n🧪 Para testar, execute:")
        print(f"  python ../test_runner.py --dataset . --ground-truth ground_truth.json --questoes {num_questoes}")

if __name__ == "__main__":
    try:
        criar_ground_truth_interativo()
    except KeyboardInterrupt:
        print("\n\n❌ Cancelado pelo usuário")
