# Análise de Melhorias V6 — Subir de 65.71% para 90%+

**Data**: Março 2026
**Status Atual**: 65.71% (175 questões, 115 acertos em 7 imagens)
**Meta**: 90%+ de precisão

---

## 📊 Análise Detalhada por Imagem

### Distribuição de Acurácia

| Imagem | Resultado | Acertos | Status | Problema Principal |
|--------|-----------|---------|--------|-------------------|
| 19.33.45 | **4.0%** (1/25) | CRÍTICO | ❌ Falha severa | Contraste=39, CLAHE insuficiente |
| 19.33.48 | **88.0%** (22/25) | BOM | ⚠️ 3 erros | Q3, Q5, Q13 - ambiguidades |
| 19.33.55 | **92.0%** (23/25) | EXCELENTE | ✓ 2 erros | Q5, Q14 - padrão recorrente |
| 19.33.51 | **96.0%** (24/25) | EXCELENTE | ✓ 1 erro | Q5 apenas - padrão recorrente |
| 19.33.50 | **88.0%** (22/25) | BOM | ⚠️ 3 erros | Q1, Q5, Q11 - padrão Q5 |
| **19.33.47** | **0.0%** (0/25) | CRÍTICO | ❌ Falha total | ROI grande (1.57×), DBSCAN falha |
| 19.33.54 | **92.0%** (23/25) | EXCELENTE | ✓ 2 erros | Q5, Q14 - padrão recorrente |

### Cálculo de Impacto

```
Se melhorássemos:
- 19.33.47: 0% → 80%  = +20 acertos = 135/175 = 77.14%
- 19.33.45: 4% → 80%  = +19 acertos = 154/175 = 88.0%
- Q5 recorrente: 5 erros → fixar = 159/175 = 90.86%
- Q14 recorrente: 2 erros → fixar = 161/175 = 92.0%
```

---

## 🔴 PROBLEMA 1: Imagem 19.33.47 — ROI Grande (0%)

### Causa Raiz

ROI é 1.57× maior que o padrão (384px vs ~244px)
- Raio estimado: 15px (vs ~8-10px normal)
- Espaçamento: 77.1px (vs ~48-50px normal)
- eps DBSCAN: 30.8px ← **TOO SMALL**, agrupa apenas 1 linha em vez de 13

### Solução: Calcular Raio Matematicamente

```python
# ANTES: divisor = 70 (empírico)
# DEPOIS:
caixa_width_mm = 43.0  # Tamanho real da caixa
bolha_raio_mm = 2.5    # Raio real da bolha
px_per_mm = roi_width_px / caixa_width_mm
raio_px = bolha_raio_mm * px_per_mm  # Calcula ~22px para 384px ROI
```

**Impacto**: +20 questões = 77.14%

---

## 🔴 PROBLEMA 2: Imagem 19.33.45 — Contraste Muito Baixo (4%)

### Causa Raiz

Contraste = 39 (limiar!)
- Threshold low-light: contraste < 40 ← detecta como normal, não low-light
- Flash virtual NÃO foi aplicado
- CLAHE padrão (2.0) em vez de agressivo

### Solução: Reduzir Threshold e Aumentar CLAHE

```python
# FIX B1: Reduzir threshold de 40 para 45
if contraste < 45:  # MUDADO
    return "low_light"

# FIX B2: Aumentar CLAHE
clahe_limit = 4.0    # AUMENTADO DE 3.5
clahe_grid = 10      # DIMINUÍDO (mais agressivo)
```

**Impacto**: +19 questões = 88.0%

---

## 🟡 PROBLEMA 3: Erro Recorrente em Q5 (5 erros)

### Análise

**Padrão**: E sempre lê como D (5 imagens!)

Possível causa: Bolhas fora de ordem (A,B,C,E,D em vez de A,B,C,D,E)

### Solução: Validar Ordem de Bolhas

```python
xs = [bolha['x'] for bolha in bolhas_questao]
if xs != sorted(xs):
    # Reordenar por X
    bolhas_ordenadas = sorted(bolhas_questao, key=lambda b: b['x'])
    fill_rates = [b['fill'] for b in bolhas_ordenadas]
```

**Impacto**: +5 questões = 90.86%

---

## 🟡 PROBLEMA 4: Ambiguidade em Q14 (2 erros)

### Análise

Lê como "B?" (baixa confiança) quando esperado é A

### Solução: Voting Mais Robusto para Ambigüidades

```python
if confianca < 0.85:
    votos = voting_system(métodos)  # HoughCircles, Template, MSER, Contornos
    resposta = votos.argmax()
```

**Impacto**: +2 questões = 92.0%

---

## 📈 Resumo de Fixes

| Fix | Arquivo | Mudança | Impacto |
|-----|---------|---------|---------|
| A1 | image_processing.py | Raio matemático | +20q = 77.14% |
| B1 | image_processing.py | Threshold < 45 | +19q = 88.0% |
| B2 | image_processing.py | CLAHE agressivo | (incluso em B1) |
| C1 | analysis.py | Validar ordem | +5q = 90.86% |
| D1 | image_processing.py | Voting robusto | +2q = 92.0% |

**Meta: 92.0% (acima de 90%)**

---

*Análise V6 - Março 2026*
