# 📸 Pasta de Imagens para Testes

## Estrutura de Pastas

```
test_images/
├── light_conditions/
│   ├── luz_direta/              (20 imagens - luz solar direta)
│   ├── sombra_parcial/          (20 imagens - parcialmente sombreado)
│   ├── luz_artificial/          (20 imagens - luz artificial/noite)
│   ├── camera_baixa_qualidade/  (20 imagens - < 5MP)
│   └── camera_alta_qualidade/   (20 imagens - > 12MP)
└── ground_truth.json            (gabarito esperado - CRIAR MANUALMENTE)
```

## Como Usar

### 1. Adicionar Imagens de Teste

Copie as imagens JPG/PNG dos cartões-resposta para as respectivas pastas:

```bash
# Exemplo: luz direta
cp /caminho/para/fotos/luz_direta/*.jpg test_images/light_conditions/luz_direta/

# Exemplo: sombra
cp /caminho/para/fotos/sombra/*.jpg test_images/light_conditions/sombra_parcial/
```

### 2. Criar Ground Truth (Gabarito Esperado)

Crie um arquivo `ground_truth.json` com os gabaritos esperados:

```json
{
  "imagem_001": {
    "1": "A",
    "2": "B",
    "3": "C",
    "4": "D",
    "5": "E",
    "6": "A",
    "7": "B",
    "8": "C",
    "9": "D",
    "10": "E"
  },
  "imagem_002": {
    "1": "B",
    "2": "C",
    ...
  }
}
```

**Dica:** O nome da chave deve corresponder ao nome do arquivo (sem extensão)

### 3. Executar Testes

```bash
# Teste básico (sem ground truth)
python test_runner.py --dataset test_images/light_conditions/luz_direta

# Teste com validação (com ground truth)
python test_runner.py \
  --dataset test_images \
  --ground-truth test_images/ground_truth.json \
  --questoes 10 \
  --colunas 1
```

## Estrutura Ground Truth Detalhada

```json
{
  "nome_arquivo_sem_extensao": {
    "numero_questao": "resposta_esperada",
    "1": "A",
    "2": "B",
    "3": "C",
    "4": "D",
    "5": "E",
    "6": "A",
    "7": "B",
    "8": "C",
    "9": "D",
    "10": "E",
    ...
  }
}
```

## Exemplo Prático

Se você tem:
- `test_images/light_conditions/luz_direta/cartao_001.jpg`
- `test_images/light_conditions/luz_direta/cartao_002.jpg`

O ground_truth.json seria:

```json
{
  "cartao_001": {
    "1": "A",
    "2": "B",
    "3": "C",
    "4": "D",
    "5": "E",
    "6": "A",
    "7": "B",
    "8": "C",
    "9": "D",
    "10": "E"
  },
  "cartao_002": {
    "1": "B",
    "2": "C",
    "3": "D",
    "4": "E",
    "5": "A",
    "6": "B",
    "7": "C",
    "8": "D",
    "9": "E",
    "10": "A"
  }
}
```

## Passos Recomendados

1. **Coletar 20 imagens** em cada condição (total 100 imagens)
2. **Marcar o gabarito esperado** manualmente em um documento
3. **Criar `ground_truth.json`** com todos os gabaritos
4. **Executar `test_runner.py`** para validação automática
5. **Analisar relatório** de Accuracy, Precision, Recall, F1

## Metas de Validação

```
✅ Accuracy      > 99%
✅ Precision     > 99.5%
✅ Recall        > 99%
✅ F1-Score      > 99%
✅ Tempo/imagem  < 1s
```

## Troubleshooting

**Erro: "Nenhuma imagem encontrada"**
- Verifique se as imagens estão em `.jpg` ou `.png`
- Confira o caminho da pasta

**Accuracy baixa (< 95%)**
- Aumentar rigor do sistema em `image_processing.py`
- Ajustar thresholds em `analisar_preenchimento_avancado()`
- Verificar qualidade das imagens

**Arquivo ground_truth não encontrado**
- Certificar que está em `test_images/ground_truth.json`
- Verificar nomes dos arquivos (sem extensão, case-sensitive)

---

**Pronto! Agora é só adicionar as imagens e executar os testes.** 🎯
