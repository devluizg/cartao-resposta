import cv2
import numpy as np
from image_processing import melhorar_pre_processamento_adaptativo
import glob

GABARITO_CORRETO = {
    1: 'A', 2: 'B', 3: 'C', 4: 'D', 5: 'E',
    6: 'A', 7: 'B', 8: 'C', 9: 'D', 10: 'E',
    11: 'C', 12: 'A', 13: 'D', 14: 'A', 15: 'B',
    16: 'C', 17: 'D', 18: 'E', 19: 'A', 20: 'A',
    21: 'B', 22: 'D', 23: 'E', 24: 'C', 25: 'C'
}

def custom_preproc(image):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    l_norm = cv2.normalize(l, None, 0, 255, cv2.NORM_MINMAX)
    
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(12, 12))
    l_clahe = clahe.apply(l_norm)
    
    # Shadow correction by division
    # A large median or gaussian blur represents the illumination
    bg = cv2.GaussianBlur(l_clahe, (151, 151), 0)
    # avoid division by zero
    l_corrected_float = (l_clahe.astype(np.float32) / (bg.astype(np.float32) + 1e-5)) * 200
    l_corrected_float = np.clip(l_corrected_float, 0, 255).astype(np.uint8)
    
    filtered = cv2.bilateralFilter(l_corrected_float, 9, 75, 75)
    
    block_size = max(45, int(min(gray.shape) * 0.05))
    if block_size % 2 == 0:
        block_size += 1
        
    binary_adaptive = cv2.adaptiveThreshold(
        filtered, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV, block_size, 10
    )
    
    _, binary_otsu = cv2.threshold(filtered, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    
    # Because illumination is corrected, Otsu shouldn't pick up shadows!
    # So we can safely use bitwise OR
    binary = cv2.bitwise_or(binary_adaptive, binary_otsu)
    
    kernel_open = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    kernel_close = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel_open)
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel_close)
    
    return binary, {}

if __name__ == "__main__":
    from testar_em_lote import agrupar_respostas_str
    from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer
    from image_processing import corrigir_perspectiva, redimensionar_imagem_otimizada
    
    img_path = "test_images/WhatsApp Image 2026-02-19 at 08.16.02212121.jpeg"
    image = cv2.imread(img_path)
    if image is not None:
        image, _ = redimensionar_imagem_otimizada(image)
        binary, _ = custom_preproc(image)
        image_corrected, binary_corrected, success = corrigir_perspectiva(image, binary)
        if success:
            image = image_corrected
            binary = binary_corrected
            
        analyzer = CartaoRespostaAnalyzer()
        multi_analyzer = MultiColumnCartaoAnalyzer(analyzer)
        debug_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        
        resultados, _ = multi_analyzer.analisar_cartao_multicolunas(
            image, binary, debug_image,
            num_questoes=25, num_colunas=2,
            return_debug_image=False,
            sensitivity=0.3, threshold=150
        )
        
        respostas = agrupar_respostas_str(resultados)
        print("Respostas lidas:", respostas)
