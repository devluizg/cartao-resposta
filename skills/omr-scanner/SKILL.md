---
name: omr-scanner
description: >
  Processa imagens de folhas de respostas (gabaritos OMR/bubble sheets) utilizando
  um pipeline de visão computacional determinístico com OpenCV, com fallback inteligente
  para a API Claude Vision quando a detecção automática falha ou produz resultados
  ambíguos. Extrai, pontua e gera relatório de acurácia para gabaritos de múltipla escolha.
  Use esta skill sempre que o usuário mencionar: escaneamento de gabaritos, correção
  automática de provas, OMR, bubble sheet, folha de respostas, leitura óptica de marcas,
  ou quando pedir para processar imagens de provas ENEM/vestibular com alternativas A-E.
  Também acione quando houver pipeline de visão computacional + Claude para documentos
  estruturados. Grau de Liberdade: BAIXO — execute as etapas em sequência estrita.

  Trigger phrases:
  - "escanear gabarito" / "scan answer sheet" / "ler folha de respostas"
  - "corrigir prova automaticamente" / "grade bubble sheet"
  - "pipeline OMR OpenCV" / "optical mark recognition"
  - "processar gabarito ENEM / vestibular"
  - "detectar bolhas marcadas em imagem de prova"
---

# OMR Scanner — Procedimento Operacional Padrão (SOP)

## Visão Geral do Pipeline

```
ENTRADA (imagem) → [Passo 1] Pré-processamento
                 → [Passo 2] Detecção do documento
                 → [Passo 3] Transformação de perspectiva
                 → [Passo 4] Binarização e detecção de bolhas
                 → [Passo 5] Classificação das respostas
                 → [Passo 6] Validação + Fallback Claude Vision  ← loop se necessário
                 → [Passo 7] Pontuação e relatório final
                 → SAÍDA (JSON + imagem anotada)
```

**REGRA DE OURO:** Nunca pule etapas. Se uma etapa falhar, acione o fallback definido antes de prosseguir.

---

## Pré-requisitos

Antes de iniciar, confirme as dependências:

```bash
pip install opencv-python-headless imutils numpy anthropic Pillow --break-system-packages
```

Confirme o gabarito de referência (chave de respostas) e o arquivo de imagem de entrada.
Se não houver chave de respostas, pergunte ao usuário antes de continuar.

---

## Passo 1 — Pré-processamento da Imagem

Execute o script de pré-processamento:

```bash
python scripts/processamento_imagem.py \
  --input <caminho_da_imagem> \
  --output /tmp/omr_preprocessed.png \
  --config references/configuracoes_normalizacao.json
```

**Saída esperada em stdout (JSON):**
```json
{
  "status": "ok",
  "resolucao_original": [H, W],
  "resolucao_processada": [H, W],
  "nivel_contraste": 0.0,
  "iluminacao_uniforme": true,
  "arquivo_saida": "/tmp/omr_preprocessed.png"
}
```

**Tratamento de erros:**
- Se `"iluminacao_uniforme": false` → o script aplica CLAHE automaticamente (não interrompa)
- Se `"nivel_contraste" < 0.3` → ALERTA: imagem pode ser muito clara/escura; logue e continue
- Se o script retornar `"status": "erro"` → **PARE. Informe o usuário e solicite imagem melhor.**

---

## Passo 2 — Detecção do Documento (Contorno da Folha)

O script do Passo 1 já emite a imagem pré-processada. Agora execute a detecção de contorno:

```bash
python scripts/processamento_imagem.py \
  --input /tmp/omr_preprocessed.png \
  --mode detectar_documento \
  --output /tmp/omr_doc_detected.png
```

**Saída esperada:**
```json
{
  "status": "ok",
  "contorno_encontrado": true,
  "pontos_corner": [[x1,y1],[x2,y2],[x3,y3],[x4,y4]],
  "area_contorno": 12345
}
```

**Tratamento de erros:**
- Se `"contorno_encontrado": false` → **acione o Fallback Claude Vision (Passo 6A)** imediatamente
- Se `"area_contorno"` for menor que 30% da área total → provável detecção incorreta → acione Passo 6A

---

## Passo 3 — Transformação de Perspectiva (Bird's-Eye View)

```bash
python scripts/processamento_imagem.py \
  --input /tmp/omr_doc_detected.png \
  --mode perspectiva \
  --pontos "<json_dos_pontos_corner>" \
  --output /tmp/omr_warped.png
```

**Saída esperada:**
```json
{
  "status": "ok",
  "arquivo_saida": "/tmp/omr_warped.png",
  "dimensoes_finais": [842, 595]
}
```

**Tratamento de erros:**
- Se `"status": "erro"` → o documento está muito distorcido → acione Passo 6A (Claude Vision total)

---

## Passo 4 — Binarização e Detecção de Bolhas

```bash
python scripts/processamento_imagem.py \
  --input /tmp/omr_warped.png \
  --mode detectar_bolhas \
  --output /tmp/omr_bubbles.png \
  --output-json /tmp/bolhas_detectadas.json
```

**Saída esperada em `/tmp/bolhas_detectadas.json`:**
```json
{
  "total_bolhas": 100,
  "bolhas_por_questao": 5,
  "num_questoes": 20,
  "bolhas": [
    {"questao": 1, "alternativa": "A", "pixels_preenchidos": 1423, "marcada": true},
    ...
  ],
  "bolhas_ambiguas": [{"questao": 3, "motivo": "dois_preenchimentos", "candidatos": ["B","C"]}]
}
```

**Tratamento de erros:**
- Se `"total_bolhas"` diferir do esperado em ±10% → logue aviso mas continue
- Se `"bolhas_ambiguas"` não for vazio → **cada uma dessas questões vai para o Passo 6B**

---

## Passo 5 — Classificação das Respostas

```bash
python scripts/processamento_imagem.py \
  --input-json /tmp/bolhas_detectadas.json \
  --mode classificar \
  --gabarito references/gabarito_exemplo.json \
  --output-json /tmp/respostas_classificadas.json
```

**Saída esperada:**
```json
{
  "respostas_detectadas": {"1": "A", "2": "C", "3": "AMBIGUA", ...},
  "questoes_ambiguas": [3],
  "confianca_media": 0.91
}
```

---

## Passo 6 — Validação e Fallback Claude Vision

### 6A — Fallback Total (documento não detectado)

Se o pipeline OpenCV falhou completamente (Passos 2 ou 3), execute:

```bash
python scripts/claude_vision_fallback.py \
  --input <caminho_imagem_original> \
  --modo completo \
  --gabarito references/gabarito_exemplo.json \
  --output-json /tmp/respostas_claude_vision.json
```

O script envia a imagem completa para Claude Vision com prompt estruturado.
Leia `/tmp/respostas_claude_vision.json` — se `"status": "ok"`, use como resposta final.
Se `"status": "erro"` → **PARE. Informe o usuário que a imagem não pode ser processada.**

### 6B — Fallback Parcial (bolhas ambíguas)

Para questões marcadas como `"AMBIGUA"`, execute:

```bash
python scripts/claude_vision_fallback.py \
  --input /tmp/omr_warped.png \
  --modo parcial \
  --questoes-ambiguas "[3, 7, 12]" \
  --output-json /tmp/resolucao_ambiguas.json
```

**Loop de Validação:**
```
GERAR (OpenCV classifica) → VALIDAR (checar ambiguidades) → CORRIGIR (Claude Vision resolve)
```
Mescle `/tmp/respostas_classificadas.json` com `/tmp/resolucao_ambiguas.json` antes do Passo 7.

---

## Passo 7 — Pontuação e Relatório Final

```bash
python scripts/metricas_acuracia.py \
  --respostas /tmp/respostas_classificadas.json \
  --gabarito references/gabarito_exemplo.json \
  --output-json /tmp/resultado_final.json \
  --output-imagem /tmp/omr_resultado_anotado.png
```

**Saída obrigatória em `/tmp/resultado_final.json`:**
```json
{
  "aluno_id": "...",
  "acertos": 17,
  "erros": 2,
  "em_branco": 1,
  "nota": 8.5,
  "percentual_acerto": 85.0,
  "detalhes_por_questao": [...],
  "metodo_processamento": "opencv+claude_fallback",
  "confianca_geral": 0.94,
  "alertas": []
}
```

**Apresente ao usuário:**
1. O caminho do `/tmp/resultado_final.json`
2. O caminho da `/tmp/omr_resultado_anotado.png` (imagem com acertos/erros anotados)
3. Um resumo em texto: nota, percentual de acerto, questões com fallback IA

---

## Referências

- `references/configuracoes_normalizacao.json` — parâmetros CLAHE, threshold, blur
- `references/gabarito_exemplo.json` — formato de chave de respostas
- `references/resposta_api_exemplo.json` — formato esperado da resposta Claude Vision

Leia esses arquivos se precisar ajustar parâmetros ou validar formatos de entrada/saída.

---

## Checklist Final

Antes de encerrar, confirme:
- [ ] `/tmp/resultado_final.json` existe e tem campo `"nota"`
- [ ] `/tmp/omr_resultado_anotado.png` existe
- [ ] Questões ambíguas foram resolvidas (array `"alertas"` vazio ou explicado)
- [ ] Se houve fallback Claude Vision, o campo `"metodo_processamento"` reflete isso
