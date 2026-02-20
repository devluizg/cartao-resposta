import os
import cv2
import glob
from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer
from image_processing import melhorar_pre_processamento_adaptativo, corrigir_perspectiva, redimensionar_imagem_otimizada

# VOCÊ PODE EDITAR SEU GABARITO CORRETO AQUI
GABARITO_CORRETO = {
    1: 'A', 2: 'B', 3: 'C', 4: 'D', 5: 'E',
    6: 'A', 7: 'B', 8: 'C', 9: 'D', 10: 'E',
    11: 'C', 12: 'C', 13: 'C', 14: 'A', 15: 'B',
    16: 'C', 17: 'D', 18: 'E', 19: 'A', 20: 'B',
    21: 'C', 22: 'D', 23: 'E', 24: 'C', 25: 'C'
}

NUM_QUESTOES = 25
NUM_COLUNAS = 2
PASTA_IMAGENS = "/home/luiz/cartao-resposta/test_images" # Pode apontar para a pasta que quiser!

def agrupar_respostas_str(respostas_obj):
    # Converte {"1": "A", "2": "B"} ou objeto similar garantindo chaves numéricas
    limpo = {}
    for k, v in respostas_obj.items():
        try:
            limpo[int(k)] = v
        except:
            pass
    return limpo

def main():
    imagens_encontradas = glob.glob(os.path.join(PASTA_IMAGENS, "**/*.*"), recursive=True)
    extensoes_validas = ['.jpg', '.jpeg', '.png']
    imagens = [img for img in imagens_encontradas if os.path.splitext(img)[1].lower() in extensoes_validas]
    
    if len(imagens) == 0:
        print(f"Nenhuma imagem encontrada na pasta: {PASTA_IMAGENS}")
        return
        
    print(f"========== INICIANDO TESTE EM LOTE ({len(imagens)} imagens) ==========")
    print(f"Gabarito usado: {GABARITO_CORRETO}")
    print("=" * 70)
    
    analyzer = CartaoRespostaAnalyzer()
    multi_analyzer = MultiColumnCartaoAnalyzer(analyzer)
    
    total_questoes_avaliadas = 0
    total_acertos = 0
    
    for _, img_path in enumerate(imagens, 1):
        nome_arquivo = os.path.basename(img_path)
        print(f"\n[Processando]: {nome_arquivo}...")
        
        image = cv2.imread(img_path)
        if image is None:
            print(f"  ❌ Erro ao ler a imagem.")
            continue
            
        try:
            image, _ = redimensionar_imagem_otimizada(image)
            binary, _ = melhorar_pre_processamento_adaptativo(image)
            image_corrected, binary_corrected, success = corrigir_perspectiva(image, binary)
            
            if success:
                image = image_corrected
                binary = binary_corrected
            else:
                print("  ⚠️ Falha ao corrigir perspectiva, processando imagem original.")
                
            debug_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            
            ret = multi_analyzer.analisar_cartao_multicolunas(
                image, binary, debug_image,
                num_questoes=NUM_QUESTOES,
                num_colunas=NUM_COLUNAS,
                sensitivity=0.3,
                threshold=150,
                return_debug_image=False
            )
            
            resultados = ret[0] if isinstance(ret, tuple) else ret
            respostas_detectadas = agrupar_respostas_str(resultados)
            
            # Comparação
            acertos = 0
            falhas_ou_erros = []
            
            for q in range(1, NUM_QUESTOES + 1):
                detectado = respostas_detectadas.get(q)
                esperado = GABARITO_CORRETO.get(q)
                
                if detectado == esperado:
                    acertos += 1
                else:
                    falhas_ou_erros.append(f"Q{q}(Lido:{detectado}|Esp:{esperado})")
                    
            pct = (acertos / NUM_QUESTOES) * 100
            total_acertos += acertos
            total_questoes_avaliadas += NUM_QUESTOES
            
            status = "✅ PERFEITO" if acertos == NUM_QUESTOES else "❌ ERROS"
            print(f"  -> Precisão: {acertos}/{NUM_QUESTOES} ({pct:.1f}%) | {status}")
            if falhas_ou_erros:
                print(f"  -> Divergências: {', '.join(falhas_ou_erros)}")
                
        except Exception as e:
            print(f"  ❌ Crash ao processar: {str(e)}")
            
    # Resumo Global
    if total_questoes_avaliadas > 0:
        print("\n" + "=" * 70)
        print("RESUMO FINAL DO LOTE:")
        print("=" * 70)
        global_pct = (total_acertos / total_questoes_avaliadas) * 100
        print(f"Imagens processadas: {len(imagens)}")
        print(f"Total de questões lidas em todas as imagens: {total_questoes_avaliadas}")
        print(f"Total de acertos perante gabarito: {total_acertos}")
        print(f"PRECISÃO GLOBAL DA API: {global_pct:.2f}%")

if __name__ == '__main__':
    main()
