#!/usr/bin/env python3
"""
Quick test script to process images and show results
"""

import cv2
import os
from pathlib import Path
from image_processing import (
    melhorar_pre_processamento_adaptativo,
    corrigir_perspectiva,
    detectar_bolhas_avancado,
    agrupar_bolhas_por_questoes
)
from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer

def quick_test(dataset_path):
    """Process images from dataset and show results"""

    print("\n" + "="*70)
    print("TESTE RÁPIDO - DETECÇÃO DE CARTÃO RESPOSTA")
    print("="*70)

    analyzer = CartaoRespostaAnalyzer()
    multi_analyzer = MultiColumnCartaoAnalyzer(analyzer)

    # Find all images
    image_files = []
    for ext in ['*.jpg', '*.jpeg', '*.png', '*.JPG', '*.JPEG', '*.PNG']:
        image_files.extend(Path(dataset_path).glob(ext))

    image_files = sorted(image_files)

    if not image_files:
        print(f"❌ Nenhuma imagem encontrada em {dataset_path}")
        return

    print(f"\n📸 Encontradas {len(image_files)} imagens")
    print(f"Processando...\n")

    import time
    total_time = 0

    for i, image_path in enumerate(image_files[:5], 1):  # Process first 5
        print(f"\n[{i}] Processando: {image_path.name}")

        image = cv2.imread(str(image_path))
        if image is None:
            print(f"   ❌ Erro ao ler imagem")
            continue

        h, w = image.shape[:2]
        print(f"   📐 Tamanho: {w}x{h} pixels")

        start = time.time()

        try:
            # Preprocessing
            binary, metadata = melhorar_pre_processamento_adaptativo(image)
            print(f"   ✅ Pré-processamento: {metadata.get('illumination_profile', 'unknown')}")

            # Perspective correction
            image_corrected, binary_corrected, correction_success = corrigir_perspectiva(image, binary)
            if correction_success:
                image = image_corrected
                binary = binary_corrected
                print(f"   ✅ Perspectiva corrigida")

            # Analysis
            debug_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            resultados = multi_analyzer.analisar_cartao_multicolunas(
                image, binary, debug_image,
                num_questoes=10,
                num_colunas=1,
                sensitivity=0.3,
                threshold=150,
                return_debug_image=False
            )

            elapsed = time.time() - start
            total_time += elapsed

            # Show results
            respostas = [resultados.get(q) for q in range(1, 11)]
            print(f"   📊 Respostas: {respostas}")
            print(f"   ⏱️  Tempo: {elapsed:.2f}s")

        except Exception as e:
            elapsed = time.time() - start
            print(f"   ❌ Erro: {str(e)[:60]}")
            print(f"   ⏱️  Tempo: {elapsed:.2f}s")

    print(f"\n" + "="*70)
    print(f"✅ Processadas {min(5, len(image_files))} imagens")
    if total_time > 0:
        print(f"⏱️  Tempo médio: {total_time/min(5, len(image_files)):.2f}s por imagem")
    print("="*70 + "\n")

if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1:
        dataset = sys.argv[1]
    else:
        dataset = "test_images/light_conditions/sombra_parcial"

    quick_test(dataset)
