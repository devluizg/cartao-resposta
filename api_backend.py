from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import numpy as np
import cv2
import os
import base64
import json
from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer, detectar_colunas
from image_processing import (
    melhorar_pre_processamento_adaptativo,
    corrigir_perspectiva,
    validar_geometria_questao,
    agrupar_bolhas_por_questoes,
    redimensionar_imagem_otimizada,
    limpar_cache_templates
)

app = FastAPI()

# Libera o acesso do app Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Instâncias globais dos analisadores - exatamente como no tkinter
analyzer = CartaoRespostaAnalyzer()
multi_analyzer = MultiColumnCartaoAnalyzer(analyzer)

def _converter_imagem_para_base64(imagem, formato='png'):
    """Converte uma imagem OpenCV para base64."""
    try:
        _, img_encoded = cv2.imencode(f'.{formato}', imagem)
        return base64.b64encode(img_encoded).decode('utf-8')
    except:
        return None

@app.post("/processar_cartao")
async def processar_cartao(
    file: UploadFile = File(...),
    num_questoes: int = Form(...),
    num_colunas: int = Form(...),
    threshold: int = Form(150),
    sensitivity: float = Form(0.3),
    retornar_imagens: str = Form("false"),
    retornar_debug: str = Form("false"),
    auto_detect: bool = Form(False),
    salvar_debug: bool = Form(False)
):
    try:
        # Salvar arquivo e ler com OpenCV
        contents = await file.read()
        np_arr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

        if image is None:
            return JSONResponse(content={"error": "Imagem inválida"}, status_code=400)

        # === OTIMIZAÇÃO: Redimensionar imagem se muito grande ===
        image, scale_factor = redimensionar_imagem_otimizada(image)

        h, w = image.shape[:2]

        # === ETAPA 1: Pré-processamento Adaptativo ===
        binary, preproc_metadata = melhorar_pre_processamento_adaptativo(image)

        # Fallback: se a binarização ficou pobre (poucos pixels pretos),
        # tentar o pré-processamento legado e escolher o melhor resultado.
        try:
            black_ratio = float(preproc_metadata.get('black_ratio', 0.0))
            if black_ratio < 0.003:
                binary_alt, _ = melhorar_pre_processamento(image)
                br_alt = float(np.mean(binary_alt > 0))
                if br_alt > black_ratio:
                    print(f"  ⚠️ Fallback preproc: black_ratio {black_ratio:.4f} -> {br_alt:.4f}")
                    binary = binary_alt
                    preproc_metadata['fallback_preproc'] = 'legacy'
                    preproc_metadata['black_ratio'] = br_alt
        except Exception as e:
            print(f"  ⚠️ Fallback preproc falhou: {e}")

        debug_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        debug_preprocessed = binary.copy()

        # === ETAPA 2: Correção de Perspectiva ===
        image_corrected, binary_corrected, correction_success = corrigir_perspectiva(image, binary)
        if correction_success:
            image = image_corrected
            binary = binary_corrected

        debug_perspective = binary.copy()

        # === ETAPA 3: Auto-detecção de colunas (se habilitada) ===
        if auto_detect:
            num_colunas = detectar_colunas(binary)

        # === ETAPA 4: Análise principal ===
        resultados, debug_image_with_marks = multi_analyzer.analisar_cartao_multicolunas(
            image, binary, debug_image,
            num_questoes=num_questoes,
            num_colunas=num_colunas,
            sensitivity=float(sensitivity),
            threshold=threshold,
            return_debug_image=True,
            quality_meta=preproc_metadata
        )

        # === ETAPA 5: Cálculo de métricas de qualidade ===
        # Validar geometria de cada questão
        questoes_agrupadas = agrupar_bolhas_por_questoes(
            [],  # Será atualizado se conseguirmos as bolhas
            num_questoes, 5
        )

        # Estatísticas das respostas
        respostas_detectadas = sum(1 for r in resultados.values() if r is not None)
        # Baixa confiança acumulada pelo CartaoRespostaAnalyzer durante a análise
        questoes_com_baixa_confianca = list(getattr(analyzer, 'ultima_baixa_confianca', []))
        warnings = []

        # Calcular distribuição de respostas
        distribuicao = {}
        for r in resultados.values():
            if r is not None and not isinstance(r, str):
                letra = r[0] if isinstance(r, str) else r
                distribuicao[letra] = distribuicao.get(letra, 0) + 1

        # Verificar distribuição desequilibrada
        if distribuicao:
            media_dist = np.mean(list(distribuicao.values()))
            for letra, count in distribuicao.items():
                if count > media_dist * 2:
                    warnings.append(f"Alternativa '{letra}' aparece {count} vezes (distribuição desequilibrada)")

        # Construir resposta estruturada
        diagnostico = {
            "qualidade_imagem": float(preproc_metadata.get('contrast', 0.0) / 255.0),
            "qualidade_perspectiva": 1.0 if correction_success else 0.5,
            "qualidade_deteccao": float(min(respostas_detectadas / max(num_questoes, 1), 1.0)),
            "bolhas_detectadas": respostas_detectadas,
            "questoes_totais": num_questoes,
            "colunas_detectadas": num_colunas,
            "perfil_iluminacao": preproc_metadata.get('illumination_profile', 'unknown'),
            "brilho_global": float(preproc_metadata.get('brightness', 0.0)),
            "contraste_global": float(preproc_metadata.get('contrast', 0.0)),
            "questoes_com_baixa_confianca": questoes_com_baixa_confianca,
            "warnings": warnings,
            "distribuicao_respostas": distribuicao
        }

        response_data = {
            "respostas": resultados,
            "diagnostico": diagnostico
        }

        if retornar_debug.lower() == "true":
            response_data["preproc_metadata"] = preproc_metadata

        # === ETAPA 6: Adicionar imagens de debug (se solicitado) ===
        if retornar_imagens.lower() == "true":
            debug_images = {}

            # Pré-processamento
            img_preprocessed_bgr = cv2.cvtColor(debug_preprocessed, cv2.COLOR_GRAY2BGR)
            debug_images["pre_processamento"] = _converter_imagem_para_base64(img_preprocessed_bgr)

            # Perspectiva corrigida
            img_perspective_bgr = cv2.cvtColor(debug_perspective, cv2.COLOR_GRAY2BGR)
            debug_images["perspectiva_corrigida"] = _converter_imagem_para_base64(img_perspective_bgr)

            # Resultado final
            debug_images["resultado_final"] = _converter_imagem_para_base64(cv2.cvtColor(debug_image_with_marks, cv2.COLOR_RGB2BGR))

            response_data["debug_images"] = debug_images

        # === ETAPA 7: Salvar debug local (opcional) ===
        if salvar_debug:
            try:
                os.makedirs("debug_runs", exist_ok=True)
                run_id = f"{int(cv2.getTickCount())}"

                cv2.imwrite(f"debug_runs/{run_id}_binary.png", binary)
                cv2.imwrite(f"debug_runs/{run_id}_preproc.png", cv2.cvtColor(debug_preprocessed, cv2.COLOR_GRAY2BGR))
                cv2.imwrite(f"debug_runs/{run_id}_persp.png", cv2.cvtColor(debug_perspective, cv2.COLOR_GRAY2BGR))
                cv2.imwrite(f"debug_runs/{run_id}_resultado.png", cv2.cvtColor(debug_image_with_marks, cv2.COLOR_RGB2BGR))

                with open(f"debug_runs/{run_id}_meta.json", "w") as f:
                    json.dump({
                        "diagnostico": diagnostico,
                        "preproc_metadata": preproc_metadata,
                        "num_questoes": num_questoes,
                        "num_colunas": num_colunas
                    }, f, indent=2)

                response_data["debug_id"] = run_id
            except Exception as e:
                print(f"  ⚠️ Falha ao salvar debug local: {e}")

        # Log estruturado
        print("\n" + "="*60)
        print("ANÁLISE COMPLETA - CARTÃO RESPOSTA")
        print("="*60)
        print(f"Imagem: {w}x{h} pixels")
        print(f"Questões: {num_questoes} | Colunas: {num_colunas}")
        print(f"Iluminação: {preproc_metadata.get('illumination_profile')} (brilho={preproc_metadata.get('brightness', 0):.0f})")
        print(f"Respostas detectadas: {respostas_detectadas}/{num_questoes}")
        print(f"Distribuição: {distribuicao}")
        if warnings:
            print("Warnings:")
            for w_msg in warnings:
                print(f"  ⚠️  {w_msg}")
        print("="*60 + "\n")

        return response_data

    except Exception as e:
        import traceback
        error_detail = traceback.format_exc()
        print(f"❌ ERRO: {str(e)}")
        print(error_detail)
        return JSONResponse(content={"error": str(e), "detail": error_detail}, status_code=500)

@app.get("/diagnosticar")
async def endpoint_diagnosticar():
    """
    Endpoint de diagnóstico para verificar status da API.
    """
    return {
        "status": "ok",
        "versao": "2.0",
        "features": [
            "pré-processamento_adaptativo",
            "correcao_perspectiva_robusta",
            "deteccao_hibrida_bolhas",
            "validacao_geometrica",
            "analise_avancada_preenchimento",
            "multiplas_colunas"
        ]
    }

if __name__ == "__main__":
    import uvicorn
    # O host 0.0.0.0 libera o acesso externo (essencial pro Docker)
    uvicorn.run(app, host="0.0.0.0", port=8000)
