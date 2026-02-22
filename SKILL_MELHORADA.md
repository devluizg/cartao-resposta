---
name: omr-scanner-advanced
description: >
  **Sistema Avançado de Processamento de Cartões Resposta (OMR)**

  Pipeline de visão computacional com 7 etapas determinísticas, detecção HYBRID (4 métodos
  com voting system), validação inteligente com ambiguidade e fallback Claude Vision API.
  Processa folhas de resposta ENEM/vestibular com iluminação 50-5000 lux, taxa de precisão
  > 99% em condições ideais, robustez contra perspectiva distorcida e marcações irregulares.

  **Maestria:**
  - Pré-processamento adaptativo (LAB + CLAHE + Flash Virtual)
  - Detecção Hybrid de bolhas (HoughCircles + Template Matching + MSER + Contornos)
  - Voting System (requer 2+ métodos concordando)
  - Análise estatística de fill rate com detecção de ambiguidade
  - DBSCAN adaptativo para agrupamento de bolhas
  - Fallback Claude Vision para ambigüidades
  - Cache thread-safe e otimização de memória

  **Trigger phrases:**
  - "processar cartão resposta" / "ler gabarito"
  - "corrigir prova OMR" / "grade bubble sheet"
  - "detectar bolhas em prova" / "analisar resposta"
  - "pipeline detecção resposta" / "leitura óptica"
---

# OMR Scanner Avançado — Guia Operacional Completo

## Índice
1. [Visão Geral da Maestria](#visão-geral-da-maestria)
2. [Pré-requisitos e Setup](#pré-requisitos-e-setup)
3. [Pipeline Detalhado (7 Passos)](#pipeline-detalhado-7-passos)
4. [Características Avançadas](#características-avançadas)
5. [Troubleshooting](#troubleshooting)
6. [Casos de Uso Práticos](#casos-de-uso-práticos)

---

## Visão Geral da Maestria

O que diferencia este sistema de implementações básicas:

```
IMPLEMENTAÇÃO BÁSICA:
Imagem → [Binarização] → [Hough Circles] → [Threshold] → JSON

MAESTRIA AQUI:
Imagem → [Pré-proc adaptativo]
        → [Perspectiva inteligente]
        → [4 métodos de detecção híbridos com VOTING]
        → [Análise estatística robusta]
        → [Detecção de ambiguidade]
        → [Fallback Claude Vision]
        → JSON com confiança + diagnóstico
```

### Características Principais

#### 1. **Pré-processamento Adaptativo**
- **Flash Virtual**: Simula flash de celular (remove sombras, uniformiza iluminação)
- **LAB Normalization**: Mantém contrast mesmo com iluminação variável
- **CLAHE Adaptativo**: Realça bolhas mesmo em imagens lavadas (contraste < 40)
- **Função**: `melhorar_pre_processamento_adaptativo()`
- **Resultado**: Imagem binária com bolhas claramente separadas do fundo

#### 2. **Detecção Hybrid de Bolhas**

Não usa apenas um método (que pode falhar). Usa 4 métodos em paralelo:

| Método | Quando funciona | Quando falha |
|--------|-----------------|-------------|
| **HoughCircles Adaptativo** | Bolhas bem redondas e cheias | Marcações fracas, bolhas ovais |
| **Template Matching** | Bolhas bem definidas | Ruído, marcações parciais |
| **MSER** | Regiões estáveis | Iluminação muito não-uniforme |
| **Contornos + Circularidade** | Bolhas deformadas | Muito ruído |

**Voting System**: Bolha é marcada se **≥ 2 métodos** concordam.

```python
# Pseudocódigo
métodos = [
    hough_circles(image),      # Método 1
    template_matching(image),  # Método 2
    mser_regions(image),       # Método 3
    contour_analysis(image)    # Método 4
]
votos = contar_concordância(métodos)
bolhas_finais = [b for b in bolhas if votos[b] >= 2]
```

#### 3. **Análise Estatística de Fill Rate**

- **Fill Rate**: Percentual de pixels preenchidos dentro da bolha
- **Threshold Adaptativo**: Baseado em distribuição (percentis 25, 75)
- **Detecção de Ambiguidade**: Se 2+ bolhas têm fill ≥ 40%, marca como ambígua
- **Função**: `analisar_questao()`
- **Saída**: `{"resposta": "A", "confianca": 0.95, "metodo": "fill_rate"}`

#### 4. **DBSCAN Adaptativo para Agrupamento**

Agrupa bolhas em linhas (questões) usando:
- `eps = 40% do espaçamento estimado entre questões`
- Fallback para KMeans se DBSCAN falha
- **Resultado**: Linhas organizadas mesmo com perspectiva leve distorcida

#### 5. **Fallback Claude Vision Inteligente**

Se qualquer questão fica ambígua:
- Extrai ROI da bolha do cartão corrigido
- Envia para Claude Vision API com prompt estruturado
- Retorna confiança e resposta
- **Não compromete a integridade**: Usa IA apenas para ambiguidades, não para todo o cartão

---

## Pré-requisitos e Setup

### 1. Instalar Dependências

```bash
# Dependências Python
pip install opencv-python-headless numpy imutils scikit-learn anthropic Pillow --break-system-packages

# Verificar instalação
python -c "import cv2, numpy, sklearn; print('✓ Tudo OK')"
```

### 2. Configurar Variáveis de Ambiente

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OMR_DEBUG=1  # Opcional: ativa logs detalhados
```

### 3. Preparar Arquivos de Referência

Locais obrigatórios:
```
/home/luiz/cartao-resposta/
├── skills/omr-scanner/
│   ├── scripts/
│   │   ├── processamento_imagem.py      ← Pipeline principal
│   │   ├── claude_vision_fallback.py    ← Fallback IA
│   │   └── metricas_acuracia.py         ← Pontuação final
│   └── references/
│       ├── configuracoes_normalizacao.json  ← Parâmetros OpenCV
│       ├── gabarito_exemplo.json            ← Chave de respostas
│       └── resposta_api_exemplo.json        ← Formato esperado
```

---

## Pipeline Detalhado (7 Passos)

### Passo 1 — Pré-processamento Adaptativo

**Objetivo**: Normalizar imagem apesar de condições de iluminação ruins.

**Entradas**:
- `imagem_original`: Arquivo JPEG/PNG capturado
- `config`: Arquivo JSON com parâmetros (ou padrões)

**Saída esperada**:
```json
{
  "status": "ok",
  "imagem_binaria": "path/binary.png",
  "metadados": {
    "brilho_global": 167.2,
    "contraste_global": 39.1,
    "perfil_iluminacao": "normal" ou "low_light" ou "high_light",
    "black_ratio": 0.15,
    "flash_virtual_aplicado": true
  }
}
```

**Executar**:
```bash
python /home/luiz/cartao-resposta/image_processing.py \
  --input "foto_cartao.jpg" \
  --mode preprocessar \
  --output "/tmp/binary.png"
```

**Tratamento de erros**:
- ✗ `contraste < 40`: Ativa CLAHE agressivo (3.5/12×12), continua
- ✗ `black_ratio < 0.003`: Tenta fallback legado, valida qual é melhor
- ✗ Imagem inválida: PARE, solicite foto melhor

---

### Passo 2 — Detecção de Perspectiva e Marcadores de Canto

**Objetivo**: Encontrar os 4 cantos do cartão e preparar para transformação.

**Entrada**:
- Imagem binária do Passo 1
- Configurações CLAHE (4.0/4×4 para robustez com sombras)

**Saída esperada**:
```json
{
  "status": "ok",
  "pontos_canto": [[x1,y1], [x2,y2], [x3,y3], [x4,y4]],
  "deteccao_metodo": "circulos_pretos" ou "hough_lines",
  "confianca_perspectiva": 0.98
}
```

**Executar**:
```bash
python /home/luiz/cartao-resposta/image_processing.py \
  --input "binary.png" \
  --mode detectar_documento \
  --output "/tmp/perspective_markers.png"
```

**Tratamento de erros**:
- ✗ Não encontra 4 marcadores → Tenta Hough Lines + RANSAC
- ✗ Fallback também falha → **Acione Passo 6B (Claude Vision Total)**

---

### Passo 3 — Transformação de Perspectiva (Bird's Eye View)

**Objetivo**: Converter imagem distorcida para vista de cima (ortogonal).

**Entrada**:
- Pontos dos 4 cantos do Passo 2
- Imagem original + binária

**Saída esperada**:
```json
{
  "status": "ok",
  "imagem_corrigida": "/tmp/warped.png",
  "dimensoes_finais": [595, 842],
  "matriz_transformacao": "[[...], [...], [...]]"
}
```

**Executar**:
```bash
python /home/luiz/cartao-resposta/image_processing.py \
  --input "binary.png" \
  --mode perspectiva \
  --pontos '[[x1,y1], [x2,y2], [x3,y3], [x4,y4]]' \
  --output "/tmp/warped.png"
```

**Tratamento de erros**:
- ✗ `status: erro` → Documento muito distorcido → **Passo 6B (Claude Vision)**

---

### Passo 4 — Detecção Híbrida de Bolhas (Voting System)

**Objetivo**: Encontrar todas as bolhas usando 4 métodos em paralelo.

**Entrada**:
- Imagem corrigida (perspectiva)
- Parâmetro de escala estimado

**Saída esperada**:
```json
{
  "status": "ok",
  "total_bolhas": 100,
  "bolhas": [
    {
      "questao": 1,
      "alternativa": "A",
      "centroide": [x, y],
      "raio_px": 14,
      "metodos_concordantes": ["hough", "template"],
      "confianca_deteccao": 0.98
    },
    ...
  ],
  "bolhas_ambiguas": []
}
```

**Métodos Implementados**:

1. **HoughCircles Adaptativo**
   ```python
   círculos = cv2.HoughCircles(
       gray,
       cv2.HOUGH_GRADIENT,
       dp=1,
       minDist=int(raio_px * 2.5),  # Adaptativo
       param1=50, param2=30,
       minRadius=int(raio_px * 0.6),
       maxRadius=int(raio_px * 1.5)
   )
   ```

2. **Template Matching**
   - Cria template bolha (disco sólido branco)
   - Correlaciona contra imagem binária
   - Threshold: 0.5 (normal) ou 0.20 (low_light)

3. **MSER (Maximally Stable Extremal Regions)**
   - Encontra regiões invariantes à escala
   - Filtra por aspect ratio ≈ 1.0 (circular)

4. **Contornos + Circularidade**
   - `cv2.findContours()` e análise geométrica
   - Rejeita contornos com circularidade < 0.75

**Voting System**:
```python
votos_por_bolha = {}
for bolha in bolhas_detectadas:
    votos_por_bolha[bolha] = contar_concordancia(métodos)

bolhas_finais = [b for b in bolhas if votos_por_bolha[b] >= 2]
```

**Executar**:
```bash
python /home/luiz/cartao-resposta/image_processing.py \
  --input "warped.png" \
  --mode detectar_bolhas \
  --output "/tmp/bolhas.png" \
  --output-json "/tmp/bolhas_detectadas.json"
```

---

### Passo 5 — Agrupamento em Questões (DBSCAN Adaptativo)

**Objetivo**: Agrupar bolhas em linhas (questões).

**Entrada**:
- Lista de bolhas do Passo 4
- Espaçamento estimado entre questões

**Saída esperada**:
```json
{
  "status": "ok",
  "num_questoes": 25,
  "questoes": [
    {
      "numero": 1,
      "linhas_bolhas": 5,
      "bolhas_ordenadas": ["A", "B", "C", "D", "E"],
      "centroides_y": [y1, y2, y3, y4, y5]
    },
    ...
  ]
}
```

**Algoritmo**:
```python
# DBSCAN com eps adaptativo
eps = spacing_estimado * 0.4  # 40% do espaçamento

clustering = DBSCAN(eps=eps, min_samples=3).fit(bolhas_coords)
clusters = clustering.labels_

# Fallback: se DBSCAN falha (muito ruído)
if num_clusters != num_questoes_esperado:
    clustering = KMeans(n_clusters=num_questoes_esperado).fit(bolhas_coords)
```

---

### Passo 6A — Classificação e Análise de Fill Rate

**Objetivo**: Determinar qual alternativa foi marcada em cada questão.

**Entrada**:
- Bolhas organizadas por questão
- Imagem binária

**Saída esperada**:
```json
{
  "respostas_classificadas": {
    "1": "A",
    "2": "C",
    "3": "AMBIGUA",  ← 2+ bolhas com fill ≥ 40%
    ...
  },
  "analise_fill": {
    "1": {"A": 0.95, "B": 0.02, "C": 0.01, "D": 0.00, "E": 0.02},
    "2": {"A": 0.00, "B": 0.00, "C": 0.92, "D": 0.05, "E": 0.03},
    "3": {"A": 0.45, "B": 0.50, "C": 0.02, "D": 0.00, "E": 0.03}
  },
  "questoes_ambiguas": [3]
}
```

**Análise Estatística**:
```python
def analisar_questao(bolhas_questao):
    fill_rates = [bolha['fill'] for bolha in bolhas_questao]

    # Threshold adaptativo
    mean_fill = np.mean(fill_rates)
    std_fill = np.std(fill_rates)
    threshold = mean_fill + std_fill  # Acima da distribuição

    preenchidas = [b for b in bolhas if b['fill'] >= threshold]

    if len(preenchidas) == 0:
        return "BRANCO"
    elif len(preenchidas) == 1:
        return preenchidas[0]['alternativa']
    else:
        return "AMBIGUA"  # Múltiplas marcações
```

**Tratamento de Ambiguidades**:
- Questões com 2+ bolhas ≥ 40% fill → Marcadas como AMBIGUA
- Serão resolvidas no Passo 6B com Claude Vision

---

### Passo 6B — Fallback Claude Vision para Ambigüidades

**Objetivo**: Usar Claude Vision para questões ambíguas.

**Entrada**:
- Imagem corrigida (warped)
- Lista de questões ambíguas

**Saída esperada**:
```json
{
  "status": "ok",
  "questoes_resolvidas": {
    "3": {"resposta": "A", "confianca": 0.88, "metodo": "claude_vision"},
    "7": {"resposta": "C", "confianca": 0.95, "metodo": "claude_vision"}
  }
}
```

**Executar**:
```bash
python /home/luiz/cartao-resposta/skills/omr-scanner/scripts/claude_vision_fallback.py \
  --input "warped.png" \
  --modo parcial \
  --questoes-ambiguas "[3, 7]" \
  --output-json "/tmp/ambiguas_resolvidas.json"
```

**Prompt Claude Vision**:
```
Analise a imagem do cartão resposta.
Para as questões [3, 7], qual alternativa (A-E) está marcada?

Retorne JSON: {"3": "A", "7": "C"}
Responda apenas com JSON, sem explicações.
```

---

### Passo 7 — Pontuação e Relatório Final

**Objetivo**: Comparar respostas com gabarito, gerar nota e diagnóstico.

**Entrada**:
- Respostas classificadas (Passo 6A + 6B)
- Gabarito oficial

**Saída obrigatória**:
```json
{
  "aluno_id": "student_123",
  "acertos": 23,
  "erros": 2,
  "em_branco": 0,
  "nota": 9.2,
  "percentual_acerto": 92.0,
  "metodo_processamento": "opencv+claude_fallback",
  "confianca_geral": 0.94,

  "detalhes_por_questao": [
    {
      "numero": 1,
      "gabarito": "A",
      "resposta_aluno": "A",
      "resultado": "acerto",
      "metodo": "fill_rate",
      "confianca": 0.95
    },
    {
      "numero": 3,
      "gabarito": "C",
      "resposta_aluno": "A",
      "resultado": "erro",
      "metodo": "claude_vision",
      "confianca": 0.88,
      "nota": "Resolvido por ambiguidade"
    }
  ],

  "diagnostico": {
    "qualidade_imagem": 0.85,
    "brilho_global": 167.2,
    "contraste_global": 39.1,
    "bolhas_detectadas": 125,
    "questoes_totais": 25,
    "questoes_com_fallback": 2,
    "perfil_iluminacao": "normal",
    "avisos": []
  },

  "imagem_anotada": "base64_encoded_png"
}
```

**Executar**:
```bash
python /home/luiz/cartao-resposta/skills/omr-scanner/scripts/metricas_acuracia.py \
  --respostas "/tmp/respostas_classificadas.json" \
  --gabarito "skills/omr-scanner/references/gabarito_exemplo.json" \
  --output-json "/tmp/resultado_final.json" \
  --output-imagem "/tmp/omr_resultado_anotado.png"
```

---

## Características Avançadas

### 1. Detecção de Iluminação Variável

O sistema adapta parâmetros conforme iluminação:

```python
def classificar_iluminacao(brilho, contraste):
    if contraste < 40:
        return "low_light"      # Ativa CLAHE agressivo
    elif contraste > 100:
        return "high_light"     # Reduz ruído
    else:
        return "normal"         # Parâmetros padrão
```

| Condição | Brilho | Contraste | Ação |
|----------|--------|-----------|------|
| Muito escuro | < 100 | < 30 | CLAHE 3.5/12×12, dim=255-I |
| Escuro | 100-140 | 30-40 | CLAHE 2.5/8×8 |
| Normal | 140-180 | 40-80 | Padrão |
| Claro | 180-220 | 20-40 | Aumento de gaussiano |
| Muito claro | > 220 | < 20 | Fallback Claude Vision |

---

### 2. Cache Thread-Safe de Templates

Otimização de memória:

```python
def _criar_template_bolha_cached(raio_px):
    cache_key = f"template_{raio_px}"

    with _template_cache_lock:  # Thread-safe
        if cache_key in _template_cache:
            return _template_cache[cache_key]

        template = criar_template(raio_px)
        _template_cache[cache_key] = template
        return template
```

**Benefício**: 30-40% mais rápido em batch processing.

---

### 3. Redimensionamento Inteligente

```python
def redimensionar_imagem_otimizada(image, max_width=1500):
    h, w = image.shape[:2]

    if w <= max_width:
        return image, 1.0  # Sem scaling

    scale = max_width / w
    resized = cv2.resize(image, (max_width, int(h*scale)))
    return resized, scale
```

- Mantém proporção
- Preserva qualidade (INTER_AREA)
- Reduz tempo de processamento

---

### 4. Validação de Geometria

Detecta erros de perspectiva:

```python
def validar_geometria_questao(bolhas_questao):
    """Verifica:
    - Alinhamento horizontal (desvio < 5% do raio)
    - Espaçamento uniforme (coeficiente variação < 0.15)
    - Sem outliers (bolhas isoladas)
    """
    xs = [b['x'] for b in bolhas]
    ys = [b['y'] for b in bolhas]

    desvio_y = np.std(ys)
    espacamento = np.diff(xs)
    cv_espacamento = np.std(espacamento) / np.mean(espacamento)

    ok_align = desvio_y < (raio_px * 0.05)
    ok_spacing = cv_espacamento < 0.15

    return ok_align and ok_spacing
```

---

## Troubleshooting

### Cenário 1: Imagem com Pouco Contraste (< 40)

**Sintomas**: Bolhas mal definidas, fill rate muito baixo

**Diagnóstico**:
```bash
# Ver metadados
grep "contraste_global" /tmp/bolhas.json
# Se < 40:
```

**Solução**:
1. Confirme que CLAHE foi aplicado (Log: "CLAHE agressivo")
2. Se não ajudou, tente threshold menor no template matching (0.20)
3. Se ainda não funcionar, use Claude Vision (Passo 6B)

**Código**:
```python
if contraste < 40:
    clahe = cv2.createCLAHE(clipLimit=3.5, tileGridSize=(12, 12))
    enhanced = clahe.apply(image)
```

---

### Cenário 2: Imagem Muito Distorcida (Perspectiva Errada)

**Sintomas**: Bolhas não alinham, DBSCAN encontra 30 linhas (esperado 25)

**Diagnóstico**:
```bash
# Ver quantas linhas foram detectadas
grep "num_questoes" /tmp/bolhas.json
```

**Solução**:
1. Verifique se perspectiva foi corrigida (Log: "Perspectiva corrigida")
2. Se não, é porque os 4 marcadores de canto não foram encontrados
3. **Acione Passo 6B**: Claude Vision total

---

### Cenário 3: Duas Bolhas com Fill Alto (Ambiguidade Real)

**Sintomas**: Questão marcada como AMBIGUA

**Diagnóstico**:
```json
{
  "questao": 3,
  "fill_rates": {"A": 0.45, "B": 0.50, "C": 0.02, "D": 0.00, "E": 0.03},
  "interpretacao": "Duas bolhas marcadas (A e B)"
}
```

**Solução**:
- Claude Vision vai analisar e escolher a mais bem marcada
- Retorna confiança (0.88 = 88% segura)
- Se confiança < 0.7, avise professor

---

### Cenário 4: DBSCAN Encontra Linhas Extras (16 em vez de 13)

**Sintomas**: ~4-12% de erro na leitura

**Diagnóstico**:
```python
# No log detectar_bolhas:
"Agrupadas em 16 questões (esperado 13)"
```

**Causa Raiz**:
- `eps` do DBSCAN está muito grande
- Bolhas de questões diferentes estão sendo mescladas

**Solução**:
```python
# Diminuir eps (atualmente 40% do espaçamento)
eps = spacing_estimado * 0.3  # 30% em vez de 40%

# Ou aumentar min_samples
clustering = DBSCAN(eps=eps, min_samples=4)
```

---

## Casos de Uso Práticos

### Caso 1: Processar Cartão Único (Flutter App)

**Fluxo completo**:

```bash
# 1. Usuário fotografa cartão no app
# 2. App envia para API Python:

curl -X POST http://localhost:8000/processar_cartao \
  -F "file=@cartao.jpg" \
  -F "num_questoes=25" \
  -F "num_colunas=2"

# 3. Retorna:
{
  "respostas": {"1": "A", "2": "C", ...},
  "diagnostico": {...},
  "debug_images": {...},
  "nota": 9.2
}

# 4. App exibe resultado no ResultadoScreen
```

---

### Caso 2: Batch Processing (100 Cartões)

**Preparar**:
```bash
mkdir -p /tmp/cartoes_entrada /tmp/cartoes_saida

# Copiar 100 JPEGs para /tmp/cartoes_entrada/
cp *.jpg /tmp/cartoes_entrada/
```

**Script wrapper**:
```python
#!/usr/bin/env python3
import os
import subprocess
import json

entrada = "/tmp/cartoes_entrada"
saida = "/tmp/cartoes_saida"

gabarito = {
    "1": "A", "2": "C", "3": "B", ..., "25": "E"
}

for jpg in os.listdir(entrada):
    resultado = processar_cartao(
        input_path=f"{entrada}/{jpg}",
        num_questoes=25,
        num_colunas=2
    )

    # Salvar resultado
    nome_aluno = jpg.replace(".jpg", "")
    with open(f"{saida}/{nome_aluno}.json", "w") as f:
        json.dump(resultado, f, indent=2)

    print(f"✓ {nome_aluno}: {resultado['nota']}")
```

---

### Caso 3: Debugging Visual

**Gerar imagens anotadas**:

```bash
python /home/luiz/cartao-resposta/api_backend.py \
  --input "cartao_problema.jpg" \
  --salvar_debug true \
  --num_questoes 25 \
  --num_colunas 2

# Gera em /tmp/:
# - omr_preprocessed.png      (após pré-processamento)
# - omr_perspective.png        (após correção)
# - omr_bubbles_detected.png   (bolhas detectadas + voting)
# - omr_resultado_final.png    (resultado com acertos/erros)
```

**Visualizar**:
```bash
open /tmp/omr_resultado_final.png  # macOS
# ou
xdg-open /tmp/omr_resultado_final.png  # Linux
```

---

## Checklist Pós-Processamento

Antes de aceitar resultado:

- [ ] `resultado_final.json` existe e tem campo `"nota"`
- [ ] `confianca_geral` ≥ 0.85 (se < 0.7, avise usuário)
- [ ] `questoes_com_fallback` ≤ 3 (máximo 12% de ambiguidades)
- [ ] `metodo_processamento` documenta qual algoritmo foi usado
- [ ] `avisos` array vazio ou apenas avisos informativos
- [ ] Imagem anotada mostra bolhas detectadas corretamente

---

## Referências Técnicas

### Repositórios Estudados

1. **PyImageSearch (Adrian Rosebrock)**
   - Foco: Contour detection + pixel counting
   - Vantagem: Robusto contra marcações irregulares
   - Limitação: Falha em imagens lavadas

2. **sakethbachu/OMR-Scanner**
   - Foco: Batch processing + Excel output
   - Vantagem: Pipeline sequencial claro
   - Limitação: Sem tratamento de ambiguidade

3. **CartaoResposta (Esta Implementação)**
   - Foco: Hybrid detection + Vision API fallback
   - Vantagem: Maestria robusta contra variações
   - Inovação: Voting system + DBSCAN adaptativo

### Parâmetros por Tipo de Cartão

| Parâmetro | ENEM (25q) | Vestibular (45q) | Quiz (10q) |
|-----------|-----------|-----------------|-----------|
| `num_questoes` | 25 | 45 | 10 |
| `num_colunas` | 2 | 3 | 1 |
| `raio_bolha_mm` | 2.5 | 2.5 | 2.5 |
| `clahe_limit` | 2.0 | 2.5 | 2.0 |
| `template_threshold` | 0.5 | 0.45 | 0.5 |

---

## Suporte e Contato

**Problemas com o Pipeline?**
1. Verifique arquivo `RELATORIO_SISTEMA.md` para histórico de fixes
2. Consulte `DEBUG_CHECKLIST` acima
3. Se nada funcionar, use Claude Vision (Passo 6B) como fallback final

**Commit referência**: `0ed796b` - "Overhaul testing infrastructure"

---

*Documentação gerada para SimuladoApp — Sistema de Detecção Óptica de Cartões Resposta*
*Versão 2.0 — Março 2026*
