from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import numpy as np
import cv2
import os
from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer, detectar_colunas

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

@app.post("/processar_cartao")
async def processar_cartao(
    file: UploadFile = File(...),
    num_questoes: int = Form(...),
    num_colunas: int = Form(...),
    threshold: int = Form(150),
    sensitivity: float = Form(0.3),
    retornar_imagens: str = Form("false"),
    auto_detect: bool = Form(False)
):
    try:
        # Salva o arquivo temporariamente para leitura com OpenCV
        contents = await file.read()
        np_arr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

        if image is None:
            return JSONResponse(content={"error": "Imagem inválida"}, status_code=400)

        # Usar exatamente o mesmo fluxo de processamento do Tkinter
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        _, binary = cv2.threshold(blurred, threshold, 255, cv2.THRESH_BINARY_INV)
        
        kernel = np.ones((3, 3), np.uint8)
        binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)
        
        debug_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        
        if auto_detect:
            detected_cols = detectar_colunas(binary)
            num_colunas = detected_cols
        
        # Usar a mesma função e parâmetros exatos do tkinter
        resultados, debug_image_with_marks = multi_analyzer.analisar_cartao_multicolunas(
            image, binary, debug_image,
            num_questoes=num_questoes,
            num_colunas=num_colunas,
            sensitivity=float(sensitivity),
            threshold=threshold,
            return_debug_image=True
        )
        
        response_data = {"respostas": resultados}
        
        # Verificar se deve retornar as imagens processadas
        if retornar_imagens.lower() == "true":
            import base64
            
            # Converter imagem de processamento para BGR antes de codificar (OpenCV usa BGR)
            debug_image_opencv = cv2.cvtColor(debug_image_with_marks, cv2.COLOR_RGB2BGR)
            _, img_encoded_debug = cv2.imencode('.png', debug_image_opencv)
            img_debug_base64 = base64.b64encode(img_encoded_debug).decode('utf-8')
            
            # Garantir que binary seja uma imagem de 8 bits para salvar corretamente
            _, img_encoded_binary = cv2.imencode('.png', binary)
            img_binary_base64 = base64.b64encode(img_encoded_binary).decode('utf-8')
            
            # Adicionar à resposta
            response_data["imagem_processada_base64"] = img_debug_base64
            response_data["imagem_binaria_base64"] = img_binary_base64
        
        return response_data

    except Exception as e:
        import traceback
        error_detail = traceback.format_exc()
        return JSONResponse(content={"error": str(e), "detail": error_detail}, status_code=500)