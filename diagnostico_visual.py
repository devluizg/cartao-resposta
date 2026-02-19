#!/usr/bin/env python3
"""
Script de Diagnóstico Visual
Processa uma imagem e mostra TUDO que está acontecendo em cada etapa
"""

import cv2
import numpy as np
from pathlib import Path
from image_processing import (
    melhorar_pre_processamento_adaptativo,
    corrigir_perspectiva,
    detectar_bolhas_avancado,
    agrupar_bolhas_por_questoes
)

def salvar_imagem_debug(img, nome):
    """Salva imagem para análise"""
    cv2.imwrite(f"debug_{nome}.png", img)
    print(f"   💾 Salvo: debug_{nome}.png")

def diagnosticar_imagem(image_path, num_questoes=24, num_colunas=2):
    """Diagnóstico completo de uma imagem"""

    print("\n" + "="*80)
    print(f"DIAGNÓSTICO VISUAL: {Path(image_path).name}")
    print("="*80 + "\n")

    # 1. Carregar imagem
    print("1️⃣  CARREGAMENTO")
    image = cv2.imread(str(image_path))
    if image is None:
        print("   ❌ Erro ao carregar!")
        return

    h, w = image.shape[:2]
    print(f"   ✅ Tamanho: {w}x{h} pixels")
    print(f"   ✅ Formato: BGR (OpenCV)")
    salvar_imagem_debug(image, "01_original")

    # 2. Pré-processamento
    print("\n2️⃣  PRÉ-PROCESSAMENTO ADAPTATIVO")
    binary, metadata = melhorar_pre_processamento_adaptativo(image)
    print(f"   ✅ Perfil iluminação: {metadata['illumination_profile']}")
    print(f"   ✅ Brilho: {metadata['brightness']:.0f}")
    print(f"   ✅ Contraste: {metadata['contrast']:.0f}")
    print(f"   ✅ Pixels pretos: {np.sum(binary == 0)}")
    print(f"   ✅ Pixels brancos: {np.sum(binary == 255)}")

    # Visualizar binary
    binary_viz = binary.copy()
    salvar_imagem_debug(binary_viz, "02_binary")

    # 3. Correção de perspectiva
    print("\n3️⃣  CORREÇÃO DE PERSPECTIVA")
    image_corrected, binary_corrected, success = corrigir_perspectiva(image, binary)
    print(f"   {'✅' if success else '❌'} Sucesso: {success}")
    if success:
        image = image_corrected
        binary = binary_corrected
        print(f"   ✅ Nova dimensão: {binary.shape[1]}x{binary.shape[0]}")
    else:
        print(f"   ⚠️  Usando imagem original")
    salvar_imagem_debug(binary, "03_after_perspective")

    # 4. Detecção de bolhas
    print("\n4️⃣  DETECÇÃO DE BOLHAS (SYSTEM HÍBRIDO)")
    print("   Iniciando 4 métodos de detecção...")

    bolhas, debug_img = detectar_bolhas_avancado(binary)

    print(f"   ✅ Total de bolhas detectadas: {len(bolhas)}")

    if len(bolhas) > 0:
        print(f"\n   📊 Estatísticas das bolhas:")
        raios = [b['radius'] for b in bolhas]
        print(f"      Raio mínimo: {min(raios)} px")
        print(f"      Raio máximo: {max(raios)} px")
        print(f"      Raio médio: {np.mean(raios):.0f} px")

        fills = [b['fill_rate'] for b in bolhas]
        print(f"\n   📊 Estatísticas de preenchimento:")
        print(f"      Preenchimento mínimo: {min(fills):.2f}")
        print(f"      Preenchimento máximo: {max(fills):.2f}")
        print(f"      Preenchimento médio: {np.mean(fills):.2f}")

        # Distribuição
        preenchidas = sum(1 for b in bolhas if b['filled'])
        vazias = len(bolhas) - preenchidas
        print(f"\n   📊 Classificação:")
        print(f"      Preenchidas: {preenchidas}")
        print(f"      Vazias: {vazias}")
    else:
        print("   ❌ NENHUMA BOLHA DETECTADA!")

    salvar_imagem_debug(debug_img, "04_bolhas_detectadas")

    # 5. Agrupamento por questões
    print("\n5️⃣  AGRUPAMENTO POR QUESTÕES")

    if len(bolhas) > 0:
        questoes = agrupar_bolhas_por_questoes(bolhas, num_questoes, 5)

        print(f"   ✅ Clusters detectados: {len(questoes)}")
        print(f"   ⚠️  Esperado: {num_questoes}")

        if len(questoes) == num_questoes:
            print(f"   ✅ Agrupamento PERFEITO!")
        else:
            print(f"   ❌ DESVIO: {abs(len(questoes) - num_questoes)} questões")

        print(f"\n   📊 Distribuição de bolhas por questão:")
        for i, questao in enumerate(questoes[:5], 1):  # Primeiras 5
            num_bolhas = len(questao)
            print(f"      Q{i}: {num_bolhas} bolhas", end="")
            if num_bolhas == 5:
                print(" ✅")
            else:
                print(f" ❌ (esperado 5)")

        if len(questoes) > 5:
            print(f"      ... ({len(questoes)-5} questões mais)")
    else:
        print("   ❌ Impossível agrupar (nenhuma bolha detectada)")

    # 6. Resumo e recomendações
    print("\n6️⃣  DIAGNÓSTICO RESUMIDO")
    print("="*80)

    problemas = []

    if len(bolhas) < num_questoes * 3:
        problemas.append("❌ Poucas bolhas detectadas (< 3x questões esperadas)")

    if metadata['brightness'] < 80 or metadata['brightness'] > 200:
        problemas.append(f"⚠️  Brilho anormal ({metadata['brightness']:.0f})")

    if len(questoes if len(bolhas) > 0 else []) != num_questoes:
        problemas.append(f"❌ Clustering inadequado ({len(questoes if len(bolhas) > 0 else [])} vs {num_questoes})")

    if problemas:
        print("\n🚨 PROBLEMAS DETECTADOS:\n")
        for p in problemas:
            print(f"   {p}")
    else:
        print("\n✅ Nenhum problema detectado!")

    print("\n" + "="*80)
    print(f"\n📁 Arquivos de debug salvos:")
    print(f"   debug_01_original.png - Imagem original")
    print(f"   debug_02_binary.png - Imagem binária após pré-processamento")
    print(f"   debug_03_after_perspective.png - Após correção de perspectiva")
    print(f"   debug_04_bolhas_detectadas.png - Bolhas detectadas")
    print(f"\n💡 Abra os arquivos para visualizar cada etapa do processamento")

def main():
    import sys

    if len(sys.argv) < 2:
        # Processar primeira imagem de test_unified
        imagens = list(Path("test_unified").glob("*.jpeg")) + list(Path("test_unified").glob("*.jpg"))
        if imagens:
            image_path = imagens[0]
        else:
            print("❌ Nenhuma imagem encontrada!")
            return
    else:
        image_path = sys.argv[1]

    num_questoes = int(sys.argv[2]) if len(sys.argv) > 2 else 24

    diagnosticar_imagem(image_path, num_questoes)

if __name__ == "__main__":
    main()
