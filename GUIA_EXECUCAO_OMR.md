# Guia de Execução Prática — Pipeline OMR Completo

**Objetivo**: Processar um cartão resposta do inicio ao fim com instruções passo-a-passo.

## Fluxo Simplificado (Versão Rápida)

```bash
# 1. Setup (uma vez)
cd /home/luiz/cartao-resposta
export ANTHROPIC_API_KEY="sk-ant-..."
pip install opencv-python-headless numpy imutils scikit-learn anthropic Pillow

# 2. Processar imagem
python api_backend.py --input cartao.jpg --num_questoes 25 --num_colunas 2

# 3. Ver resultado em resultado_final.json
cat /tmp/resultado_final.json | jq .
```

---

## Fluxo Detalhado (Versão Completa)

### Fase 1: Preparação

```bash
# 1.1 Localizar imagem de cartão
ls -lh test_images/*.jpeg

# 1.2 Definir configuração
NUM_QUESTOES=25
NUM_COLUNAS=2
GABARITO_ARQUIVO="skills/omr-scanner/references/gabarito_exemplo.json"
IMAGEM="test_images/WhatsApp Image 2026-02-21 at 19.33.50.jpeg"

# 1.3 Confirmar estrutura
echo "Verificando estrutura..."
test -f "$IMAGEM" && echo "✓ Imagem OK" || echo "✗ Imagem não encontrada"
test -f "$GABARITO_ARQUIVO" && echo "✓ Gabarito OK" || echo "✗ Gabarito não encontrado"
test -f "api_backend.py" && echo "✓ Backend OK" || echo "✗ Backend não encontrado"
```

---

### Fase 2: Executar Pipeline Principal

```bash
# 2.1 INICIE O SERVIDOR API (terminal 1)
cd /home/luiz/cartao-resposta
python -m uvicorn api_backend:app --host 0.0.0.0 --port 8000 --reload

# Esperado:
# Uvicorn running on http://0.0.0.0:8000
# Application startup complete
```

```bash
# 2.2 EM OUTRO TERMINAL, EXECUTE O PROCESSAMENTO (terminal 2)
curl -X POST http://localhost:8000/processar_cartao \
  -F "file=@test_images/WhatsApp\ Image\ 2026-02-21\ at\ 19.33.50.jpeg" \
  -F "num_questoes=25" \
  -F "num_colunas=2" \
  -F "retornar_imagens=true" \
  -F "retornar_debug=true" \
  -F "salvar_debug=true" \
  | jq . > /tmp/resultado_raw.json

echo "Status: $?"
```

```bash
# 2.3 INSPECIONAR RESULTADO
cat /tmp/resultado_raw.json | jq '.respostas'       # Respostas detectadas
cat /tmp/resultado_raw.json | jq '.diagnostico'    # Diagnóstico
cat /tmp/resultado_raw.json | jq '.notaFinal'      # Nota
```

---

### Fase 3: Validação Manual

```bash
# 3.1 COMPARAR COM GABARITO
# Edite gabarito_exemplo.json com gabarito correto:
cat skills/omr-scanner/references/gabarito_exemplo.json | jq .gabarito

# 3.2 VERIFICAR PRECISÃO MANUALMENTE
# Abra em editor de texto e compare

# 3.3 VISUALIZAR IMAGENS DEBUG
# As imagens foram salvas em /tmp/:
ls -lh /tmp/omr_*.png

# Visualizar a imagem final anotada
# macOS:
open /tmp/omr_resultado_anotado.png

# Linux:
xdg-open /tmp/omr_resultado_anotado.png

# Ou converter para base64 e visualizar em navegador
python3 << 'EOF'
import base64
import json

with open('/tmp/resultado_raw.json') as f:
    data = json.load(f)

if 'debug_images' in data:
    img_b64 = data['debug_images'].get('resultado_final', '')
    if img_b64:
        # Salvar em arquivo
        with open('/tmp/resultado_visual.png', 'wb') as f:
            f.write(base64.b64decode(img_b64))
        print("✓ Imagem salva em /tmp/resultado_visual.png")
EOF
```

---

### Fase 4: Troubleshooting

```bash
# 4.1 SE A RESPOSTA ESTÁ ERRADA
# Checar logs de debug

python3 << 'EOF'
import json

with open('/tmp/resultado_raw.json') as f:
    resultado = json.load(f)

print("=== DIAGNÓSTICO ===")
print(f"Contraste: {resultado.get('diagnostico', {}).get('contraste_global', '?')}")
print(f"Brilho: {resultado.get('diagnostico', {}).get('brilho_global', '?')}")
print(f"Iluminação: {resultado.get('diagnostico', {}).get('perfil_iluminacao', '?')}")
print(f"Bolhas detectadas: {resultado.get('diagnostico', {}).get('bolhas_detectadas', '?')}")
print(f"Questões totais: {resultado.get('diagnostico', {}).get('questoes_totais', '?')}")
print(f"Warnings: {resultado.get('diagnostico', {}).get('warnings', [])}")

print("\n=== RESPOSTAS COM BAIXA CONFIANÇA ===")
for q, r in resultado.get('respostas', {}).items():
    meta = resultado.get('detalhes_por_questao', {}).get(q, {})
    conf = meta.get('confianca', 0.0)
    if conf < 0.85:
        print(f"Q{q}: {r} (confiança: {conf:.2f})")
EOF

# 4.2 SE CONTRASTE < 40
# O sistema já aplicou CLAHE, mas pode tentar:
# - Tirar nova foto com melhor iluminação
# - Se não conseguir, usar Claude Vision (Passo 6B)

# 4.3 SE BOLHAS NÃO SÃO DETECTADAS
# Verificar método de detecção usado:
cat /tmp/resultado_raw.json | \
  jq '.detalhes_por_questao | .[] | select(.metodo != "fill_rate")'
```

---

## Batch Processing (Múltiplas Imagens)

```bash
#!/bin/bash
# script: processar_lote.sh

PASTA_ENTRADA="/home/luiz/cartao-resposta/test_images"
PASTA_SAIDA="/tmp/cartoes_processados"
GABARITO_JSON=$(cat << 'EOF'
{
  "1": "A", "2": "C", "3": "B", "4": "E", "5": "D",
  "6": "A", "7": "C", "8": "B", "9": "D", "10": "E",
  "11": "B", "12": "A", "13": "C", "14": "D", "15": "E",
  "16": "A", "17": "B", "18": "C", "19": "D", "20": "E",
  "21": "C", "22": "A", "23": "D", "24": "B", "25": "E"
}
EOF
)

mkdir -p "$PASTA_SAIDA"

echo "Processando cartões em: $PASTA_ENTRADA"
echo "Salvando resultados em: $PASTA_SAIDA"
echo ""

TOTAL=0
ACERTOS=0
ERROS=0

for imagem in "$PASTA_ENTRADA"/*.jpeg; do
    [ -f "$imagem" ] || continue

    NOME=$(basename "$imagem")
    echo -n "Processando $NOME... "

    RESULTADO=$(curl -s -X POST http://localhost:8000/processar_cartao \
      -F "file=@$imagem" \
      -F "num_questoes=25" \
      -F "num_colunas=2")

    if [ $? -eq 0 ]; then
        # Salvar resultado
        echo "$RESULTADO" | jq . > "$PASTA_SAIDA/${NOME%.jpeg}.json"

        # Extrair nota
        NOTA=$(echo "$RESULTADO" | jq '.notaFinal // 0')
        PRECISAO=$(echo "$RESULTADO" | jq '.diagnostico.precisao_estimada // 0')

        echo "✓ Nota: $NOTA | Precisão: $PRECISAO"

        ((TOTAL++))
        if (( $(echo "$NOTA >= 7" | bc -l) )); then
            ((ACERTOS++))
        else
            ((ERROS++))
        fi
    else
        echo "✗ Erro no processamento"
        ((ERROS++))
    fi
done

echo ""
echo "=== RESUMO ==="
echo "Total: $TOTAL"
echo "Bom (≥7): $ACERTOS"
echo "Ruim (<7): $ERROS"
echo ""
echo "Resultados em: $PASTA_SAIDA"
```

Executar:
```bash
chmod +x processar_lote.sh
./processar_lote.sh | tee batch_log.txt
```

---

## Validação Automática com Ground Truth

Se houver gabarito correto (ground truth):

```bash
python3 << 'EOF'
import json
import os

# Carregar resultado
with open('/tmp/resultado_raw.json') as f:
    resultado = json.load(f)

# Gabarito correto
GABARITO_CORRETO = {
    "1": "A", "2": "C", "3": "B", "4": "E", "5": "D",
    # ... complete com gabarito real ...
    "25": "E"
}

respostas_aluno = resultado.get('respostas', {})

# Contar acertos/erros
acertos = 0
erros = 0
brancos = 0

for num_q, resp_aluno in respostas_aluno.items():
    if resp_aluno == "BRANCO":
        brancos += 1
    elif resp_aluno == GABARITO_CORRETO.get(num_q):
        acertos += 1
    else:
        erros += 1
        print(f"Q{num_q}: esperado {GABARITO_CORRETO.get(num_q)}, detectado {resp_aluno}")

total = len(GABARITO_CORRETO)
precisao = (acertos / total) * 100

print(f"\n=== VALIDAÇÃO ===")
print(f"Acertos: {acertos}/{total}")
print(f"Erros: {erros}/{total}")
print(f"Brancos: {brancos}/{total}")
print(f"Precisão: {precisao:.2f}%")

if precisao >= 95:
    print("✓ EXCELENTE (≥95%)")
elif precisao >= 85:
    print("✓ BOM (≥85%)")
elif precisao >= 70:
    print("⚠ ACEITÁVEL (≥70%)")
else:
    print("✗ RUIM (<70%) — revisar configurações")
EOF
```

---

## Integração com App Flutter

Se estiver usando app Flutter:

```dart
// lib/services/omr_service.dart

class OMRService {
  static const String API_BASE = "http://192.168.1.100:8000";

  static Future<Map<String, dynamic>> procesarCartao(
    File imageFile,
    int numQuestoes,
    int numColunas,
  ) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$API_BASE/processar_cartao'),
    );

    request.files.add(
      await http.MultipartFile.fromPath('file', imageFile.path),
    );
    request.fields.addAll({
      'num_questoes': numQuestoes.toString(),
      'num_colunas': numColunas.toString(),
      'retornar_imagens': 'true',
    });

    var response = await request.send();
    var responseData = await response.stream.bytesToString();

    return json.decode(responseData);
  }
}

// Usar:
final resultado = await OMRService.procesarCartao(
  imagemArquivo,
  25,
  2,
);

print("Respostas: ${resultado['respostas']}");
print("Nota: ${resultado['notaFinal']}");
```

---

## Monitoramento em Produção

```bash
# Criar log de processamento
python3 << 'EOF'
import json
import csv
from datetime import datetime
from pathlib import Path

LOG_FILE = "/tmp/omr_processing_log.csv"
RESULTADO_FILE = "/tmp/resultado_raw.json"

with open(RESULTADO_FILE) as f:
    resultado = json.load(f)

# Preparar linha do CSV
linha = {
    'timestamp': datetime.now().isoformat(),
    'nota': resultado.get('notaFinal', 0),
    'acertos': resultado.get('acertos', 0),
    'erros': resultado.get('erros', 0),
    'metodo': resultado.get('metodo_processamento', ''),
    'confianca': resultado.get('confianca_geral', 0),
    'questoes_fallback': len(resultado.get('questoes_com_fallback', [])),
    'contraste': resultado.get('diagnostico', {}).get('contraste_global', 0),
    'brilho': resultado.get('diagnostico', {}).get('brilho_global', 0),
}

# Adicionar ao CSV
path = Path(LOG_FILE)
write_header = not path.exists()

with open(LOG_FILE, 'a', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=linha.keys())
    if write_header:
        writer.writeheader()
    writer.writerow(linha)

print(f"✓ Log gravado em {LOG_FILE}")
EOF

# Visualizar log
tail -20 /tmp/omr_processing_log.csv

# Estatísticas
python3 << 'EOF'
import csv
import statistics

with open('/tmp/omr_processing_log.csv') as f:
    reader = csv.DictReader(f)
    notas = [float(row['nota']) for row in reader]

if notas:
    print(f"Nota média: {statistics.mean(notas):.2f}")
    print(f"Mediana: {statistics.median(notas):.2f}")
    print(f"Desvio padrão: {statistics.stdev(notas):.2f}")
    print(f"Mín: {min(notas):.2f}, Máx: {max(notas):.2f}")
EOF
```

---

## Checklist Pré-Produção

Antes de usar em produção:

- [ ] API Python rodando (`python -m uvicorn api_backend:app`)
- [ ] ANTHROPIC_API_KEY configurada
- [ ] Gabarito correto em `gabarito_exemplo.json`
- [ ] Testado com 5+ cartões reais
- [ ] Precisão ≥ 95% em test set
- [ ] Logs sendo gerados e monitorados
- [ ] Backup de resultados automatizado
- [ ] Fallback Claude Vision testado
- [ ] Documentação atualizada
- [ ] Equipe treinada

---

## Suporte Rápido

| Problema | Solução |
|----------|---------|
| API não inicia | `pip install -r requirements.txt` |
| Imagem preta | Verificar iluminação, tirar nova foto |
| Contraste baixo | CLAHE ativado automaticamente |
| Bolhas não detectadas | Claude Vision fallback (Passo 6B) |
| Muitas ambiguidades | Reduzir escala ou usar nova foto |
| Lenta (> 5s/imagem) | Verificar dimensão, reduzir MAX_IMAGE_WIDTH |

---

*Guia prático para execução do pipeline OMR — Versão 2.0 (Março 2026)*
