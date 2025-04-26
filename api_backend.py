from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import numpy as np
import cv2
import tempfile
from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer, detectar_colunas
from image_processing import melhorar_pre_processamento, corrigir_perspectiva

app = FastAPI()

# Libera o acesso do app Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Instâncias globais dos analisadores
analyzer = CartaoRespostaAnalyzer()
multi_analyzer = MultiColumnCartaoAnalyzer(analyzer)

@app.post("/processar_cartao")
async def processar_cartao(
    file: UploadFile = File(...),
    num_questoes: int = Form(...),
    num_colunas: int = Form(...),
    sensitivity: float = 0.3,
    threshold: int = Form(150)
):
    try:
        # Salva o arquivo temporariamente para leitura com OpenCV
        contents = await file.read()
        np_arr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

        if image is None:
            return JSONResponse(content={"error": "Imagem inválida"}, status_code=400)

        # Pré-processamento
        binary, _ = melhorar_pre_processamento(image)
        corrected_image, corrected_binary, success = corrigir_perspectiva(image, binary)

        if success:
            image = corrected_image
            binary = corrected_binary

        debug_image = image.copy()

        resultados = multi_analyzer.analisar_cartao_multicolunas(
            image, binary, debug_image,
            num_questoes=num_questoes,
            num_colunas=num_colunas,
            sensitivity=sensitivity,
            threshold=threshold
        )

        return {"respostas": resultados}

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
