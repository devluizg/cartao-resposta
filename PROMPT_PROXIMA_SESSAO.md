# Prompt para Próxima Sessão

Cole esse texto no início de uma nova conversa com o Claude Code.

---

## Contexto do Projeto

Estou trabalhando em um sistema Python de leitura automática de cartão-resposta usando OpenCV. O projeto está em `/home/luiz/cartao-resposta/`.

**Taxa de acerto atual: 28.1%** (27/96 questões) — precisa chegar perto de 90%+.

O gabarito real dos cartões de teste é: `D C C B C D E E C C B C D C B C C C D E D C B A`
(24 questões, 2 colunas de 12, nenhuma questão em branco, nenhuma marcada duas vezes)

---

## Arquivos Importantes

### `image_processing.py` (1230 linhas) — pipeline principal de detecção
Funções relevantes para os bugs:
- **`_aplicar_voting_system()`** — linha 497: combina detecções dos 4 métodos por proximidade
- **`agrupar_bolhas_por_questoes()`** — linha 630: agrupa bolhas em linhas de questões via KMeans
- **`detectar_bolhas_avancado()`** — linha 542: orquestra os 4 métodos de detecção
- **`analisar_cartao_melhorado()`** — linha 1181: detecta o retângulo do cartão e extrai ROI

### `analysis.py` (856 linhas) — análise de preenchimento e mapeamento resposta→letra
Funções relevantes:
- **`analisar_gabarito()`** — linha 198: mapeia bolhas preenchidas → letras A/B/C/D/E
- **`MultiColumnCartaoAnalyzer`** — linha 675: divide imagem em N colunas, processa cada uma
- **`segmentar_colunas_com_bordas()`** — linha 335: faz o corte horizontal da imagem

### `teste_auto.py` (206 linhas) — script de teste não-interativo
```bash
python3 teste_auto.py  # roda com gabarito DCCBCDEECCBCDCBCCCDEDCBA, 24q, 2 colunas
```
Salva resultado em `relatorio_auto_YYYYMMDD_HHMMSS.json`.

### `test_unified/` — pasta com 4 imagens JPEG reais de cartões para teste

---

## 4 Bugs a Corrigir (em ordem de prioridade)

### Bug 1 — Overflow uint16 no voting system
**Arquivo:** `image_processing.py`, linha 525, dentro de `_aplicar_voting_system()`

```python
# CÓDIGO ATUAL (com bug):
dist = np.sqrt((circulo[0] - outro[0])**2 + (circulo[1] - outro[1])**2)

# CORREÇÃO: HoughCircles retorna uint16; subtração de uint16 pode wrap-around (overflow)
dist = np.sqrt((int(circulo[0]) - int(outro[0]))**2 + (int(circulo[1]) - int(outro[1]))**2)
```

### Bug 2 — Margem de 8% cortando Q1
**Arquivo:** `analysis.py`, linhas 592-596, dentro de `analisar_cartao_melhorado()`

```python
# REMOVER estas 4 linhas:
# CORREÇÃO: Adicionar margem interna no topo para excluir cabeçalho "A B C D E"
# O cabeçalho ocupa ~8% do topo do retângulo detectado
margem_topo = int(h * 0.08)
y = min(y + margem_topo, y + h - 1)
h = max(h - margem_topo, 1)
```

**Por que remover:** Quando o retângulo é detectado corretamente (já exclui o cabeçalho), a margem adicional de 8% corta a primeira questão real. Evidência: Q1 é sempre errada nas 4 imagens de teste.

### Bug 3 — KMeans misturando linhas adjacentes no clustering
**Arquivo:** `image_processing.py`, linhas 755-792, dentro de `agrupar_bolhas_por_questoes()`

O KMeans às vezes coloca bolhas de 2 linhas físicas adjacentes no mesmo cluster. Quando isso acontece, o cluster tem 2 marcações com fill_rate alto (~0.97 cada), e o sistema reporta "Múltiplas marcações" escolhendo aleatoriamente entre elas.

**Correção:** No bloco `if len(bolhas_ordenadas) > num_alternativas:` (linha 768), antes do bucket assignment, filtrar bolhas por proximidade ao centróide y do cluster:

```python
if len(bolhas_ordenadas) > num_alternativas:
    # NOVO: filtrar bolhas que estejam muito longe do centro y do cluster
    y_vals = [b.get('y', b['centro'][1]) for b in bolhas_ordenadas]
    y_range = max(y_vals) - min(y_vals)
    raio_cluster = float(np.median([b.get('radius', 10) for b in bolhas_ordenadas]))
    if y_range > raio_cluster * 2:
        y_med = float(np.median(y_vals))
        bolhas_ordenadas = [b for b in bolhas_ordenadas
                            if abs(b.get('y', b['centro'][1]) - y_med) <= raio_cluster * 1.5]
        bolhas_ordenadas = sorted(bolhas_ordenadas,
                                  key=lambda b: b['centro'][0] if 'centro' in b else b['x'])
    # ... continua com o bucket assignment existente ...
```

### Bug 4 — Off-by-one no mapeamento de colunas (letras A/B/C/D/E)
**Sintoma:** Muitas respostas erram por 1 posição — detecta B quando deveria ser C, C quando deveria ser D.

**Local provável:** `agrupar_bolhas_por_questoes()` linha 780, cálculo do bucket index:
```python
idx = min(int((x - x_min) / largura_grupo), num_alternativas - 1)
```
Quando `x` está exatamente no limite entre dois buckets, pode cair no bucket errado.

**Investigar:** Adicionar log de x-coords reais de cada bolha vs limites dos buckets para uma imagem. Pode ser necessário usar a posição do cabeçalho "A B C D E" como referência de x-coords em vez de calcular por distribuição.

---

## Como rodar o teste após cada correção
```bash
cd /home/luiz/cartao-resposta
python3 teste_auto.py
# Resultado fica em relatorio_auto_YYYYMMDD_HHMMSS.json
```

---

## O que já funciona (não mexer)
- Pré-processamento adaptativo (CLAHE, remoção de sombra, perspectiva)
- Detecção com 4 métodos + NMS no template matching
- DBSCAN auxiliar para estimar número de linhas antes do KMeans
- Sem mais "X": ERRO_MULTIPLA resolve pelo maior fill_rate
- Sem mais "-": forced choice sempre retorna uma letra
- Suporte a 2 colunas via `MultiColumnCartaoAnalyzer`
