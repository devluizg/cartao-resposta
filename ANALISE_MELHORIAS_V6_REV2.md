# Análise Revisada V6.2 — Estratégia Mais Conservadora

**Aprendizado**: O FIX A1 (mudança radical no cálculo de raio) causou regressão de 65.71% → 44.0%

**Nova Estratégia**: Ajustes menores e incrementais, validados em cada passo

---

## 🔴 Problema com FIX A1

O novo cálculo de raio:
```
raio_px = 2.5mm * (roi_width_px / 43mm)
```

Para 397px: raio = 23.1px (vs anterior ~14px com divisor=70)

Problema: Raio 23px muda TODA a geometria:
- spacing_est maior
- eps maior
- DBSCAN agrupa menos
- Resultado: 2 clusters em vez de 13

**Conclusão**: O divisor=70 não é tão errado assim. É empiricamente otimizado.

---

## ✅ Nova Estratégia: FIX Adaptativo de DBSCAN

Em vez de mudar o raio fundamentalmente, usar adaptação de eps:

```python
def agrupar_bolhas_com_validacao(bolhas, num_questoes_esperado):
    """
    Se DBSCAN não encontrar num_questoes_esperado clusters,
    aumentar eps iterativamente até conseguir (ou dar up e usar KMeans).
    """
    for eps_factor in [0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70]:
        eps = spacing_estimado * eps_factor
        clusters = DBSCAN(eps=eps, min_samples=3).fit(coords)
        num_clusters = contar_clusters(clusters)

        if num_clusters == num_questoes_esperado:
            print(f"  ✓ DBSCAN encontrou {num_clusters} com eps_factor={eps_factor}")
            return clusters

    # Se nem com eps=0.70 conseguiu, usar KMeans
    print(f"  ⚠ DBSCAN não convergiu mesmo com eps=0.70, usando KMeans")
    return KMeans(n_clusters=num_questoes_esperado).fit(coords)
```

**Vantagem**: Mais conservador, não quebra as imagens que estão funcionando bem

---

## ✅ FIX B1 + B2: CLAHE Agressivo (Mantém)

Isso estava correto:
```python
if contrast < 45:  # Reduzir threshold de 40→45
    clahe_limit = 4.0  # Aumentar de 3.5
    clahe_grid = (10, 10)  # Mais agressivo
```

**Estado**: OK, implementar com segurança

---

## ✅ FIX C1: Validar Ordem de Bolhas (Mantém)

```python
# Reordenar bolhas por X antes de mapear para [A,B,C,D,E]
bolhas_ordenadas = sorted(bolhas_da_linha, key=lambda b: b.get('x', 0))
```

**Estado**: OK, implementar com segurança

---

## 📊 Novo Plano de Implementação

| Fix | Risco | Implementar |
|-----|-------|-------------|
| A1 (raio matemático) | ALTO | ❌ REVERT - causa regressão |
| A2 (DBSCAN adaptativo) | MÉDIO | ✅ Implementar |
| B1+B2 (CLAHE agressivo) | BAIXO | ✅ Implementar |
| C1 (ordem de bolhas) | BAIXO | ✅ Implementar |

---

## 🎯 Meta com Nova Estratégia

- Baseline: 65.71%
- Com A2+B1+B2+C1: Estimar ~75-80% (mais conservador)

---

*Análise Revisada V6.2 - Março 2026*
