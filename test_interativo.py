#!/usr/bin/env python3
"""
Script Interativo para Teste e Validação de Cartão Resposta
Processa cada imagem e permite você digitar o gabarito real para comparação
"""

import cv2
import json
import os
from pathlib import Path
from datetime import datetime
from image_processing import (
    melhorar_pre_processamento_adaptativo,
    corrigir_perspectiva,
    redimensionar_imagem_otimizada
)
from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer

def limpar_tela():
    """Limpa a tela do terminal"""
    os.system('clear' if os.name == 'posix' else 'cls')

def mostrar_header():
    """Mostra cabeçalho do programa"""
    print("\n" + "="*80)
    print("TESTE INTERATIVO - DETECÇÃO DE CARTÃO RESPOSTA")
    print("Processa imagem → Mostra resultado → Você digita gabarito real → Compara")
    print("="*80 + "\n")

def obter_imagens(dataset_path="test_unified"):
    """Obtém lista de imagens"""
    imagens = []
    for ext in ['*.jpg', '*.jpeg', '*.png', '*.JPG', '*.JPEG', '*.PNG']:
        imagens.extend(Path(dataset_path).glob(ext))

    return sorted(imagens)

def processar_imagem(image_path, num_questoes=10):
    """Processa uma imagem e retorna gabarito detectado"""
    try:
        image = cv2.imread(str(image_path))
        if image is None:
            return None, "Erro ao ler imagem"

        # Redimensionar se necessário
        image, _ = redimensionar_imagem_otimizada(image)

        # Pré-processamento
        binary, metadata = melhorar_pre_processamento_adaptativo(image)

        # Correção de perspectiva
        image_corrected, binary_corrected, success = corrigir_perspectiva(image, binary)
        if success:
            image = image_corrected
            binary = binary_corrected

        # Análise
        analyzer = CartaoRespostaAnalyzer()
        multi_analyzer = MultiColumnCartaoAnalyzer(analyzer)

        debug_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        resultados = multi_analyzer.analisar_cartao_multicolunas(
            image, binary, debug_image,
            num_questoes=num_questoes,
            num_colunas=1,
            sensitivity=0.3,
            threshold=150,
            return_debug_image=False
        )

        return resultados, None

    except Exception as e:
        return None, str(e)

def formatar_gabarito(resultados, num_questoes=10):
    """Formata gabarito para exibição"""
    gabarito = []
    for q in range(1, num_questoes + 1):
        resp = resultados.get(q)
        if resp is None:
            gabarito.append("-")
        elif "ERRO" in str(resp):
            gabarito.append("X")  # X para erro de múltiplas marcações
        else:
            gabarito.append(str(resp))
    return gabarito

def obter_gabarito_usuario(num_questoes=10, gabarito_detectado=None):
    """Pede ao usuário para digitar o gabarito real"""
    print(f"\n📝 Digite o gabarito real ({num_questoes} alternativas)")
    print("   Alternativas: A, B, C, D, E")
    print("   Use '-' se a questão foi deixada em branco")
    print("   Exemplos: A B C D E  ou  A-CDE  ou  ABCDE\n")

    if gabarito_detectado:
        print(f"   Detectado: {' '.join(gabarito_detectado)}")

    while True:
        entrada = input("   Gabarito: ").strip().upper()

        # Remover espaços
        entrada = entrada.replace(" ", "")

        # Validar comprimento
        if len(entrada) != num_questoes:
            print(f"   ❌ Digite exatamente {num_questoes} caracteres!")
            continue

        # Validar caracteres
        valido = True
        for char in entrada:
            if char not in "ABCDE-":
                print(f"   ❌ Caractere inválido: '{char}' (use A, B, C, D, E ou -)")
                valido = False
                break

        if valido:
            return list(entrada)

def comparar_gabaritos(detectado, real):
    """Compara gabarito detectado com real"""
    acertos = 0
    erros = 0
    diferenças = []

    for q, (det, real_resp) in enumerate(zip(detectado, real), 1):
        # Normalizar valores
        det_norm = "-" if det == "X" or det == "-" else det
        real_norm = real_resp

        if det_norm == real_norm:
            acertos += 1
        else:
            erros += 1
            diferenças.append({
                'questao': q,
                'detectado': det,
                'real': real_resp
            })

    taxa_acerto = (acertos / len(detectado) * 100) if len(detectado) > 0 else 0

    return {
        'acertos': acertos,
        'erros': erros,
        'taxa_acerto': taxa_acerto,
        'diferenças': diferenças
    }

def main():
    limpar_tela()
    mostrar_header()

    # Obter imagens
    imagens = obter_imagens()

    if not imagens:
        print("❌ Nenhuma imagem encontrada em test_unified/")
        return

    print(f"📸 Encontradas {len(imagens)} imagens\n")

    # Parâmetros
    num_questoes = 10
    num_colunas = 1

    resposta = input(f"Número de questões por cartão? (padrão {num_questoes}): ").strip()
    if resposta.isdigit():
        num_questoes = int(resposta)

    resposta = input(f"Número de colunas? (padrão {num_colunas}): ").strip()
    if resposta.isdigit():
        num_colunas = int(resposta)

    # Estrutura para armazenar resultados
    resultados_teste = []
    total_acertos = 0
    total_questoes = 0

    # Processar cada imagem
    for i, image_path in enumerate(imagens, 1):
        limpar_tela()
        mostrar_header()

        print(f"[{i}/{len(imagens)}] Processando: {image_path.name}\n")

        # Processar imagem
        print("⏳ Processando imagem...")
        resultados, erro = processar_imagem(image_path, num_questoes)

        if erro:
            print(f"❌ Erro: {erro}")
            input("Pressione ENTER para continuar...")
            continue

        gabarito_detectado = formatar_gabarito(resultados, num_questoes)

        print(f"✅ Imagem processada\n")
        print(f"📊 Gabarito detectado: {' '.join(gabarito_detectado)}")

        # Obter gabarito real do usuário
        gabarito_real = obter_gabarito_usuario(num_questoes, gabarito_detectado)

        # Comparar
        comparacao = comparar_gabaritos(gabarito_detectado, gabarito_real)

        # Exibir resultado
        limpar_tela()
        mostrar_header()

        print(f"[{i}/{len(imagens)}] {image_path.name}\n")
        print(f"Detectado: {' '.join(gabarito_detectado)}")
        print(f"Real:      {' '.join(gabarito_real)}")
        print()
        print(f"📈 Resultado:")
        print(f"   Acertos: {comparacao['acertos']}/{num_questoes}")
        print(f"   Erros: {comparacao['erros']}/{num_questoes}")
        print(f"   Taxa de acerto: {comparacao['taxa_acerto']:.1f}%")

        if comparacao['diferenças']:
            print(f"\n⚠️  Diferenças encontradas:")
            for diff in comparacao['diferenças']:
                det_symbol = "❌" if diff['detectado'] == "X" else "⚠️"
                print(f"   {det_symbol} Q{diff['questao']:2d}: Detectado={diff['detectado']} vs Real={diff['real']}")

        # Armazenar resultado
        resultados_teste.append({
            'imagem': image_path.name,
            'detectado': gabarito_detectado,
            'real': gabarito_real,
            'acertos': comparacao['acertos'],
            'erros': comparacao['erros'],
            'taxa_acerto': comparacao['taxa_acerto']
        })

        total_acertos += comparacao['acertos']
        total_questoes += num_questoes

        # Próxima imagem
        input("\nPressione ENTER para próxima imagem...")

    # Relatório final
    limpar_tela()
    mostrar_header()

    print("📊 RELATÓRIO FINAL\n")
    print("="*80)

    for resultado in resultados_teste:
        print(f"\n{resultado['imagem']}")
        print(f"  Detectado: {' '.join(resultado['detectado'])}")
        print(f"  Real:      {' '.join(resultado['real'])}")
        print(f"  Acertos:   {resultado['acertos']}/{num_questoes} ({resultado['taxa_acerto']:.1f}%)")

    print("\n" + "="*80)
    print(f"\n📈 ESTATÍSTICAS GERAIS")
    print(f"   Total de imagens:  {len(resultados_teste)}")
    print(f"   Total de questões: {total_questoes}")
    print(f"   Total de acertos:  {total_acertos}")
    print(f"   Taxa geral:        {(total_acertos/total_questoes*100):.1f}%")

    # Salvar relatório em JSON
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    relatorio_file = f"relatorio_teste_{timestamp}.json"

    relatorio_final = {
        'data': datetime.now().isoformat(),
        'num_questoes': num_questoes,
        'num_colunas': num_colunas,
        'total_imagens': len(resultados_teste),
        'total_acertos': total_acertos,
        'total_questoes': total_questoes,
        'taxa_geral': (total_acertos/total_questoes*100) if total_questoes > 0 else 0,
        'resultados': resultados_teste
    }

    with open(relatorio_file, 'w', encoding='utf-8') as f:
        json.dump(relatorio_final, f, indent=2, ensure_ascii=False)

    print(f"\n✅ Relatório salvo em: {relatorio_file}")
    print("="*80 + "\n")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n❌ Teste cancelado pelo usuário")
