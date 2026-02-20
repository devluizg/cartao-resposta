import cv2
import numpy as np
import glob
from testar_em_lote import agrupar_respostas_str
from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer
from image_processing import corrigir_perspectiva, redimensionar_imagem_otimizada

def custom_preproc(image):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)

    l_norm = cv2.normalize(l, None, 0, 255, cv2.NORM_MINMAX)

    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(12, 12))
    l_clahe = clahe.apply(l_norm)

    # 4. Shadow removal com top-hat morphological
    kernel_tophat = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    tophat = cv2.morphologyEx(l_clahe, cv2.MORPH_TOPHAT, kernel_tophat)
    l_corrected = cv2.add(l_clahe, tophat)

    # 5. Bilateral filter 
    filtered = cv2.bilateralFilter(l_corrected.astype(np.uint8), 9, 75, 75)

    # 6. SOMENTE Threshold Adaptativo!
    # Isso lida perfeitamente com sombras. Mas "oca" formas grandes > 45px.
    binary = cv2.adaptiveThreshold(
        filtered, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV, 45, 12
    )

    # PREENCHER FORMAS OCAS (Hollow Shapes)
    # Como o adaptativo oca marcadores de cantos se forem maiores q o bloco,
    # nós usamos os contornos externos e os preenchemos completamente!
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for c in contours:
        area = cv2.contourArea(c)
        if area > 10:  # evitar ruído minúsculo
            # Preenche o contorno pra deixá-lo sólido
            cv2.drawContours(binary, [c], -1, 255, -1)

    # 7. Limpeza morfológica otimizada
    kernel_open = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    kernel_close = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))

    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel_open)
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel_close)

    return binary, {}

GABARITO = {
    1: 'A', 2: 'B', 3: 'C', 4: 'D', 5: 'E',
    6: 'A', 7: 'B', 8: 'C', 9: 'D', 10: 'E',
    11: 'C', 12: 'A', 13: 'D', 14: 'A', 15: 'B',
    16: 'C', 17: 'D', 18: 'E', 19: 'A', 20: 'A',
    21: 'B', 22: 'D', 23: 'E', 24: 'C', 25: 'C'
}

imagens = glob.glob('/home/luiz/cartao-resposta/test_images/*.jpeg')
if not imagens:
    print('No images found!')
    exit(1)

total_acertos = 0
total = 0

for img_path in imagens:
    print(f'Testing {img_path}')
    image = cv2.imread(img_path)
    if image is not None:
        image, _ = redimensionar_imagem_otimizada(image)
        binary, _ = custom_preproc(image)
        image_corrected, binary_corrected, success = corrigir_perspectiva(image, binary)
        if success:
            image = image_corrected
            binary = binary_corrected
        else:
            print("Falha na perspectiva!")
            
        analyzer = CartaoRespostaAnalyzer()
        multi_analyzer = MultiColumnCartaoAnalyzer(analyzer)
        debug_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        
        try:
            resultados = multi_analyzer.analisar_cartao_multicolunas(
                image, binary, debug_image,
                num_questoes=25, num_colunas=2,
                return_debug_image=False,
                sensitivity=0.3, threshold=150
            )
            respostas = agrupar_respostas_str(resultados[0] if isinstance(resultados, tuple) else resultados)
            acertos = 0
            for i in range(1, 26):
                if respostas.get(i) == GABARITO.get(i):
                    acertos += 1
            print(f'Acertos: {acertos}/25')
            total_acertos += acertos
            total += 25
        except Exception as e:
            print('Error during analysis:', e)

print(f"Overall Accuracy: {total_acertos/total*100:.2f}%")
