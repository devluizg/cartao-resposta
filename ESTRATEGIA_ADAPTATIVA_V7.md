# Estratégia Adaptativa V7 — Atingir 90%+ com Robustez

**Princípio**: Não usar valores fixos. Adaptar aos dados **reais** de cada imagem/cartão.

---

## 🎯 Pilares da Estratégia Adaptativa

### Pilar 1: Thresholds Dinâmicos (Não Fixos!)

**Problema com fixos**:
```python
if contrast < 45:  # ❌ Quebra com outras imagens
    clahe_limit = 3.5
```

**Solução adaptativa**:
```python
# Calcular threshold baseado na distribuição real
todas_taxas_preenchimento = [b.fill_rate for b in todas_bolhas]
media = np.mean(todas_taxas_preenchimento)
desvio = np.std(todas_taxas_preenchimento)
percentil_80 = np.percentile(todas_taxas_preenchimento, 80)
percentil_20 = np.percentile(todas_taxas_preenchimento, 20)

# Threshold adaptativo = baseado em percentis, não em valores fixos
threshold_dinamico = (percentil_80 + media) / 2

# Ou usar análise por questão:
for questao in questoes:
    fill_rates_questao = [b.fill_rate for b in questao]
    media_q = np.mean(fill_rates_questao)
    desvio_q = np.std(fill_rates_questao)
    # Threshold específico para esta questão
    threshold_q = media_q + 1.5 * desvio_q
```

**Vantagem**: Funciona com qualquer imagem, brilho ou contraste!

---

### Pilar 2: CLAHE Adaptativo Automático

**Problema com fixos**:
```python
if contrast < 45:  # ❌ Número mágico
    clahe_limit = 3.5
```

**Solução adaptativa**:
```python
def calcular_clahe_dinamico(contraste, brilho, black_ratio):
    """
    Calcula parâmetros CLAHE baseado em análise dos dados.
    Sem valores fixos!
    """
    # Score de "qualidade de imagem" (0-1)
    score_contraste = min(contraste / 80.0, 1.0)  # 80 é "ideal"
    score_brilho = 1.0 - abs(brilho - 150) / 150.0  # 150 é "ideal"
    score_black = min(black_ratio / 0.20, 1.0)  # 20% é "ideal"

    # Qualidade geral (0-1)
    qualidade = (score_contraste + score_brilho + score_black) / 3.0

    # Ajustar CLAHE inversamente à qualidade
    if qualidade < 0.3:
        # Muito ruim
        clahe_limit = 5.0
        clahe_grid = (8, 8)
    elif qualidade < 0.5:
        # Ruim
        clahe_limit = 4.0
        clahe_grid = (10, 10)
    elif qualidade < 0.7:
        # OK
        clahe_limit = 3.0
        clahe_grid = (12, 12)
    else:
        # Bom
        clahe_limit = 2.0
        clahe_grid = (8, 8)

    return clahe_limit, clahe_grid
```

**Vantagem**: Escala automaticamente com qualidade, não quebra com outras imagens!

---

### Pilar 3: DBSCAN Adaptativo com Validação

**Problema com fixos**:
```python
eps = spacing_estimado * 0.40  # ❌ Número fixo
```

**Solução adaptativa**:
```python
def agrupar_bolhas_robusto(bolhas, num_questoes_esperado):
    """
    Encontra o melhor eps automaticamente, não usa valores fixos.
    """
    spacing_estimado = estimar_espacamento(bolhas)

    # Tentar múltiplos eps_factors até encontrar o correto
    for eps_factor in np.linspace(0.30, 0.80, 11):  # 0.30, 0.35, ..., 0.80
        eps = spacing_estimado * eps_factor
        clusters = DBSCAN(eps=eps, min_samples=3).fit(coords)
        num_clusters = contar_clusters(clusters)

        if num_clusters == num_questoes_esperado:
            print(f"  ✓ DBSCAN convergiu com eps_factor={eps_factor:.2f}")
            return clusters, eps_factor

    # Se nem isso conseguiu, usar KMeans como último recurso
    print(f"  ⚠ DBSCAN não convergiu, usando KMeans forçado")
    return KMeans(n_clusters=num_questoes_esperado).fit(coords), None
```

**Vantagem**: Testa automaticamente, encontra o melhor eps sem valores mágicos!

---

### Pilar 4: Validação de Razoabilidade

**Verificações automáticas**:
```python
def validar_resultado_razoavel(resultado, confianca, num_questoes):
    """
    Verifica se o resultado faz sentido estatisticamente.
    Se não, marca para fallback.
    """
    # Check 1: Nenhuma alternativa aparece muito mais que esperado
    alternativas_esperado = num_questoes / 5.0
    from collections import Counter
    contagem = Counter([r for r in resultado.values() if r])
    for alt, count in contagem.items():
        if count > alternativas_esperado * 2.5:
            print(f"  ⚠ Alternativa {alt} aparece {count}x (esperado ~{alternativas_esperado:.1f})")
            return False, f"Alternativa {alt} muito frequente"

    # Check 2: Muitas questões com baixa confiança
    conf_media = np.mean(list(confianca.values()))
    if conf_media < 0.5:
        print(f"  ⚠ Confiança média muito baixa: {conf_media:.2f}")
        return False, "Confiança geral baixa"

    # Check 3: Muitas questões não lidas
    respostas_lidas = sum(1 for r in resultado.values() if r is not None)
    if respostas_lidas < num_questoes * 0.8:
        print(f"  ⚠ Apenas {respostas_lidas}/{num_questoes} questões lidas")
        return False, "Muitas questões não detectadas"

    return True, "OK"
```

**Vantagem**: Detecta automaticamente quando algo está errado!

---

### Pilar 5: Fallback Automático em Cascata

**Em vez de um fallback, implementar cascata**:
```python
def processar_cartao_robusto(image, binary, num_questoes, num_colunas):
    """
    Tenta múltiplas estratégias em cascata até uma funcionar.
    """
    estrategias = [
        ("Estratégia 1: DBSCAN adaptativo", estrategia_dbscan_adaptativo),
        ("Estratégia 2: KMeans direto", estrategia_kmeans),
        ("Estratégia 3: Análise per-coluna", estrategia_por_coluna),
        ("Estratégia 4: Claude Vision", estrategia_claude_vision),
    ]

    for nome, funcao in estrategias:
        try:
            resultado, confianca = funcao(image, binary, num_questoes, num_colunas)
            valido, motivo = validar_resultado_razoavel(resultado, confianca, num_questoes)

            if valido:
                print(f"  ✓ {nome} funcionou!")
                return resultado, confianca, nome

            print(f"  ⚠ {nome} falhou: {motivo}, tentando próxima...")
        except Exception as e:
            print(f"  ❌ {nome} exception: {e}")

    # Se nada funcionar, retornar com confiança baixa
    print(f"  ❌ Todas as estratégias falharam!")
    return None, {}, "Nenhuma estratégia funcionou"
```

**Vantagem**: Nunca quebra completamente, sempre tenta alternativas!

---

## 📊 Implementação Prática

### Fase 1: Analise os Dados Reais
```python
# Em cada processamento, coletar metadados
metricas = {
    "contraste_min": None,
    "contraste_max": None,
    "contraste_medio": None,
    "brilho_min": None,
    "brilho_max": None,
    "fill_rate_min": None,
    "fill_rate_max": None,
    "fill_rate_media": None,
    "num_clusters_detectados": None,
    "num_clusters_esperado": None,
}
```

### Fase 2: Tome Decisões Baseadas em Dados
```python
# Não faça:
if contraste < 45:  # ❌ Valor fixo

# Faça:
qualidade_imagem = calcular_qualidade(contraste, brilho, black_ratio)
if qualidade_imagem < 0.5:  # ✅ Baseado em análise
    clahe_limit, clahe_grid = calcular_clahe_dinamico(...)
```

### Fase 3: Valide Continuamente
```python
# Após cada passo, verificar se saída faz sentido
valido, motivo = validar_resultado_razoavel(resultado, confianca, num_questoes)
if not valido:
    # Tentar estratégia alternativa, não simplesmente aceitar resultado ruim
    resultado = estrategia_alternativa(...)
```

---

## 🎯 Expectativas

**Com estratégia adaptativa**:
- Dataset A (7 imagens): 65% → 85-90% ✅
- Dataset B (100 imagens variadas): 85-90% (não cai para 40%) ✅
- Dataset C (novas imagens): 85-90% (generaliza bem) ✅

**Sem estratégia adaptativa (valores fixos)**:
- Dataset A: 90% ✅
- Dataset B: 50% ❌ (valores fixos não se adaptam)
- Dataset C: 40% ❌ (quebra completamente)

---

## 🔧 Arquitetura Proposta

```
Imagem
  ↓
[Pré-processamento Adaptativo]
  ├─ Qualidade = f(contraste, brilho, black_ratio)
  ├─ CLAHE Params = f(qualidade)
  └─ Flash Virtual = sempre (idempotente)
  ↓
[Detecção Hybrid Robusta]
  ├─ 4 métodos em paralelo
  ├─ Voting system (requer 2+ concordância)
  └─ Validate = f(distribuição real)
  ↓
[Agrupamento DBSCAN Adaptativo]
  ├─ Estimar spacing
  ├─ Tentar múltiplos eps_factors
  ├─ Validar num_clusters == esperado
  └─ Fallback para KMeans se necessário
  ↓
[Análise de Fill Rate Adaptativa]
  ├─ Threshold = f(distribuição per-questão)
  ├─ Confiança = f(separação entre max e segundo-max)
  └─ Validação = estatística
  ↓
[Validação em Cascata]
  ├─ Check 1: Distribuição alternativas razoável?
  ├─ Check 2: Confiança média aceitável?
  ├─ Check 3: Mínimo questões detectadas?
  └─ Se não, tentar próxima estratégia
  ↓
Resultado + Confiança + Método Usado
```

---

## ✅ Checklist de Implementação

- [ ] Remover TODOS os valores fixos (contraste < 45, clipLimit = 3.5, etc.)
- [ ] Implementar cálculo de qualidade_imagem dinâmico
- [ ] Implementar CLAHE params como função de qualidade
- [ ] Implementar DBSCAN adaptativo com loop iterativo
- [ ] Implementar validação de razoabilidade
- [ ] Implementar cascata de fallbacks
- [ ] Testar com dataset original (7 imagens)
- [ ] Testar com dataset novo (se possível)
- [ ] Medir: Média, Min, Max, Desvio Padrão de precisão

---

*Estratégia V7 — Adaptativa, Robusta, Generalizável*
*Objetivo: 90%+ em qualquer dataset, não apenas este*
