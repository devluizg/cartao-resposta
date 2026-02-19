#!/usr/bin/env python3
"""
Script de teste automatizado para o sistema de detecção de cartão-resposta.
Valida a confiabilidade e precisão da detecção em diferentes condições.

Uso:
    python test_runner.py --dataset /path/to/test/images --ground-truth /path/to/ground_truth.json
"""

import os
import sys
import json
import cv2
import numpy as np
import argparse
from pathlib import Path
from collections import defaultdict
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, confusion_matrix

from image_processing import (
    melhorar_pre_processamento_adaptativo,
    corrigir_perspectiva,
    detectar_bolhas_avancado,
    agrupar_bolhas_por_questoes,
    validar_geometria_questao
)
from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer

class TestRunner:
    def __init__(self, ground_truth_file=None):
        self.analyzer = CartaoRespostaAnalyzer()
        self.multi_analyzer = MultiColumnCartaoAnalyzer(self.analyzer)
        self.ground_truth = {}
        self.resultados_teste = []

        if ground_truth_file and os.path.exists(ground_truth_file):
            with open(ground_truth_file, 'r') as f:
                self.ground_truth = json.load(f)

    def processar_imagem(self, image_path, num_questoes=10, num_colunas=1):
        """Processa uma imagem de cartão-resposta."""
        image = cv2.imread(image_path)
        if image is None:
            return None

        try:
            # Pré-processamento
            binary, metadata = melhorar_pre_processamento_adaptativo(image)

            # Correção de perspectiva
            image_corrected, binary_corrected, success = corrigir_perspectiva(image, binary)
            if success:
                image = image_corrected
                binary = binary_corrected

            # Análise
            debug_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            resultados = self.multi_analyzer.analisar_cartao_multicolunas(
                image, binary, debug_image,
                num_questoes=num_questoes,
                num_colunas=num_colunas,
                sensitivity=0.3,
                threshold=150,
                return_debug_image=False
            )

            return resultados
        except Exception as e:
            print(f"❌ Erro ao processar {image_path}: {e}")
            return None

    def validar_resultado(self, image_name, resultados_detectados):
        """Valida os resultados contra o ground truth."""
        if image_name not in self.ground_truth:
            return None

        ground_truth = self.ground_truth[image_name]
        esperadas = []
        detectadas = []

        # Comparar resultado esperado com detectado
        for q in sorted(set(list(ground_truth.keys()) + list(resultados_detectados.keys()))):
            try:
                q_num = int(q)
            except:
                q_num = q

            esperada = ground_truth.get(str(q_num))
            detectada = resultados_detectados.get(q_num)

            esperadas.append(esperada)
            detectadas.append(detectada)

        return {
            'image': image_name,
            'esperadas': esperadas,
            'detectadas': detectadas
        }

    def calcular_metricas(self, validacoes):
        """Calcula métricas de desempenho."""
        todas_esperadas = []
        todas_detectadas = []

        for validacao in validacoes:
            if validacao is None:
                continue
            todas_esperadas.extend([e for e in validacao['esperadas'] if e is not None])
            todas_detectadas.extend([d for d in validacao['detectadas'] if d is not None])

        if not todas_esperadas:
            return None

        # Converter para formato numérico para métricas
        mapa_alt = {'A': 0, 'B': 1, 'C': 2, 'D': 3, 'E': 4, None: -1}

        y_true = [mapa_alt.get(e, -1) for e in todas_esperadas]
        y_pred = [mapa_alt.get(d, -1) for d in todas_detectadas]

        # Remover casos onde ground truth não existe
        validos = [(t, p) for t, p in zip(y_true, y_pred) if t != -1]
        if not validos:
            return None

        y_true_valido = [t for t, p in validos]
        y_pred_valido = [p for t, p in validos]

        metricas = {
            'accuracy': float(accuracy_score(y_true_valido, y_pred_valido)),
            'precisao': float(precision_score(y_true_valido, y_pred_valido, average='weighted', zero_division=0)),
            'recall': float(recall_score(y_true_valido, y_pred_valido, average='weighted', zero_division=0)),
            'f1': float(f1_score(y_true_valido, y_pred_valido, average='weighted', zero_division=0))
        }

        return metricas

    def gerar_relatorio(self, dataset_path, num_questoes=10, num_colunas=1):
        """Gera relatório completo de testes."""
        print("\n" + "="*70)
        print("TESTE AUTOMATIZADO - SISTEMA DE DETECÇÃO DE CARTÃO-RESPOSTA")
        print("="*70)

        # Listar imagens
        image_files = list(Path(dataset_path).glob('*.jpg')) + list(Path(dataset_path).glob('*.png'))

        if not image_files:
            print(f"❌ Nenhuma imagem encontrada em {dataset_path}")
            return

        print(f"📊 Testando {len(image_files)} imagens...")
        print("="*70)

        validacoes = []
        tempo_total = 0

        for i, image_path in enumerate(image_files, 1):
            image_name = image_path.stem

            print(f"\n[{i}/{len(image_files)}] Processando: {image_name}")

            import time
            start = time.time()
            resultados = self.processar_imagem(str(image_path), num_questoes, num_colunas)
            tempo_decorrido = time.time() - start
            tempo_total += tempo_decorrido

            if resultados is None:
                print(f"❌ Falha ao processar")
                continue

            print(f"✅ Processado em {tempo_decorrido:.2f}s")

            # Validar
            validacao = self.validar_resultado(image_name, resultados)
            if validacao:
                validacoes.append(validacao)
                print(f"   Esperado: {validacao['esperadas'][:5]}...")
                print(f"   Detectado: {validacao['detectadas'][:5]}...")

        # Calcular métricas
        print("\n" + "="*70)
        print("RESULTADOS")
        print("="*70)

        metricas = self.calcular_metricas(validacoes)

        if metricas:
            print(f"\n📈 Métricas de Desempenho:")
            print(f"   • Accuracy:  {metricas['accuracy']:.1%}")
            print(f"   • Precisão:  {metricas['precisao']:.1%}")
            print(f"   • Recall:    {metricas['recall']:.1%}")
            print(f"   • F1-Score:  {metricas['f1']:.1%}")
        else:
            print("⚠️  Sem ground truth para validação")

        print(f"\n⏱️  Tempo Total: {tempo_total:.2f}s ({tempo_total/len(image_files):.2f}s por imagem)")

        # Verificar metas
        print("\n" + "="*70)
        print("CHECKLIST DE VALIDAÇÃO FINAL")
        print("="*70)

        metas = {
            "Taxa de detecção > 99%": metricas.get('accuracy', 0) > 0.99 if metricas else None,
            "Falsos positivos < 0.5%": metricas.get('precision', 0) > 0.995 if metricas else None,
            "Tempo de processamento < 1s": tempo_total/len(image_files) < 1.0,
            "Funciona com 10+ questões": num_questoes >= 10,
        }

        for meta, atingida in metas.items():
            status = "✅" if atingida else "❌" if atingida is False else "⚠️"
            print(f"{status} {meta}")

        print("="*70 + "\n")

        return {
            'metricas': metricas,
            'tempo_total': tempo_total,
            'imagens_testadas': len(validacoes),
            'total_imagens': len(image_files)
        }

def main():
    parser = argparse.ArgumentParser(
        description='Testa o sistema de detecção de cartão-resposta'
    )
    parser.add_argument(
        '--dataset', '-d',
        required=True,
        help='Caminho para pasta com imagens de teste'
    )
    parser.add_argument(
        '--ground-truth', '-g',
        help='Caminho para arquivo JSON com ground truth'
    )
    parser.add_argument(
        '--questoes', '-q',
        type=int,
        default=10,
        help='Número de questões (padrão: 10)'
    )
    parser.add_argument(
        '--colunas', '-c',
        type=int,
        default=1,
        help='Número de colunas (padrão: 1)'
    )

    args = parser.parse_args()

    if not os.path.exists(args.dataset):
        print(f"❌ Dataset não encontrado: {args.dataset}")
        sys.exit(1)

    runner = TestRunner(args.ground_truth)
    runner.gerar_relatorio(args.dataset, args.questoes, args.colunas)

if __name__ == "__main__":
    main()
