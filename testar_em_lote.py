"""
Teste em Lote - Versão 2.1 (Visualização Corrigida)

NOVO na v2.1:
- Bolhas verdes desenhadas usando EXATAMENTE as coordenadas
  que foram processadas (sem detecção independente)
- Nenhum ponto verde fora dos limites das colunas
- Performance melhorada (sem processamento duplicado)
"""
import os
import cv2
import glob
import json
from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer
from image_processing import melhorar_pre_processamento_adaptativo, corrigir_perspectiva, redimensionar_imagem_otimizada

# VOCÊ PODE EDITAR SEU GABARITO CORRETO AQUI
GABARITO_CORRETO = {
    1: 'A', 2: 'C', 3: 'B', 4: 'B', 5: 'E',
    6: 'D', 7: 'E', 8: 'B', 9: 'D', 10: 'A',
    11: 'B', 12: 'D', 13: 'C', 14: 'A', 15: 'D',
    16: 'B', 17: 'C', 18: 'D', 19: 'E', 20: 'A',
    21: 'B', 22: 'D', 23: 'C', 24: 'B', 25: 'A'
}

NUM_QUESTOES = 25
NUM_COLUNAS = 2
PASTA_IMAGENS = "/home/luiz/cartao-resposta/test_images" # Pode apontar para a pasta que quiser!
PASTA_DEBUG = "/home/luiz/cartao-resposta/debug_lote"

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
    print(f"✨ Usando versão corrigida: Visualização com bolhas realmente selecionadas")
    print(f"Gabarito usado: {GABARITO_CORRETO}")
    print("=" * 70)
    
    analyzer = CartaoRespostaAnalyzer()
    multi_analyzer = MultiColumnCartaoAnalyzer(analyzer)
    
    total_questoes_avaliadas = 0
    total_acertos = 0
    relatorio = []
    problemas = []
    
    for _, img_path in enumerate(imagens, 1):
        nome_arquivo = os.path.basename(img_path)
        print(f"\n[Processando]: {nome_arquivo}...")
        
        image = cv2.imread(img_path)
        if image is None:
            print(f"  ❌ Erro ao ler a imagem.")
            continue
            
        try:
            image, _ = redimensionar_imagem_otimizada(image)
            binary, meta = melhorar_pre_processamento_adaptativo(image)
            image_corrected, binary_corrected, success = corrigir_perspectiva(image, binary)
            
            if success:
                image = image_corrected
                binary = binary_corrected
            else:
                print("  ⚠️ Falha ao corrigir perspectiva, processando imagem original.")
                
            debug_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

            # Analisar cartão multicolunas
            # A visualização retornada usa EXATAMENTE as coordenadas das bolhas realmente selecionadas
            ret = multi_analyzer.analisar_cartao_multicolunas(
                image, binary, debug_image,
                num_questoes=NUM_QUESTOES,
                num_colunas=NUM_COLUNAS,
                sensitivity=0.3,
                threshold=150,
                return_debug_image=True,
                quality_meta=meta
            )
            resultados, debug_img = ret if isinstance(ret, tuple) else (ret, debug_image)
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
            
            # Salvar debug do lote
            try:
                os.makedirs(PASTA_DEBUG, exist_ok=True)
                base = os.path.splitext(nome_arquivo)[0].replace(" ", "_")
                cv2.imwrite(os.path.join(PASTA_DEBUG, f"{base}_debug.png"), cv2.cvtColor(debug_img, cv2.COLOR_RGB2BGR))
                cv2.imwrite(os.path.join(PASTA_DEBUG, f"{base}_binary.png"), binary)
                with open(os.path.join(PASTA_DEBUG, f"{base}_meta.json"), "w") as f:
                    json.dump(meta, f, indent=2)
            except Exception as e:
                print(f"  ⚠️ Falha ao salvar debug local: {e}")

            # Relatório por imagem
            item = {
                "arquivo": nome_arquivo,
                "acertos": acertos,
                "total": NUM_QUESTOES,
                "precisao_pct": round(pct, 2),
                "brightness": float(meta.get("brightness", 0.0)),
                "contrast": float(meta.get("contrast", 0.0)),
                "black_ratio": float(meta.get("black_ratio", 0.0)),
                "illumination_profile": meta.get("illumination_profile", "unknown"),
                "divergencias": falhas_ou_erros
            }
            relatorio.append(item)

            # Marcar casos problemáticos
            if item["black_ratio"] < 0.01 or item["brightness"] < 90 or item["precisao_pct"] < 80:
                problemas.append(item)
                
        except Exception as e:
            print(f"  ❌ Crash ao processar: {str(e)}")
            
    # Resumo Global
    if total_questoes_avaliadas > 0:
        print("\n" + "=" * 70)
        print("RESUMO FINAL DO LOTE (v2.1 - Visualização Corrigida):")
        print("=" * 70)
        global_pct = (total_acertos / total_questoes_avaliadas) * 100
        print(f"Imagens processadas: {len(imagens)}")
        print(f"Total de questões lidas em todas as imagens: {total_questoes_avaliadas}")
        print(f"Total de acertos perante gabarito: {total_acertos}")
        print(f"PRECISÃO GLOBAL DA API: {global_pct:.2f}%")
        print(f"\n✨ Bolhas verdes desenhadas com coordenadas reais (sem ruído fora de colunas)")

        # Salvar relatório agregado
        try:
            os.makedirs(PASTA_DEBUG, exist_ok=True)
            with open(os.path.join(PASTA_DEBUG, "relatorio_lote.json"), "w") as f:
                json.dump({
                    "versao": "2.1 (Visualização Corrigida)",
                    "descricao": "Bolhas verdes desenhadas com coordenadas realmente selecionadas, sem detecção independente",
                    "imagens": len(imagens),
                    "questoes_total": total_questoes_avaliadas,
                    "acertos_total": total_acertos,
                    "precisao_global_pct": round(global_pct, 2),
                    "problemas": problemas,
                    "detalhes": relatorio
                }, f, indent=2)
            print(f"Relatório salvo em: {os.path.join(PASTA_DEBUG, 'relatorio_lote.json')}")
        except Exception as e:
            print(f"  ⚠️ Falha ao salvar relatório: {e}")

if __name__ == '__main__':
    main()
