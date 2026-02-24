# 🎯 Fase 1: Captura com Validação de Qualidade

## Implementação Completa

### ✅ O que foi feito

#### 1. **Novo Serviço: `ImageQualityAnalyzer`**
📁 `lib/services/image_quality_analyzer.dart`

Analisa qualidade de imagem capturada em 6 dimensões:

| Métrica | O que mede | Ideal | Implementação |
|---------|-----------|-------|-------------------|
| **Brightness** | Intensidade média da luz | 150-220 | Média ponderada RGB |
| **Contrast** | Variação entre claro/escuro | > 40 | Desvio padrão |
| **Sharpness** | Clareza/foco | > 0.7 | Detecção Sobel |
| **Illumination** | Uniformidade de sombras | > 0.75 | Análise de quadrantes |
| **Corners** | Visibilidade dos cantos | > 0.8 | Detecção de borda escura |
| **Overall Score** | Combinação ponderada | > 60 | 0-100 |

**Output:**
```dart
ImageQualityResult {
  brightness: 180,           // ✅ Bom
  contrast: 55,              // ✅ Bom
  sharpness: 0.82,           // ✅ Bom
  illuminationUniformity: 0.78,  // ✅ Bom
  cornerVisibility: 0.95,    // ✅ Excelente
  overallScore: 87,          // ✅ Excelente
  recommendation: "✅ Qualidade excelente!"
}
```

#### 2. **Integração na Câmera: `CameraCaptureScreen`**
📁 `lib/screens/camera_capture_screen.dart`

**Alterações implementadas:**

**a) Análise Automática Após Captura**
```dart
// Após capturar a foto, análise automática:
final qualityResult = await ImageQualityAnalyzer.analyzeImage(
  XFile(arquivoFinal.path),
);
```

**b) Novo Widget: `_buildQualityBanner()`**
- Banner dinâmico que muda cor baseado no score:
  - 🟢 Verde (score >= 85): Excelente
  - 🔵 Azul (score >= 75): Bom
  - 🟠 Laranja (score >= 60): Aceitável
  - 🔴 Cinzento (score < 60): Qualidade Baixa

**c) Card de Detalhes: `_buildQualityDetailsCard()`**
- Grid 2x3 com métricas individuais:
  ```
  ☀️ Brilho: 180    📊 Contraste: 55    🎯 Nitidez: 82%
  💡 Iluminação: 78%  📐 Cantos: 95%     ⭐ Score: 87%
  ```
- Cada métrica tem cor (verde=boa, vermelho=ruim)

**d) Bloqueio de Uso (Score < 60)**
```dart
if (_qualityResult != null && !_qualityResult!.isAcceptable) {
  // Bloqueia envio, mostra SnackBar com recomendação
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_qualityResult!.recommendation))
  );
  return;
}
```

**e) Botão "USAR ESTA FOTO" dinâmico**
- 🟢 Verde: Score >= 60 (habilitado)
- 🟰 Cinzento: Score < 60 (desabilitado)
- Mostra "ANALISANDO..." durante processamento
- Exibe "QUALIDADE BAIXA" se score insuficiente

#### 3. **Passagem de Dados**
```dart
class CaptureResult {
  final File imageFile;
  final int numColunas;
  final ImageQualityResult? qualityResult;  // ✨ NOVO
}
```

---

## 🎨 Visual/UX

### Fluxo do Usuário

```
1️⃣ CÂMERA AO VIVO
   └─ "Fotografar Cartão-Resposta"
   └─ Enquadre os quadrados pretos de cada coluna
   └─ Botão circular branco "CAPTURAR"

2️⃣ ANALISANDO (1-2 segundos)
   ⏳ Progress spinner no botão
   "ANALISANDO..."

3️⃣ RESULTADO - PREVIEW COM QUALIDADE

   ┌─────────────────────────────────────┐
   │ ✨ Imagem da Foto                   │
   │                                     │
   │ ┌─────────────────────────────────┐ │
   │ │ 🟢 Qualidade: 87%               │ │ ← Banner colorido
   │ │ ✅ Qualidade excelente!          │ │
   │ └─────────────────────────────────┘ │
   │                                     │
   │ ┌──────┬──────┬──────┐              │
   │ │☀️180 │📊 55 │🎯82% │ ← Grid 2x3  │
   │ ├──────┼──────┼──────┤              │
   │ │💡78% │📐95% │⭐87% │              │
   │ └──────┴──────┴──────┘              │
   │                                     │
   └─────────────────────────────────────┘

   ┌─────────────┬──────────────────────┐
   │ 🔄 REFAZER  │ ✅ USAR ESTA FOTO   │ (botões)
   └─────────────┴──────────────────────┘

4️⃣ POSSÍVEIS RESPOSTAS

   ✅ Score >= 60: Foto aceita, segue para OCR
   ❌ Score < 60: Mostra recomendação, permite refazer
      "⚠️ Imagem muito escura • Contraste baixo"
```

---

## 🔍 Exemplos de Recomendações

| Situação | Recomendação | Score |
|----------|-------------|-------|
| Foto normal, bem iluminada | "✅ Qualidade excelente!" | 87% |
| Pouca luz | "⚠️ Imagem muito escura" | 42% ❌ |
| Muita luz/reflexo | "⚠️ Imagem muito clara" | 35% ❌ |
| Desfocada | "⚠️ Imagem desfocada" | 38% ❌ |
| Com sombras | "⚠️ Sombras detectadas" | 48% ❌ |
| Cantos fora do quadro | "⚠️ Cantos não visíveis" | 45% ❌ |
| Múltiplos problemas | "⚠️ Imagem muito escura • Contraste baixo • Desfocada" | 25% ❌ |

---

## 📊 Impacto Esperado

### Antes (88%)
- Usuário tira foto qualquer
- Envia para API (mesmo se ruim)
- API tenta processar com 88% de acurácia

### Depois (88% + 5-8%)
- Usuário tira foto
- **App valida qualidade ANTES**
- Se ruim: "Imagem muito escura, tente novamente"
- Se boa: "✅ Qualidade excelente! Use esta foto"
- Envia apenas fotos com score >= 60
- **Resultado: API processa mais fotos boas = menos erros**

**Ganho estimado: +5-8% de acurácia global**

---

## 🚀 Como Testar

### 1. Build do app
```bash
cd leitor_cartao
flutter pub get
flutter run
```

### 2. Capturar foto
- Pressione câmera
- Tire foto do cartão
- Espere 1-2 segundos de análise

### 3. Verificar resultado
- **✅ Verde**: Score >= 85 → use a foto
- **🔵 Azul**: Score 75-84 → boa qualidade
- **🟠 Laranja**: Score 60-74 → aceitável
- **🔴 Cinzento**: Score < 60 → refaça

### 4. Testar cenários
- ☀️ Luz natural boa → score alto ✅
- 🌙 Pouca luz → score baixo ❌
- ⛅ Sombras → score médio ⚠️
- 📸 Desfocada → score baixo ❌
- 📐 Cantos fora → score baixo ❌

---

## 📱 Próximas Fases (Roadmap)

### ✅ Fase 1: Captura (COMPLETO) 🎯
Validação de qualidade em tempo real

### 🔄 Fase 2: User Correction (IN PROGRESS)
Loop de correção com feedback do usuário

### 📸 Fase 3: Multi-Shot Voting
Tirar múltiplas fotos e votar

### 📋 Fase 4: Gabarito Integration
Validação cruzada com gabarito esperado

---

## 🛠️ Implementação Técnica

### Arquivos Modificados

1. **`lib/services/image_quality_analyzer.dart`** ✨ NOVO
   - 350+ linhas
   - Classe `ImageQualityResult` + `ImageQualityAnalyzer`
   - 6 funções de cálculo de métricas

2. **`lib/screens/camera_capture_screen.dart`** 📝 MODIFICADO
   - +3 novos widgets (`_buildQualityBanner`, `_buildQualityDetailsCard`, `_buildQualityMetric`)
   - +100 linhas de código
   - Integração com serviço de análise

3. **`pubspec.yaml`** ✅ JÁ CONTÉM
   - `image: ^4.0.17` (já presente, nenhuma mudança necessária)

### Dependências
```yaml
dependencies:
  image: ^4.0.17  # ✅ Já presente
  camera: ^0.11.0+2  # Para captura de foto
  path_provider: ^2.1.0  # Para arquivo temporário
```

---

## ⚙️ Configuração Recomendada

No `image_quality_analyzer.dart`, você pode ajustar thresholds:

```dart
// Brightness ideal
if (brightness >= 120 && brightness <= 230) {
  overallScore += 20;  // ← Ajuste se necessário
}

// Contrast mínimo
if (contrast > 40) {  // ← Pode baixar para 35 se muito restritivo
  overallScore += 25;
}

// Score mínimo para aceitar
bool get isAcceptable => overallScore >= 60;  // ← Default 60
```

---

## 📈 Métricas de Sucesso

- [ ] Score >= 60 não bloqueia envio
- [ ] Score < 60 mostra aviso claro
- [ ] Recomendações são específicas
- [ ] UI responsiva (análise <= 2 segundos)
- [ ] Nenhuma crash em edge cases
- [ ] Acurácia API melhora 5-8%

