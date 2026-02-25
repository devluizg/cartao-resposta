# 📸 GUIA COMPLETO: FOTOGRAFIA ÓTIMA DO CARTÃO-RESPOSTA

## 1. DIMENSÕES EXATAS DO CARTÃO

### Papel
- **Formato**: A4 (210mm × 297mm)
- **Proporção**: 0.707 (mais alto que largo)
- **Tipo**: Branco com bordas pretas

### Marcadores de Canto (Fiduciais OMR)
- **Quantidade**: 4 (um em cada canto)
- **Formato**: Círculos pretos sólidos
- **Raio**: 6mm (Ø 12mm)
- **Posição**:
  - Top-Left: 12mm do topo, 12mm da esquerda
  - Top-Right: 12mm do topo, 198mm da esquerda
  - Bottom-Left: 12mm da base, 12mm da esquerda
  - Bottom-Right: 12mm da base, 198mm da esquerda

### Bolhas de Resposta
- **Formato**: Círculos brancos com borda preta
- **Raio**: 2.5mm (Ø 5mm)
- **Espaçamento horizontal**: 7mm entre centros (A, B, C, D, E)
- **Espaçamento vertical**: 8.5mm entre centros (entre questões)

---

## 2. POSIÇÃO ÓTIMA NA CÂMERA

### Enquadramento Ideal
```
┌─────────────────────────────────────────┐
│                                         │
│    ╔═══════════════════════════╗       │
│    ║  CARTÃO-RESPOSTA (A4)    ║       │
│    ║                          ║       │
│    ║  [Ocupar ~80% da tela]   ║       │
│    ║                          ║       │
│    ╚═══════════════════════════╝       │
│                                         │
└─────────────────────────────────────────┘

Para 1280×720px:
- Altura do cartão: ~700px
- Largura do cartão: ~495px
- Margens laterais: ~392px cada lado
- Margens verticais: ~10px cada lado
```

### Área de Segurança (Não Cortar)
- ❌ Não deixe o topo do QR code sair da tela
- ❌ Não deixe o rodapé sair da tela
- ❌ Não deixe os marcadores de canto saírem
- ✅ Mantenha ~15px de margem em todos os lados

---

## 3. ÂNGULO IDEAL

### Classificação de Ângulos
```
Ângulo 0° (Perpendicular) - PERFEITO ✅
  ├─ Sem distorção de perspectiva
  ├─ Bolhas detectadas 100%
  ├─ OMR funciona perfeitamente
  └─ Moldura fica VERDE

Ângulo ±2 a ±5° - BOM ✅
  ├─ Pequena distorção
  ├─ Transformação de perspectiva compensa
  └─ Moldura fica VERDE

Ângulo ±5 a ±10° - AVISO ⚠️
  ├─ Distorção moderada
  ├─ Recomenda ajuste
  └─ Moldura fica LARANJA

Ângulo > ±15° - RUIM ❌
  ├─ Muita distorção
  ├─ Não recomendado
  └─ Moldura fica VERMELHO
```

### Como Detectar Inclinação
1. **Observe os 4 marcadores de canto** (círculos verdes na tela)
2. **Linha TL-TR deve estar HORIZONTAL** (sem inclinação)
3. **Linha TL-BL deve estar VERTICAL** (sem inclinação)
4. **Indicador de ângulo** (topo da câmera) mostra o ângulo atual
5. **Quando ângulo = 0°, marcadores formam retângulo perfeito**

---

## 4. ILUMINAÇÃO IDEAL

### Brightness (Brilho)
- **Ideal**: 150-220 (valores 0-255)
- **Muito escuro** (<100): Vermelho ❌
  - Acenda o flash ou mude para local mais iluminado
- **Muito claro** (>240): Vermelho ❌
  - Evite luz solar direta
  - Reduza intensidade da luz
- **Ótimo** (150-220): Verde ✅

### Illumination Uniformity (Uniformidade)
- **Ideal**: > 0.75 (valores 0-1)
- **Com sombras** (<0.55): Laranja ⚠️
  - Mude o ângulo da luz
  - Use múltiplas fontes de luz
- **Uniforme** (>0.75): Verde ✅

### Dica Prática
```
✅ BOA ILUMINAÇÃO:
  • Luz natural (janela)
  • Sala bem iluminada
  • Sem sombras no cartão
  • Contraste alto (branco/preto claro)

❌ MÁ ILUMINAÇÃO:
  • Luz muito fraca (precisa flash)
  • Sombra de mão cobrindo cartão
  • Luz solar direta (muito brilho)
  • Contraste baixo (cinzento)
```

---

## 5. DISTÂNCIA IDEAL

### Profundidade
```
Menos de 20cm    : Desfocado, bolhas muito grandes  ❌
20-30cm (IDEAL)  : Foco nítido, bolhas bem definidas ✅
Mais de 30cm     : Muito longe, bolhas pequenas      ❌

Para 1280×720px:
  → Use 25cm como referência
  → Deixe uma mão de distância (aproximadamente)
```

### Como Verificar
1. **Veja as bolhas na câmera**: devem estar nítidas e bem definidas
2. **Indicador de distância** (canto inferior direito) mostra "Ideal: 20-30cm"
3. **Foco automático** da câmera deve travar (observe o retângulo de foco)

---

## 6. GUIAS VISUAIS NA CÂMERA

### Moldura Principal (Borda Colorida)
- 🟩 **VERDE**: Perfeito, pode fotografar
- 🟨 **AMARELO**: Analisando, aguarde
- 🟧 **LARANJA**: Aviso, corrija posição/ângulo
- 🔴 **VERMELHO**: Ruim, precisa ajuste

### Área de Segurança (Linha Vermelha)
- ✅ Mostra a área que pode estar visível na foto
- ❌ Evite que conteúdo saia dessa área
- Margem de ~15px em todos os lados

### Marcadores de Canto Esperados (Círculos Verdes)
- ✅ 4 pontos verdes marcam onde DEVE estar cada marcador
- ✅ Use como referência para posicionar o cartão
- Indicadores: **TL** (canto superior esquerdo), **TR**, **BL**, **BR**

### Linhas de Perspectiva (Azuis)
- ✅ Diagonais do cartão (X)
- ✅ Linhas verticais e horizontais
- Se inclinadas, cartão está em perspectiva

### Indicador de Ângulo (Topo da Câmera)
- Mostra ângulo atual em graus
- Escala: -15° a +15°
- Verde quando 0° (reto)
- Vermelho quando inclinado

### Indicador de Distância (Canto Inferior Direito)
- Mostra alcance ideal: 20-30cm
- Use como referência

---

## 7. PASSO A PASSO PARA FOTOGRAFAR PERFEITAMENTE

### Antes de Tirar a Foto
1. ✅ **Escanear QR Code**
   - Aponte para o QR code no topo do cartão
   - Veja mensagem: "QR Code detectado!"
   - Tipo de prova é identificado automaticamente

2. ✅ **Abrir Câmera**
   - Clique em "Fotografar Cartão"
   - Câmera abre com guias visuais

### Posicionamento do Cartão
3. ✅ **Coloque o cartão na mesa**
   - Posição: central, bem iluminado
   - Angle: 0° (reto, perpendicular à câmera)
   - Distância: 25cm aproximadamente

4. ✅ **Alinhe com os marcadores de canto**
   - Observe os 4 círculos verdes na tela
   - Ajuste cartão até os 4 cantos alinharem
   - Moldura muda para VERDE quando tudo está certo

### Verificação Final
5. ✅ **Verifique iluminação**
   - Moldura está VERDE? ✅
   - Dica diz "Pode fotografar"? ✅
   - Bolhas visíveis e nítidas? ✅

6. ✅ **Verifique ângulo**
   - Indicador de ângulo mostra 0°? ✅
   - Marcadores de canto formam retângulo? ✅
   - Linhas horizontais estão horizontais? ✅

### Captura
7. ✅ **Clique no botão branco (Centro)**
   - Botão tem borda colorida (deve estar VERDE)
   - Câmera captura foto
   - Vê preview da foto

8. ✅ **Confirmar ou Refazer**
   - "USAR ESTA FOTO": envia para processamento
   - "REFAZER": volta para câmera ao vivo

---

## 8. SOLUÇÃO DE PROBLEMAS

### Moldura Está Vermelha (Muito Inclinado)
```
Problema: Cartão está em ângulo (não perpendicular)

Solução:
  1. Veja a moldura - qual lado está saindo?
  2. Levante ou abaixe o cartão para corrigir
  3. Observe os 4 marcadores de canto
  4. Deixe-os formar um retângulo perfeito
  5. Indicador de ângulo deve mostrar ~0°
```

### Moldura Está Laranja (Sombra)
```
Problema: Iluminação não uniforme (com sombras)

Solução:
  1. Procure a origem da sombra (sua mão? luz lateral?)
  2. Mude a posição da câmera ou do cartão
  3. Use luz frontal (não lateral)
  4. Se possível, use 2 fontes de luz
  5. Evite luz solar direta
```

### Moldura Está Vermelha (Muito Escuro)
```
Problema: Pouca iluminação (brightness < 100)

Solução:
  1. Leve o cartão para local mais iluminado
  2. Ou acenda o flash (clique no ícone de flash)
  3. Aumente intensidade da luz ambiente
  4. Espere a moldura ficar VERDE
```

### Moldura Está Vermelha (Muito Claro)
```
Problema: Muita iluminação (brightness > 240)

Solução:
  1. Evite luz solar direta no cartão
  2. Mude para sombra
  3. Reduza intensidade da luz
  4. Feche um pouco a abertura da câmera
  5. Espere a moldura ficar VERDE
```

### Bolhas Estão Embaçadas
```
Problema: Foco não está correto (muito perto)

Solução:
  1. Aumente a distância (>25cm)
  2. Deixe câmera focar (retângulo aparece)
  3. Aguarde 1 segundo
  4. Observe se "PRONTO: Pode fotografar" aparece
```

### Cartão Está Cortado (Saindo da Tela)
```
Problema: Cartão muito grande na câmera

Solução:
  1. Aumente a distância (aproxime-se menos)
  2. Reduza o zoom (se houver)
  3. Reposicione o cartão na câmera
  4. Observe a linha vermelha (área de segurança)
```

---

## 9. CHECKLIST ANTES DE FOTOGRAFAR

- [ ] QR code foi escaneado?
- [ ] Câmera abriu com guias visuais?
- [ ] Moldura está VERDE?
- [ ] Indicador de ângulo mostra ~0°?
- [ ] Marcadores de canto estão visíveis (4 círculos verdes)?
- [ ] Distância está certa (20-30cm)?
- [ ] Iluminação é uniforme (sem sombras)?
- [ ] Bolhas são nítidas?
- [ ] Dica diz "Pode fotografar"?
- [ ] Cartão não está saindo da tela?
- [ ] Botão de captura está com borda VERDE?

**Se todos marcados: ✅ Pode fotografar!**

---

## 10. RESULTADO ESPERADO

### Foto Ruim (88% de precisão)
- Inclinado
- Com sombras
- Desfocado
- Iluminação ruim

### Foto Ótima (100% de precisão) ✨
- Perpendicular (0°)
- Iluminação uniforme
- Nítido e claro
- Contraste alto
- Todos os 4 marcadores visíveis

**Use este guia e a moldura inteligente para sempre fotografar ótimo!**

