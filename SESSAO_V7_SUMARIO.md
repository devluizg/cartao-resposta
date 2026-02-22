# Sessão V7 — Implementação de Pillares Adaptativos (3 & 4)

**Data**: Fevereiro 2026
**Objetivo Inicial**: Melhorar de 65.14% para 90%+
**Resultado Final**: 65.71% (115/175 acertos) — Estável + Melhorias Implementadas
**Status**: ✅ Pillares 3 & 4 funcionando, Pilar 5 planejado

---

## 📊 Resumo de Resultados

### Progresso por Teste
| Teste | Abordagem | Precisão | Δ | Status |
|-------|-----------|----------|---|--------|
| V6 Final | Baseline CLAHE agressivo | 65.14% | baseline | ✅ |
| Quality_score CLAHE | CLAHE dinâmico por qualidade | 63.43% | -1.71% | ❌ Regressão |
| Iterativo DBSCAN | Baseline + eps iterativo | 65.71% | +0.57% | ✅ Melhoria |

### Por Imagem (65.71% = 115/175)
```
Imagem 1 (19.33.45): 22/25 = 88.0%
Imagem 2 (19.33.48): 15/25 = 60.0%
Imagem 3 (19.33.55): 20/25 = 80.0%
Imagem 4 (19.33.51):  4/25 = 16.0% ⚠️ PROBLEMA
Imagem 5 (19.33.50): 23/25 = 92.0%
Imagem 6 (19.33.47): 10/25 = 40.0% ⚠️ PROBLEMA
Imagem 7 (19.33.54): 21/25 = 84.0%
─────────────────────────────────
TOTAL: 115/175 = 65.71%
```

---

## 🎯 Implementações Realizadas

### ✅ PILAR 3: DBSCAN Iterativo com Validação

**Problema Identificado**:
- DBSCAN original usava eps fixo = `raio_medio * 1.5`
- Resultava em clustering errado para imagens com proporções diferentes
- Exemplos:
  - Imagem com ROI grande → 14-18 clusters (esperado 12-13)
  - Imagem com ROI pequeno → 8-10 clusters (esperado 12-13)

**Solução Implementada**:
```python
# Em agrupar_bolhas_por_questoes() - image_processing.py:983

for eps_factor in [0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.80, 0.90, 1.0]:
    eps_teste = eps_base * eps_factor
    db_teste = DBSCAN(eps=eps_teste, min_samples=1).fit(y_only)
    linhas_teste = len(set(db_teste.labels_[db_teste.labels_ != -1]))

    # Sucesso se encontra número esperado (com tolerância de ±1)
    if abs(linhas_teste - num_questoes) <= 1:
        labels = db_teste.labels_
        print(f"DBSCAN convergiu com eps_factor={eps_factor:.2f}")
        break

# Se nada funcionar, KMeans como último recurso
if labels is None:
    kmeans = KMeans(n_clusters=num_questoes, random_state=42, n_init=10)
    labels = kmeans.fit_predict(y_only)
```

**Benefícios**:
- ✅ Encontra eps automaticamente sem valor mágico
- ✅ Mais robusto para imagens com proporções diferentes
- ✅ Log mostra qual eps_factor funcionou
- ✅ Fallback seguro para KMeans se necessário

---

### ✅ PILAR 4: Validação Estatística de Razoabilidade

**Problema Identificado**:
- Resultados "suspeitos" não eram detectados (ex: 8 A's em 25 questões)
- Sem validação, código aceitava resultados ruins sem questionar

**Solução Implementada**:
```python
# analysis.py:326

def validar_resultado_razoavel(resultados, confianca, num_questoes, num_alternativas=5):
    """Verifica se resultado faz sentido estatisticamente."""

    # CHECK 1: Nenhuma alternativa > 2.5× esperada
    alternativas_esperadas = len(respostas_lidas) / num_alternativas
    for alt, count in Counter(respostas_lidas).items():
        if count > alternativas_esperadas * 2.5 and count > 2:
            return False, f"Alternativa {alt} aparece {count}x (esperado ~{esperadas:.1f})"

    # CHECK 2: Confiança média não muito baixa
    conf_media = np.mean(valores_confianca)
    if conf_media < 0.30:
        return False, f"Confiança média muito baixa: {conf_media:.2f}"

    # CHECK 3: Mínimo 70% de questões detectadas
    num_lidas = sum(1 for r in resultados.values() if r is not None)
    if num_lidas < num_questoes * 0.70:
        return False, f"Apenas {num_lidas}/{num_questoes} questões lidas"

    return True, "OK"
```

**Benefícios**:
- ✅ Detecta automáticamente resultados suspeitos
- ✅ Preparação para fallback em Pilar 5 (cascata de estratégias)
- ✅ Métricas explícitas para debugging

---

## 🔬 Análise de Falhas

### Imagem 4 (19.33.51): 16% — Cristicamente Baixa
```
Brightness: 156
Contrast: 65
Clusters detectados: 13 (esperado 12)
Problema: Questões não mapeadas corretamente
```
**Hipótese**: DBSCAN encontrou um cluster extra (13 vs 12), causando desalinhamento

**Próximas Ações**:
- [ ] Verificar se tolerância de ±1 está causando problemas
- [ ] Aumentar tolerância para ±2 e testar
- [ ] Analisar visualmente a imagem para entender estrutura

### Imagem 6 (19.33.47): 40% — ROI Muito Grande
```
Brightness: 122
Contrast: 77 (boa)
ROI: 384×1013 (1.57× maior que padrão)
Problema: DBSCAN agrupa demais em poucas linhas
```
**Hipótese**: Raio estimado é grande demais para ROI grande

**Próximas Ações**:
- [ ] Implementar normalização de raio baseada em ROI
- [ ] Testar diferentes raio_factors (não apenas 1.5×)

---

## 🚀 Pilar 5: Cascading Fallbacks (Não Implementado)

Seria implementar estratégia de múltiplas tentativas:

```
Estratégia 1: DBSCAN Iterativo (atual)
├─ Validação passa? → Retornar resultado
└─ Validação falha? → Estratégia 2

Estratégia 2: KMeans com eps adaptativo
├─ Validação passa? → Retornar resultado
└─ Validação falha? → Estratégia 3

Estratégia 3: Análise per-coluna
├─ Validação passa? → Retornar resultado
└─ Validação falha? → Estratégia 4

Estratégia 4: Claude Vision API (fallback final)
└─ Retornar resultado com confiança manual
```

**Não foi implementado porque**:
- Código atual já tem MultiColumnCartaoAnalyzer para per-coluna
- Cada estratégia adicional aumenta complexidade
- Antes de Pilar 5, fazer debugging das imagens 4 & 6 é mais produtivo

---

## 📈 Próximos Passos Recomendados

### Curto Prazo (Próximas 1-2 sessões)
1. **Debug Imagem 4** (16%): Investigar por que DBSCAN encontra 13 linhas vs 12 esperado
2. **Debug Imagem 6** (40%): Analisar ROI grande e possível normalização de raio
3. **Testar tolerância ±2**: Aumentar tolerância em DBSCAN para ±2 e ver impacto

### Médio Prazo (Próximas 3-5 sessões)
4. **Melhorar Flash Virtual** para imagens com sombras extremas (tipo imagem 4)
5. **Implementar normalização de raio**: `raio = raio_base * (roi_width / roi_width_padrao)`
6. **Adicionar mais validações**: Distribuição de fill_rates por questão

### Longo Prazo
7. **Implementar Pilar 5**: Cascading fallbacks com multiple estratégias
8. **Integrar Claude Vision**: Para questões ambíguas (confidence < 0.20)
9. **Fine-tuning final**: Ajustar thresholds baseado em dataset completo

---

## 💡 Aprendizados Principais

### 1. Quality_Score Dinâmico É Traiçoeiro
❌ Tentar prever CLAHE ideal usando fórmula (brightness + contrast)
- Fatores confundidos (brightness e density muito relacionados)
- Impossível validar sem detectar bolhas (catch-22)

✅ Usar abordagem "try and validate"
- Tentar com CLAHE padrão
- Validar se clustering funcionou
- Só mudar parâmetros se validação falhar

### 2. Iteração É Melhor Que Predição
❌ Fixar DBSCAN eps = `raio * 1.5` para todas as imagens

✅ Testar múltiplos eps_factors até encontrar que funciona

### 3. Validação Estatística É Crítica
- Sem validação, aceita qualquer resultado
- Com validação, detecta problemas antes de piora

---

## 📝 Commits Realizados

```
49953c3 feat: Implement iterative DBSCAN (Pilar 3) and statistical validation (Pilar 4)
        - DBSCAN tenta eps_factors de 0.40 a 1.0
        - Validação: alternativas, confiança, cobertura de questões
        - Baseline mantido em 65.71%
```

---

## 🎯 Conclusão

- **Baseline Estável**: 65.71% (melhor que 65.14%)
- **Arquitectura Robusta**: Pillares 3 & 4 implementados
- **Pronto para Debug**: Imagens 4 & 6 são próximos alvos
- **Caminho Claro**: Path to 90% bem definido (debug → normalização → Pilar 5)

**Estimativa com debugging de imagens 4 & 6**: 65% → 75-80%
**Estimativa com Pilar 5 + Claude Vision**: 80% → 85-90%

---

*Sessão V7 Finalizada - Fevereiro 2026*
*Próxima: Debug de imagens problemáticas e normalização de raio*
