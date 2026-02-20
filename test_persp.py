import cv2
import glob
from image_processing import redimensionar_imagem_otimizada, corrigir_perspectiva

imagens = glob.glob('/home/luiz/cartao-resposta/test_images/*.jpeg')
if not imagens:
    print('No images')
    exit()

img_path = imagens[0]
print(f'Testing {img_path}')
image = cv2.imread(img_path)
image, _ = redimensionar_imagem_otimizada(image)

gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
l, a, b = cv2.split(lab)
l_norm = cv2.normalize(l, None, 0, 255, cv2.NORM_MINMAX)
clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(12, 12))
l_clahe = clahe.apply(l_norm)
kernel_tophat = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
tophat = cv2.morphologyEx(l_clahe, cv2.MORPH_TOPHAT, kernel_tophat)
l_corrected = cv2.add(l_clahe, tophat)
filtered = cv2.bilateralFilter(l_corrected, 9, 75, 75)
binary_adaptive = cv2.adaptiveThreshold(filtered, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 21, 10)

contours, _ = cv2.findContours(binary_adaptive, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
areas = sorted([cv2.contourArea(c) for c in contours], reverse=True)
print("Top 10 areas:", areas[:10])

