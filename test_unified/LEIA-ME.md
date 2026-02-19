# 🧪 Teste Interativo - Cartão Resposta

## Como Usar

### 1. Executar o Script

```bash
cd /home/luiz/cartao-resposta
python3 test_interativo.py
```

### 2. Configurar Parâmetros (na primeira execução)

```
Número de questões por cartão? (padrão 10): 10
Número de colunas? (padrão 1): 1
```

### 3. Processar Cada Imagem

Para cada imagem o programa vai:

1. **Processar a imagem** (pré-processamento, detecção de bolhas, análise)
2. **Mostrar o gabarito detectado**:
   ```
   Detectado: A B C D E - - C D E
   ```
3. **Pedir para você digitar o gabarito real**:
   ```
   Digite o gabarito real (10 alternativas)
   Alternativas: A, B, C, D, E
   Use '-' se a questão foi deixada em branco

   Gabarito: A B C D E
   ```

### 4. Ver Resultado Imediato

```
Detectado: A B C D E - - C D E
Real:      A B C D E A B C D E

Resultado:
   Acertos: 8/10
   Erros: 2/10
   Taxa de acerto: 80.0%

⚠️ Diferenças encontradas:
   ⚠️ Q6: Detectado=- vs Real=A
   ⚠️ Q7: Detectado=- vs Real=B
```

### 5. Relatório Final Automático

Ao final de todos os testes, o programa vai gerar:

```
📊 RELATÓRIO FINAL
================================================================================

WhatsApp Image 2026-02-19 at 08.1.jpeg
  Detectado: A B C D E - - C D E
  Real:      A B C D E A B C D E
  Acertos:   8/10 (80.0%)

WhatsApp Image 2026-02-19 at 08.16.01.jpeg
  Detectado: - - - - - - - - - -
  Real:      B C D E A B C D E A
  Acertos:   0/10 (0.0%)

================================================================================

📈 ESTATÍSTICAS GERAIS
   Total de imagens:  2
   Total de questões: 20
   Total de acertos:  8
   Taxa geral:        40.0%

✅ Relatório salvo em: relatorio_teste_20260219_143022.json
```

---

## 🎯 Formato de Entrada do Gabarito

O programa aceita gabaritos nos formatos:

```
ABCDE              (sem espaços)
A B C D E          (com espaços - serão removidos)
A-CDE              (com hífen para questões em branco)
ABCD-              (hífen indica questão deixada em branco)
```

**Exemplos válidos:**
- `ABCDEABCDE` (10 respostas)
- `A B C D E A B C D E` (com espaços)
- `A-C-E A-C-E` (com brancos)

**Exemplos inválidos:**
- `ABC` (muito curto)
- `ABCDEFGH` (contém F, G, H)
- `ABCDE?` (contém caractere inválido)

---

## 💾 Arquivo de Saída

O programa gera um arquivo JSON com todos os resultados:

**Exemplo: `relatorio_teste_20260219_143022.json`**

```json
{
  "data": "2026-02-19T14:30:22.123456",
  "num_questoes": 10,
  "num_colunas": 1,
  "total_imagens": 2,
  "total_acertos": 8,
  "total_questoes": 20,
  "taxa_geral": 40.0,
  "resultados": [
    {
      "imagem": "WhatsApp Image 2026-02-19 at 08.1.jpeg",
      "detectado": ["A", "B", "C", "D", "E", "-", "-", "C", "D", "E"],
      "real": ["A", "B", "C", "D", "E", "A", "B", "C", "D", "E"],
      "acertos": 8,
      "erros": 2,
      "taxa_acerto": 80.0
    },
    {
      "imagem": "WhatsApp Image 2026-02-19 at 08.16.01.jpeg",
      "detectado": ["-", "-", "-", "-", "-", "-", "-", "-", "-", "-"],
      "real": ["B", "C", "D", "E", "A", "B", "C", "D", "E", "A"],
      "acertos": 0,
      "erros": 10,
      "taxa_acerto": 0.0
    }
  ]
}
```

---

## 🔑 Teclas de Atalho

- **ENTER** - Confirmar entrada / Próxima imagem
- **CTRL+C** - Cancelar teste (no meio da execução)

---

## ✅ Checklist de Teste

- [ ] Executar `python3 test_interativo.py`
- [ ] Configurar 10 questões e 1 coluna
- [ ] Processar todas as imagens
- [ ] Digitar gabarito real para cada imagem
- [ ] Revisar taxa de acerto final
- [ ] Verificar arquivo JSON gerado

---

## 🎯 Metas de Validação

```
✅ Taxa de acerto geral > 90%
✅ Taxa máxima de erro: 5 questões
✅ Tempo de processamento < 5s por imagem
```

---

**Boa sorte! 🚀**
