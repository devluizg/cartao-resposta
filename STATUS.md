# STATUS DO SISTEMA - Leitura de Cartão Resposta
**Última atualização:** 2026-02-19

---

## Resultado Real dos Testes

| Teste | Data | Acertos | Taxa |
|-------|------|---------|------|
| relatorio_rapido (1 coluna, hardcoded) | 2026-02-19 08:59 | 15/96 | 15.6% |
| relatorio_rapido (2 colunas) | 2026-02-19 14:22 | ~28/96 | ~29% |
| relatorio_auto (2 colunas, gabarito fixo) | 2026-02-19 14:32 | 27/96 | **28.1%** |

**Gabarito usado nos testes:** `D C C B C D E E C C B C D C B C C C D E D C B A`
**Configuração:** 24 questões, 2 colunas, sensitivity=0.10

---

## O que foi implementado

### Pré-processamento (`image_processing.py`)
- `melhorar_pre_processamento_adaptativo()` — normalização LAB + CLAHE adaptativo + remoção de sombras
- `corrigir_perspectiva()` — Hough Lines + RANSAC + fallbacks multi-nível, aceita até ~45° de inclinação
- `redimensionar_imagem_otimizada()` — redimensiona automaticamente imagens > 1500px

### Detecção de Bolhas (`image_processing.py`)
- `detectar_bolhas_avancado()` — 4 métodos híbridos combinados:
  - **HoughCircles Adaptativo** — parâmetros ajustados (param1=40, param2=20)
  - **Template Matching com NMS** — antes gerava ~50K círculos falsos; corrigido com dilation+contours → ~100 círculos
  - **MSER** — Maximally Stable Extremal Regions
  - **Contornos** — aceita polígonos de 4 a 8 vértices (era exatamente 4)
- `_aplicar_voting_system()` — threshold = raio * 0.8 (era raio * 0.3)

### Agrupamento por Questão (`image_processing.py`)
- `agrupar_bolhas_por_questoes()`:
  - DBSCAN pré-detecta número natural de linhas antes do KMeans
  - KMeans com `effective_clusters` (linhas naturais detectadas, não num_questoes)
  - Quando cluster tem mais bolhas que o esperado: bucket horizontal equidistante + seleciona melhor por fill_rate

### Análise de Respostas (`analysis.py`)
- Threshold adaptativo: `max(0.15, media + 0.5 * desvio)` (era `max(0.30, media + 0.8 * desvio)`)
- `ERRO_MULTIPLA` → antes retornava "X"; agora escolhe a de maior fill_rate
- **Forced choice** → quando nenhuma bolha passa o threshold, escolhe a de maior fill_rate (elimina "-")
- `analisar_cartao_melhorado()` aceita retângulos de 4-8 vértices para melhor detecção do contorno do cartão

### Scripts de Teste
- `teste_auto.py` — teste não-interativo com gabarito fixo, salva JSON automaticamente
- `test_rapido.py` — teste interativo com gabarito digitado, suporte a múltiplas colunas
- `test_interativo.py` — teste imagem por imagem com comparação manual

---

## Problemas Ativos (ainda não corrigidos)

### 1. Overflow uint16 no voting system
**Arquivo:** `image_processing.py`, linha 525, função `_aplicar_voting_system`
```python
# BUG: circulo[] vem do HoughCircles como uint16; subtração wrapa em vez de dar negativo
dist = np.sqrt((circulo[0] - outro[0])**2 + (circulo[1] - outro[1])**2)
# FIX: converter para int antes
dist = np.sqrt((int(circulo[0]) - int(outro[0]))**2 + (int(circulo[1]) - int(outro[1]))**2)
```

### 2. Margem de 8% cortando Q1
**Arquivo:** `analysis.py`, linhas 594-596, função `analisar_cartao_melhorado`
```python
# BUG: quando o retângulo é detectado corretamente (já exclui o cabeçalho A B C D E),
# a margem de 8% corta a primeira questão real, fazendo Q1 ser detectada errada
margem_topo = int(h * 0.08)
y = min(y + margem_topo, y + h - 1)
h = max(h - margem_topo, 1)
```
Evidência nos testes: Q1 é sempre errada nas 4 imagens (A ou C em vez de D).

### 3. KMeans misturando linhas adjacentes
**Arquivo:** `image_processing.py`, função `agrupar_bolhas_por_questoes`

Quando o KMeans agrupa bolhas de 2 linhas físicas adjacentes no mesmo cluster:
- Ambas têm 1 marcação com fill_rate ~0.97
- Sistema vê "Múltiplas marcações" e escolhe aleatoriamente entre elas
- Resultado: metade das questões fica errada

### 4. Padrão de erro off-by-one nas colunas
**Sintoma observado nos 4 testes mais recentes:**
- Muitas respostas errando por 1 coluna: B quando deveria ser C, C quando deveria ser D
- Possível causa: mapeamento de x-coordenada para letra A/B/C/D/E está deslocado 1 posição
- Pode ser o bucket-index calculado com `int((x - x_min) / largura_grupo)` quando x está no limite entre buckets

---

## Próximos Passos (em ordem de prioridade)

1. **Fix overflow uint16** → `image_processing.py` linha 525 (trivial, 1 linha)
2. **Remover margem 8%** → `analysis.py` linhas 594-596 (remover 3 linhas)
3. **Filtrar bolhas por proximidade y no cluster** → `agrupar_bolhas_por_questoes`: quando cluster tem y-range > raio*2, manter só as mais próximas do centróide y
4. **Investigar off-by-one nas colunas** → adicionar log de x-coords reais vs esperadas para uma imagem de teste; verificar se bucket index está sendo calculado corretamente
