# Relatório do Sistema — Correção de Cartão Resposta
**Última atualização:** 21/02/2026
**Projeto:** SimuladoApp — Leitor óptico de cartão resposta
**Repositório:** `/home/luiz/cartao-resposta/`

---

## 1. Visão Geral do Sistema

O sistema é composto por três camadas que se comunicam entre si:

```
┌─────────────────────┐       foto JPEG        ┌──────────────────────────┐
│   App Flutter       │ ──────────────────────► │  API Python (FastAPI)    │
│  (leitor_cartao/)   │ ◄────────────────────── │  api_backend.py          │
│                     │     JSON com respostas  │  image_processing.py     │
└─────────────────────┘                         │  analysis.py             │
         ▲                                      └──────────────────────────┘
         │ gabarito + respostas
         ▼
┌─────────────────────┐
│  Django Backend     │  (simuladoapp_v2)
│  Gabaritos, Turmas  │  gera PDFs dos cartões
│  Resultados via API │  para impressão
└─────────────────────┘
```

---

## 2. Gerador de Cartão Resposta para Impressão (PDF)

### Arquivo
```
/home/luiz/simuladoapp_v2/questions/pdf_generator.py
```

### O que faz
Gera arquivos PDF dos cartões resposta para impressão em papel A4. É chamado pelo Django quando o professor solicita a impressão de cartões para uma turma.

### Layout do Cartão (medidas exatas do PDF)

```
┌─────────────────────────────────────────┐
│  [QR Code]   CARTÃO RESPOSTA   TIPO: N  │  ← Cabeçalho
│  Nome: ___________  Turma: __________   │
├──────────────────┬──────────────────────┤
│  A  B  C  D  E  │  A  B  C  D  E       │  ← Letras (4.5mm ACIMA do retângulo)
│ ┌──────────────┐│ ┌──────────────────┐  │
│ │01 ○  ○  ○  ○  ○│ │14 ○  ○  ○  ○  ○  │  │
│ │02 ○  ○  ○  ○  ○│ │15 ●  ○  ○  ○  ○  │  │  ← Coluna de bolhas
│ │  ...         ││ │  ...             │  │
│ │13 ○  ○  ●  ○  ○│ │25 ○  ○  ○  ●  ○  │  │
│ └──────────────┘│ └──────────────────┘  │
└──────────────────┴──────────────────────┘
```

### Constantes de Design Críticas (usadas pelo OMR)

| Parâmetro | Valor | Relevância para detecção |
|---|---|---|
| `raio_bolha` | **2,5 mm** (Ø 5mm) | Tamanho real das bolhas |
| `espaco_entre_circulos` | **7,0 mm** | Distância horizontal entre bolhas A→E |
| `espaco_entre_questoes` | **8,5 mm** | Distância vertical entre linhas |
| `margem_interna` | **5,0 mm** | Espaço dentro do retângulo até a 1ª bolha |
| `largura_bolhas_span` | **28 mm** (4 × 7mm) | Largura total das 5 bolhas |
| `largura_necessaria` | **43 mm** | Largura total da caixa de bolhas |
| `largura_indice` | **9,0 mm** | Largura da coluna de números (Q01, Q02…) |
| Y da 1ª bolha | **9,25 mm** do topo | 5mm margem + 0,5 × 8,5mm espaçamento |

### Configurações de Múltiplas Versões

O sistema gera até **5 versões embaralhadas** (VersaoGabarito) de cada prova. Cada versão:
- Tem um UUID único impresso no QR Code
- Tem as alternativas reordenadas aleatoriamente
- Tem um gabarito correspondente armazenado no banco

### Número de Colunas por Quantidade de Questões

| Questões | Colunas | Largura por coluna |
|---|---|---|
| 1–23 | 1 coluna | 52 mm (43mm bolhas + 9mm índice) |
| 24–45 | 2 colunas | Dividido no A4 |
| 46+ | 3 colunas | Dividido no A4 |

### Tecnologia
- **ReportLab** (geração de PDF com medidas precisas em mm)
- **WeasyPrint** (alternativa via HTML/CSS)
- Chamado via Django view em `questions/views.py`

---

## 3. Telas de Correção no Flutter

### App Flutter
```
/home/luiz/cartao-resposta/leitor_cartao/
```

### Fluxo completo de correção

```
SelectionScreen
    │  usuário seleciona turma + aluno + simulado
    ▼
CameraCaptureScreen          ← Câmera ao vivo com overlay guia
    │  foto capturada
    ▼
[API Python /processar_cartao]   ← Upload da foto + detecção OCR
    │  JSON: {respostas: {...}, diagnostico: {...}}
    ▼
CartaoRespostaPreviewScreen  ← Mostra imagem processada + resultado
    │  professor confirma
    ▼
[consumir crédito via CreditManager]
    │
    ▼
ResultadoScreen              ← Nota final, acertos, estatísticas
```

---

### 3.1 Tela de Câmera (`camera_capture_screen.dart`)

**Arquivo:** `leitor_cartao/lib/screens/camera_capture_screen.dart`

#### Função
Tela de captura guiada com câmera ao vivo. Exibe um overlay amarelo proporcional ao papel A4 para ajudar o professor a enquadrar o cartão corretamente.

#### Funcionalidades implementadas
- **Câmera traseira** em resolução `high` (1280×720), foco automático, flash desligado por padrão
- **Overlay de enquadramento** — moldura amarela proporcional A4 (ratio 1:1.414) com:
  - Cantos em "L" pintados por CustomPainter
  - Quadradinhos nos 4 cantos (simulando os marcadores de canto do cartão)
  - Linhas divisórias por coluna (1, 2 ou 3 conforme número de questões)
  - Label "CARTÃO RESPOSTA" semitransparente no centro
- **Dica de iluminação** — banner inferior: "Boa iluminação • Sem sombras • Cartão reto"
- **Toggle de flash** — botão lateral para ligar/desligar lanterna
- **Preview após captura** — modo de revisão com `InteractiveViewer` (zoom 0.5×–4×)
- **Botões REFAZER / USAR ESTA FOTO** — permite repetir a foto antes de enviar
- **Gerenciamento de ciclo de vida** — libera câmera ao pausar, reinicia ao retomar

#### Lógica de número de colunas (automático)
```dart
int get _numColunas {
  if (widget.numQuestoes <= 23) return 1;
  if (widget.numQuestoes <= 45) return 2;
  return 3;
}
```

#### Retorno para a tela anterior
```dart
CaptureResult(imageFile: arquivoFinal, numColunas: _numColunas)
```

---

### 3.2 Tela de Preview da Correção (`cartao_resposta_preview_screen.dart`)

**Arquivo:** `leitor_cartao/lib/screens/cartao_resposta_preview_screen.dart`

#### Função
Tela intermediária exibida **após** a API processar o cartão e **antes** de confirmar o resultado. Exibe a imagem processada com as marcações detectadas e permite ao professor revisar antes de consumir um crédito.

#### Dados recebidos
| Campo | Tipo | Descrição |
|---|---|---|
| `imagemProcessada` | `Uint8List` | Imagem com marcações sobrepostas (retornada pela API) |
| `respostasAluno` | `Map<String, String>` | Ex: `{"1": "A", "2": "C", ...}` |
| `gabarito` | `Map<String, String>` | Gabarito da versão da prova |
| `nomeAluno` | `String` | Nome do aluno |
| `notaFinal` | `double` | Nota calculada |
| `tipoProva` | `int` | Número da versão (1–5) |
| `alunoId`, `simuladoId`, `turmaId` | `int?` | IDs para integração com Django |

#### Funcionalidades implementadas
- **Verificação de créditos** no `initState` via `CreditManager.getAvailableCredits()`
- **Badge de créditos** na AppBar — verde se > 0, vermelho se esgotado
- **Visualização do cartão** com zoom interativo (`InteractiveViewer` 0.5×–3×)
- **Card de informações** — nome, turma, simulado, versão, acertos/total
- **Fluxo de confirmação com créditos:**
  1. Verifica créditos em tempo real (`forceRefresh: true`)
  2. Se sem créditos → abre dialog `showInsufficientCreditsDialog` → redireciona para loja
  3. Se com créditos → chama `consumeCredit()` → navega para `ResultadoScreen`
- **Dialog de loading** durante o consumo do crédito
- **Botão RECOMEÇAR** — volta para a tela anterior sem consumir crédito

#### Paleta de cores (modo escuro)
```dart
static const Color primary    = Color(0xFF0DA6F2);  // Azul primário
static const Color bgDark     = Color(0xFF121E25);  // Fundo
static const Color surfaceDark = Color(0xFF1A2A33); // Cards
static const Color success    = Color(0xFF16A34A);  // Verde (confirmar)
static const Color danger     = Color(0xFFDC2626);  // Vermelho (recomeçar)
```

---

## 4. API de Processamento Python

### Arquivo principal
```
/home/luiz/cartao-resposta/api_backend.py
```

### Endpoint principal
```
POST /processar_cartao
  file: UploadFile           (foto JPEG/PNG)
  num_questoes: int          (total de questões)
  num_colunas: int           (número de colunas)
  threshold: int = 150       (limiar de preenchimento)
  sensitivity: float = 0.3   (sensibilidade)
  retornar_imagens: str      ("true" para incluir debug images em base64)
  retornar_debug: str        ("true" para incluir metadados de pré-processamento)
  auto_detect: bool          (detectar número de colunas automaticamente)
  salvar_debug: bool         (salvar imagens localmente)
```

### Resposta JSON
```json
{
  "respostas": {"1": "A", "2": "C", ...},
  "diagnostico": {
    "qualidade_imagem": 0.85,
    "qualidade_perspectiva": 1.0,
    "bolhas_detectadas": 25,
    "questoes_totais": 25,
    "perfil_iluminacao": "normal",
    "brilho_global": 167.2,
    "contraste_global": 39.1,
    "questoes_com_baixa_confianca": [4, 7],
    "warnings": ["Alternativa 'A' aparece 8 vezes"],
    "distribuicao_respostas": {"A": 5, "B": 6, "C": 4, "D": 6, "E": 4}
  },
  "debug_images": {
    "pre_processamento": "base64...",
    "perspectiva_corrigida": "base64...",
    "resultado_final": "base64..."
  }
}
```

---

## 5. Pipeline de Processamento de Imagem

**Arquivo:** `/home/luiz/cartao-resposta/image_processing.py`
**Arquivo:** `/home/luiz/cartao-resposta/analysis.py`

### Etapas do pipeline (em ordem)

```
Foto JPEG
    │
    ▼
1. redimensionar_imagem_otimizada()
   → Max 1500px de largura, mantém proporção

    │
    ▼
2. melhorar_pre_processamento_adaptativo()
   → Flash virtual (LAB normalization + Gaussian blur)
   → CLAHE adaptativo por brilho/contraste
   → Remoção de sombras
   → Binarização adaptativa (THRESH_BINARY_INV)
   → Retorna: binary (imagem binária) + metadados

    │
    ▼
3. corrigir_perspectiva()
   → Detecta 4 marcadores de canto (círculos pretos)
   → Aplica transformação de perspectiva
   → Fallback: HoughLines + RANSAC se marcadores não encontrados

    │
    ▼
4. detectar_retangulos_colunas()
   → Detecta as caixas retangulares de cada coluna de bolhas

    │
    ▼
5. [Para cada coluna ROI]:
   detectar_bolhas_avancado()
   → Método 1: HoughCircles Adaptativo
   → Método 2: Template Matching (disco sólido branco)
   → Método 3: MSER (regiões estáveis)
   → Método 4: Contornos com circularidade
   → Voting System: requer 2+ métodos concordando
   → Exclusão de zona de cabeçalho (A-E header)
   → Análise de fill rate por bolha

    │
    ▼
6. agrupar_bolhas_por_questoes()
   → DBSCAN com eps adaptativo (40% do espaçamento estimado)
   → KMeans como fallback se DBSCAN falha

    │
    ▼
7. analisar_questao()
   → Calcula fill rate de cada bolha por questão
   → Detecta resposta marcada (maior fill rate)
   → Detecta ambiguidade (múltiplas marcações)
   → Threshold adaptativo com análise estatística

    │
    ▼
JSON com respostas + imagem debug anotada
```

---

## 6. Estado Atual de Precisão

### Resultado por run (imagens 21/02/2026 — 7 fotos)

| Run | Divisor de escala | Precisão Global |
|---|---|---|
| Baseline (antes desta sessão) | 100 (original) | 46,86% |
| Fix: divisor=70 | 70 | **67,43%** ← melhor |
| Regressão: divisor=43 | 43 | 44,00% |
| **Estado atual** | **70 (revertido)** | **~67,43%** |

### Precisão por imagem (melhor run — divisor=70)

| Imagem | Precisão | Problema |
|---|---|---|
| 19.33.50 | ~92% | 2 questões com fill baixo |
| 19.33.51 | ~96% | 1 questão ambígua |
| 19.33.54 | ~88% | Linhas extras no DBSCAN |
| 19.33.55 | ~92% | 2 questões com fill baixo |
| 19.33.53 | ~88% | DBSCAN: +3 linhas extras |
| **19.33.45** | **~5%** | Contraste=39, linhas missing |
| **19.33.47** | **~0%** | Câmera mais próxima, ROI maior |

---

## 7. Problemas Identificados (Pendentes)

### Problema 1 — Estimativa de escala empírica
- **Causa:** `divisor=70` é empírico, não matemático (correto seria 43mm = largura real da caixa)
- **Impacto:** `raio_px` subestimado (~9px vs real ~14px) → fill rate amostrado em área menor que o ideal → leituras de "fill muito baixo"
- **Arquivo:** `image_processing.py`, função `_estimar_escala_imagem()`, linha ~717

### Problema 2 — Voting threshold acopla com raio
- **Causa:** `threshold_distancia = raio_px * 1.0` → com raio=14px, threshold=14px → mais detecções de ruído passam o filtro → DBSCAN confuso
- **Impacto:** Regressão ao mudar para divisor=43 (que é o matematicamente correto)
- **Arquivo:** `image_processing.py`, linha ~1012

### Problema 3 — DBSCAN encontra linhas extras
- **Sintoma:** "Detectadas 16 linhas (esperado 13)" em imagens que funcionam bem
- **Causa:** eps adaptativo ainda agrupa ruído em linhas extras em alguns casos
- **Impacto:** 1-3 questões deslocadas por imagem (~4-12% de perda por imagem)
- **Arquivo:** `image_processing.py`, função `agrupar_bolhas_por_questoes()`, linha ~1128

### Problema 4 — 19.33.45: imagem lavada (contraste=39)
- **Causa:** contrast<40 ativa `low_light=True` → parâmetros relaxados mas template matching ainda perde algumas linhas
- **Impacto:** ~5% de precisão (quase falha total)
- **Evidência visual:** debug.png mostra apenas 7-8 de 13 linhas detectadas na coluna 1

### Problema 5 — 19.33.47: câmera mais próxima
- **Causa:** ROI detectado = 384×1013px vs padrão ~244×674px (1,57× maior) → escala diferente muda todos os parâmetros de detecção
- **Impacto:** 0% de precisão no baseline; comportamento após divisor=70 não confirmado

---

## 8. Melhorias Implementadas Nesta Sessão

| Fix | Arquivo | Linha | Resultado |
|---|---|---|---|
| DBSCAN eps adaptativo (40% do espaçamento estimado) | `image_processing.py` | ~1128 | +5-10% estimado |
| CLAHE agressivo para contraste < 40 (3.5 / 12×12) | `image_processing.py` | ~254 | Melhora imagens lavadas |
| dark_thresh adaptativo para contraste < 40 | `image_processing.py` | ~290 | Melhora binarização lavada |
| Fix de polaridade em `detectar_marcadores_de_canto` | `image_processing.py` | ~486 | Correção de perspectiva mais estável |
| CLAHE mais agressivo em `corrigir_perspectiva` (4.0/4×4) | `image_processing.py` | ~596 | Melhor detecção com sombras |
| Revert divisor: 43 → 70 (eliminou regressão de 23%) | `image_processing.py` | ~717 | Restaurado 67,43% |

---

## 9. Próximos Passos Recomendados

### Prioridade Alta
1. **Confirmar revert** — rodar `python testar_em_lote.py` e confirmar retorno a 67,43%
2. **Corrigir voting threshold** — mudar de `raio_px * 1.0` para `max(raio_px * 0.5, 6)`:
   - Arquivo: `image_processing.py`, linha ~1012
   - Isso permite usar divisor=43 sem regressão
3. **Corrigir fill analysis** — raio interno mínimo de 10px:
   - `inner_r = max(int(r * 0.75), 10)` nas linhas ~1047 e ~1077

### Prioridade Média
4. **19.33.45** — baixar threshold do template matching para 0.20 em modo `low_light` (atualmente 0.35)
5. **Investigar 19.33.47** — capturar log detalhado para ver qual método falha no ROI grande

### Prioridade Baixa
6. **DBSCAN linhas extras** — implementar filtro pós-DBSCAN que mescla clusters com menos de 5 bolhas em clusters adjacentes

---

## 10. Como Executar

### Rodar API Python (FastAPI)
```bash
cd /home/luiz/cartao-resposta
uvicorn api_backend:app --host 0.0.0.0 --port 8000 --reload
```

### Rodar teste em lote
```bash
cd /home/luiz/cartao-resposta
python testar_em_lote.py 2>&1 | tee output_log_novo.txt
tail -10 output_log_novo.txt
```

### Rodar app Flutter
```bash
cd /home/luiz/cartao-resposta/leitor_cartao
flutter pub get
flutter run
```

### Configurações do teste em lote (`testar_em_lote.py`)
```python
GABARITO_CORRETO = {1: 'A', 2: 'C', ...}  # Editar conforme gabarito real
NUM_QUESTOES = 25
NUM_COLUNAS = 2
PASTA_IMAGENS = "/home/luiz/cartao-resposta/test_images"
PASTA_DEBUG   = "/home/luiz/cartao-resposta/debug_lote"
```

### Debug: imagens de saída por imagem
Após rodar o teste, `debug_lote/` conterá por cada imagem:
- `{nome}_binary.png` — imagem binária após pré-processamento
- `{nome}_debug.png` — imagem original com detecções sobrepostas (marcações azuis/verdes)
- `{nome}_meta.json` — metadados: brilho, contraste, perfil de iluminação

---

*Sistema desenvolvido para SimuladoApp — Plataforma de simulados educacionais (simuladoapp.com.br)*
