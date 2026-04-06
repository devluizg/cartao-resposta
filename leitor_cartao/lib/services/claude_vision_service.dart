// claude_vision_service.dart
// Leitura de cartão-resposta via Claude Vision API (Haiku 4.5)
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ClaudeVisionService {
  // Chave lida da variável de ambiente ANTHROPIC_API_KEY (nunca hardcode aqui)
  static final String _apiKey =
      const String.fromEnvironment('ANTHROPIC_API_KEY', defaultValue: '');
  static const String _baseUrl = 'https://api.anthropic.com/v1/messages';
  static const String _model = 'claude-haiku-4-5-20251001'; // ~R$0,015/scan

  /// Processa cartão-resposta enviando imagem diretamente ao Claude Vision.
  /// Retorna o mesmo formato JSON que o backend OMR:
  /// { "respostas": {"1":"A","2":"B",...}, "metodo": "claude_vision", ... }
  static Future<Map<String, dynamic>> processarCartao({
    required File imageFile,
    required int numQuestoes,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Envia imagem ORIGINAL (sem pré-recorte) — Claude lida com qualquer orientação
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    print(
        '📷 Claude Vision: imagem ${(bytes.length / 1024).toStringAsFixed(0)}KB → base64...');

    // Calcular estrutura de blocos — mesma lógica do pdf_generator.py
    // num_colunas = 1 if num_questoes <= 23 else 2
    final int numBlocos = numQuestoes <= 23 ? 1 : 2;
    final List<int> questoesPorBloco;
    if (numBlocos == 1) {
      questoesPorBloco = [numQuestoes];
    } else if (numQuestoes % 2 == 0) {
      questoesPorBloco = [numQuestoes ~/ 2, numQuestoes ~/ 2];
    } else {
      questoesPorBloco = [(numQuestoes ~/ 2) + 1, numQuestoes ~/ 2];
    }
    final int bloco1Fim = questoesPorBloco[0];

    String q(int n) => n.toString().padLeft(2, '0');

    final String descricaoBlocos;
    final String avisoColuna;
    if (numBlocos == 1) {
      descricaoBlocos = '1 bloco retangular com questões ${q(1)} a ${q(numQuestoes)}';
      avisoColuna = '';
    } else {
      descricaoBlocos =
          '2 blocos retangulares LADO A LADO (separados por espaço de ~18mm):\n'
          '  • Bloco ESQUERDO: questões ${q(1)} a ${q(bloco1Fim)} (lidas de cima para baixo)\n'
          '  • Bloco DIREITO:  questões ${q(bloco1Fim + 1)} a ${q(numQuestoes)} (lidas de cima para baixo)\n'
          'ATENÇÃO: cada bloco tem seu PRÓPRIO cabeçalho "A B C D E". '
          'NÃO leia da esquerda para direita atravessando os dois blocos. '
          'Leia cada bloco de forma completamente INDEPENDENTE, de cima para baixo.';
      avisoColuna =
          '\n⚠️ CUIDADO COM 2 COLUNAS: Os dois blocos ficam lado a lado. '
          'A questão ${q(bloco1Fim + 1)} está no BLOCO DIREITO, primeira linha, NÃO é continuação do bloco esquerdo. '
          'Cada bloco tem seus próprios 5 círculos de bolhas referenciados pelo cabeçalho A-B-C-D-E daquele bloco.';
    }

    final prompt =
        '''TAREFA: Ler um cartão-resposta do SimuladoApp com $numQuestoes questões.

ESTRUTURA EXATA DO CARTÃO:
O cartão possui $descricaoBlocos.
Dentro de cada bloco retangular com borda escura:
  - Cabeçalho interno com as letras:  A  B  C  D  E
  - Cada questão = 1 LINHA com 5 bolhas circulares (alternativas A B C D E, esquerda→direita)
  - O NÚMERO da questão está impresso em negrito À ESQUERDA da linha (ex: "01", "09", "14")
  - Linhas com fundo alternado branco / azul-claro (zebra)
  - O cartão pode estar rotacionado na foto — leia os números independente da orientação
$avisoColuna

MÉTODO DE LEITURA (siga obrigatoriamente):
Para cada questão de 1 a $numQuestoes:
  1. Localize o número impresso no cartão (formato "${q(1)}", "${q(2)}", ... "${q(numQuestoes)}")
  2. Encontre as 5 bolhas circulares da linha desse número (dentro do bloco desse número)
  3. Identifique qual bolha está COMPLETAMENTE PREENCHIDA (preta = marcada pelo aluno)
  4. A posição da bolha preta determina a resposta: 1ª=A, 2ª=B, 3ª=C, 4ª=D, 5ª=E

REGRAS IMPORTANTES:
  - SEMPRE use o número impresso para identificar a questão — NUNCA conte linhas em sequência
  - Bolha MARCADA = completamente preenchida / preta
  - Bolha VAZIA = apenas o contorno circular
  - Sem nenhuma marcação → "EM_BRANCO"
  - Duas ou mais marcadas → "AMBIGUA"

Retorne APENAS este JSON sem markdown nem texto extra:
{"respostas":{"1":"A","2":"B",...,"$numQuestoes":"E"},"confianca":0.95,"observacoes":"..."}''';

    final requestBody = jsonEncode({
      'model': _model,
      'max_tokens': 1024,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/jpeg',
                'data': base64Image,
              },
            },
            {
              'type': 'text',
              'text': prompt,
            },
          ],
        },
      ],
    });

    print('🧠 Enviando para Claude Haiku...');

    final response = await http
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'x-api-key': _apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          body: requestBody,
        )
        .timeout(
          const Duration(seconds: 45),
          onTimeout: () => throw Exception('Claude Vision timeout (>45s)'),
        );

    print('⏱️ Claude respondeu em ${stopwatch.elapsedMilliseconds}ms');

    if (response.statusCode != 200) {
      throw Exception(
        'Claude API error ${response.statusCode}: ${response.body}',
      );
    }

    final responseData = jsonDecode(response.body) as Map<String, dynamic>;
    String content = (responseData['content'] as List).first['text'] as String;
    print('📝 Resposta bruta: $content');

    // Remove blocos markdown se presentes
    content = content.trim();
    if (content.contains('```json')) {
      content = content.split('```json')[1].split('```')[0].trim();
    } else if (content.contains('```')) {
      content = content.split('```')[1].split('```')[0].trim();
    }

    final Map<String, dynamic> parsed = jsonDecode(content);
    final Map<String, dynamic> respostas =
        (parsed['respostas'] as Map<String, dynamic>?) ?? {};
    final double confianca = (parsed['confianca'] as num?)?.toDouble() ?? 1.0;
    final String observacoes = (parsed['observacoes'] as String?) ?? '';

    // Tokens usados (para monitorar custo)
    final usage = responseData['usage'] as Map<String, dynamic>?;
    final inputTokens = usage?['input_tokens'] ?? 0;
    final outputTokens = usage?['output_tokens'] ?? 0;
    print(
      '💰 Tokens: $inputTokens entrada + $outputTokens saída '
      '≈ \$${((inputTokens * 0.80 + outputTokens * 4.0) / 1000000).toStringAsFixed(5)}',
    );
    print(
        '✅ Claude Vision: ${respostas.length} questões detectadas (confiança: $confianca)');
    if (observacoes.isNotEmpty) print('💬 Obs: $observacoes');

    return {
      'respostas': respostas,
      'metodo': 'claude_vision',
      'taxa_deteccao': respostas.length / numQuestoes,
      'qualidade_imagem': confianca,
      'observacoes': observacoes,
    };
  }
}
