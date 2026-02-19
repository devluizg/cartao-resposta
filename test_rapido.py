#!/usr/bin/env python3
"""
Teste Rápido - Digite gabarito UMA VEZ, use para TODAS as imagens
Perfeito para testar múltiplas imagens do mesmo cartão resposta
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
    print("TESTE RÁPIDO - UM GABARITO PARA TODAS AS IMAGENS")
    print("Digite o gabarito UMA VEZ → Use para TODAS as imagens do mesmo cartão")
    print("="*80 + "\n")

def obter_imagens(dataset_path="test_unified"):
    """Obtém lista de imagens"""
    imagens = []
    for ext in ['*.jpg', '*.jpeg', '*.png', '*.JPG', '*.JPEG', '*.PNG']:
        imagens.extend(Path(dataset_path).glob(ext))
    return sorted(imagens)

def processar_imagem(image_path, num_questoes=10, num_colunas=1):
    """Processa uma imagem e retorna gabarito detectado"""
    try:
        image = cv2.imread(str(image_path))
        if image is None:
            return None, "Erro ao ler imagem"

        image, _ = redimensionar_imagem_otimizada(image)
        binary, metadata = melhorar_pre_processamento_adaptativo(image)

        image_corrected, binary_corrected, success = corrigir_perspectiva(image, binary)
        if success:
            image = image_corrected
            binary = binary_corrected

        analyzer = CartaoRespostaAnalyzer()
        multi_analyzer = MultiColumnCartaoAnalyzer(analyzer)

        debug_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        resultados = multi_analyzer.analisar_cartao_multicolunas(
            image, binary, debug_image,
            num_questoes=num_questoes,
            num_colunas=num_colunas,
            sensitivity=0.10,
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
            gabarito.append("X")
        else:
            gabarito.append(str(resp))
    return gabarito

def obter_gabarito_unico(num_questoes=10):
    """Pede gabarito UMA VEZ para usar em todas as imagens"""
    print(f"\n📝 GABARITO ÚNICO (será usado para TODAS as {num_questoes} imagens)")
    print("   Alternativas: A, B, C, D, E")
    print("   Use '-' para questões em branco")
    print("   Exemplos: A B C D E  ou  ABCDEABCDE  ou  A-C-E\n")

    while True:
        entrada = input("   Digite o gabarito: ").strip().upper()

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

def carregar_gabaritos_salvos():
    """Carrega gabaritos previamente salvos"""
    gabaritos_file = "gabaritos_salvos.json"
    if os.path.exists(gabaritos_file):
        with open(gabaritos_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {}

def salvar_gabarito(nome, gabarito):
    """Salva gabarito para futuros testes"""
    gabaritos_file = "gabaritos_salvos.json"

    gabaritos = carregar_gabaritos_salvos()
    gabaritos[nome] = {
        'gabarito': gabarito,
        'data': datetime.now().isoformat()
    }

    with open(gabaritos_file, 'w', encoding='utf-8') as f:
        json.dump(gabaritos, f, indent=2, ensure_ascii=False)

def comparar_gabaritos(detectado, real):
    """Compara gabarito detectado com real"""
    acertos = 0
    erros = 0
    diferenças = []

    for q, (det, real_resp) in enumerate(zip(detectado, real), 1):
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

    imagens = obter_imagens()

    if not imagens:
        print("❌ Nenhuma imagem encontrada em test_unified/")
        return

    print(f"📸 Encontradas {len(imagens)} imagens\n")

    # Parâmetros
    num_questoes = 10
    num_colunas = 1

    resposta = input(f"Número de questões? (padrão {num_questoes}): ").strip()
    if resposta.isdigit():
        num_questoes = int(resposta)

    resposta_colunas = input(f"Número de colunas? (padrão {num_colunas}): ").strip()
    if resposta_colunas.isdigit():
        num_colunas = int(resposta_colunas)

    # Carregar gabaritos salvos
    gabaritos_salvos = carregar_gabaritos_salvos()

    if gabaritos_salvos:
        print(f"\n📚 Gabaritos salvos anteriormente:")
        lista_gabaritos = list(gabaritos_salvos.keys())
        for i, nome in enumerate(lista_gabaritos, 1):
            print(f"   {i}. {nome}")
        print(f"   {len(lista_gabaritos)+1}. Digitar novo gabarito")

        escolha = input(f"\nEscolha (1-{len(lista_gabaritos)+1}): ").strip()
        try:
            idx = int(escolha) - 1
            if 0 <= idx < len(lista_gabaritos):
                nome_selecionado = lista_gabaritos[idx]
                gabarito_real = gabaritos_salvos[nome_selecionado]['gabarito']
                print(f"\n✅ Gabarito carregado: {' '.join(gabarito_real)}")
            else:
                gabarito_real = obter_gabarito_unico(num_questoes)
                nome_novo = input("\n💾 Nome para salvar este gabarito: ").strip()
                if nome_novo:
                    salvar_gabarito(nome_novo, gabarito_real)
                    print(f"✅ Gabarito '{nome_novo}' salvo!")
        except:
            gabarito_real = obter_gabarito_unico(num_questoes)
    else:
        gabarito_real = obter_gabarito_unico(num_questoes)
        nome_novo = input("\n💾 Nome para salvar este gabarito (opcional): ").strip()
        if nome_novo:
            salvar_gabarito(nome_novo, gabarito_real)
            print(f"✅ Gabarito '{nome_novo}' salvo!")

    # Processar todas as imagens com o MESMO gabarito
    print(f"\n{'='*80}")
    print(f"✅ Usando gabarito: {' '.join(gabarito_real)}")
    print(f"{'='*80}\n")

    resultados_teste = []
    total_acertos = 0
    total_questoes = 0

    for i, image_path in enumerate(imagens, 1):
        limpar_tela()
        mostrar_header()

        print(f"[{i}/{len(imagens)}] {image_path.name}\n")

        # Processar imagem
        print("⏳ Processando...")
        resultados, erro = processar_imagem(image_path, num_questoes, num_colunas)

        if erro:
            print(f"❌ Erro: {erro}")
            input("Pressione ENTER para próxima...")
            continue

        gabarito_detectado = formatar_gabarito(resultados, num_questoes)

        # Comparar
        comparacao = comparar_gabaritos(gabarito_detectado, gabarito_real)

        # Exibir resultado
        print(f"Detectado: {' '.join(gabarito_detectado)}")
        print(f"Real:      {' '.join(gabarito_real)}")
        print()
        print(f"📈 Resultado:")
        print(f"   Acertos: {comparacao['acertos']}/{num_questoes}")
        print(f"   Erros: {comparacao['erros']}/{num_questoes}")
        print(f"   Taxa: {comparacao['taxa_acerto']:.1f}%")

        if comparacao['diferenças']:
            print(f"\n⚠️  Diferenças:")
            for diff in comparacao['diferenças'][:10]:  # Mostrar até 10
                det_symbol = "❌" if diff['detectado'] == "X" else "⚠️"
                print(f"   {det_symbol} Q{diff['questao']:2d}: {diff['detectado']} vs {diff['real']}")
            if len(comparacao['diferenças']) > 10:
                print(f"   ... e mais {len(comparacao['diferenças'])-10}")

        # Armazenar resultado
        resultados_teste.append({
            'imagem': image_path.name,
            'detectado': gabarito_detectado,
            'acertos': comparacao['acertos'],
            'taxa_acerto': comparacao['taxa_acerto']
        })

        total_acertos += comparacao['acertos']
        total_questoes += num_questoes

        if i < len(imagens):
            input("\nPressione ENTER para próxima imagem...")

    # Relatório final
    limpar_tela()
    mostrar_header()

    print("📊 RELATÓRIO FINAL\n")
    print("="*80)

    for resultado in resultados_teste:
        print(f"\n{resultado['imagem']}")
        print(f"  Detectado: {' '.join(resultado['detectado'])}")
        print(f"  Acertos:   {resultado['acertos']}/{num_questoes} ({resultado['taxa_acerto']:.1f}%)")

    print("\n" + "="*80)
    print(f"\n📈 ESTATÍSTICAS GERAIS")
    print(f"   Total de imagens:  {len(resultados_teste)}")
    print(f"   Total de questões: {total_questoes}")
    print(f"   Total de acertos:  {total_acertos}")
    print(f"   Taxa geral:        {(total_acertos/total_questoes*100):.1f}%")

    # Salvar relatório
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    relatorio_file = f"relatorio_rapido_{timestamp}.json"

    relatorio_final = {
        'data': datetime.now().isoformat(),
        'gabarito_usado': gabarito_real,
        'num_questoes': num_questoes,
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
