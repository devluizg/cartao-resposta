// cartao_preview_screen.dart
// Tela 4: Preview e Processamento do Cartão
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'simulado_selection_screen.dart';
import 'cartao_processing_screen.dart';
import 'cartao_result_screen.dart' show CartaoResultData, CartaoResultScreen;

/// Tela 4: Preview do Cartão e Processamento
class CartaoPreviewScreen extends StatefulWidget {
  final File imageFile;
  final SimuladoData simulado;
  final AlunoData aluno;
  final int tipoProva;
  final String? versionCode;

  const CartaoPreviewScreen({
    super.key,
    required this.imageFile,
    required this.simulado,
    required this.aluno,
    required this.tipoProva,
    this.versionCode,
  });

  @override
  State<CartaoPreviewScreen> createState() => _CartaoPreviewScreenState();
}

class _CartaoPreviewScreenState extends State<CartaoPreviewScreen> {
  bool _isProcessing = false;

  Future<void> _processarCartao() async {
    setState(() => _isProcessing = true);

    try {
      // Ler arquivo da imagem
      final bytes = await widget.imageFile.readAsBytes();

      // Preparar requisição multipart
      // ✨ OMR Backend (FastAPI - Servidor Remoto)
      final omrBaseUrl = 'https://simuladoapp.com.br';  // Backend hospedado

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$omrBaseUrl/processar_cartao_robusto'),
      );

      request.fields['num_questoes'] = widget.simulado.numQuestoes.toString();
      request.fields['num_colunas'] = '1';
      request.fields['sensitivity'] = '0.3';
      request.fields['threshold'] = '150';

      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: 'cartao.jpg'),
      );

      print('🔍 Enviando cartão (${bytes.length} bytes) para processamento OMR robusto...');
      final stopwatch = Stopwatch()..start();

      final response = await request.send().timeout(
        const Duration(seconds: 180),  // 3 minutos - tempo suficiente para OMR + Claude Vision
        onTimeout: () => throw Exception('Timeout no processamento (>180s)'),
      );

      print('⏱️ Resposta da rede recebida em ${stopwatch.elapsedMilliseconds}ms');

      final responseBody = await response.stream.bytesToString();
      print('📦 Resposta completa em ${stopwatch.elapsedMilliseconds}ms: ${response.statusCode}');
      print('📏 Tamanho da resposta: ${responseBody.length} bytes');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(responseBody);

        // Extrair respostas
        final respostasJson = jsonData['respostas'] as Map<String, dynamic>;
        final List<String> respostas = List.generate(
          widget.simulado.numQuestoes,
          (i) => (respostasJson[(i + 1).toString()] as String?) ?? 'Não detectada',
        );

        // Carregar gabarito do servidor
        final gabarito = await _carregarGabarito();

        // Calcular acertos
        int acertos = 0;
        int erros = 0;
        for (int i = 0; i < respostas.length; i++) {
          if (respostas[i] != null && gabarito.containsKey(i + 1)) {
            if (respostas[i] == gabarito[i + 1]) {
              acertos++;
            } else {
              erros++;
            }
          }
        }

        final score = (acertos / widget.simulado.numQuestoes) * 100;
        final metodo = jsonData['metodo'] as String? ?? 'hibrido';

        print('✅ Processamento concluído: $acertos acertos, $erros erros');
        print('📊 Método: $metodo | Taxa detecção: ${jsonData['taxa_deteccao']}');

        final result = CartaoResultData(
          simulado: widget.simulado,
          aluno: widget.aluno,
          tipoProva: widget.tipoProva,
          totalQuestoes: widget.simulado.numQuestoes,
          acertos: acertos,
          erros: erros,
          score: score,
          respostasMarcadas: respostas,
          tempoProcessamento: '${(response.request?.contentLength ?? 0) / 1000}s',
          qualidade: jsonData['qualidade_imagem'] != null
              ? (jsonData['qualidade_imagem'] > 0.7 ? 'Excelente' : 'Boa')
              : 'Desconhecida',
        );

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CartaoResultScreen(result: result),
            ),
          );
        }
      } else {
        throw Exception('Erro no servidor: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Erro ao processar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<Map<int, String>> _carregarGabarito() async {
    // ✨ TODO: Implementar carregamento do gabarito do servidor
    // Por enquanto, retorna vazio (será implementado depois)
    return {};
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isProcessing) return false;
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text(
            'Passo 4: Revisar Cartão',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          elevation: 0,
          automaticallyImplyLeading: !_isProcessing,
        ),
        body: Column(
          children: [
            // FOTO DO CARTÃO
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 3.0,
                    child: Image.file(
                      widget.imageFile,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),

            // INFO DO PROCESSAMENTO
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_rounded,
                          color: Color(0xFF0DA6F2), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Simulado: ${widget.simulado.nome}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Aluno: ${widget.aluno.nome} • Tipo ${widget.tipoProva}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // BOTÕES
                  Row(
                    children: [
                      // REFAZER
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () {
                                  Navigator.pop(context);
                                },
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                          label: const Text(
                            'REFAZER',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // PROCESSAR
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed:
                              _isProcessing ? null : _processarCartao,
                          icon: _isProcessing
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                          label: Text(
                            _isProcessing
                                ? 'PROCESSANDO...'
                                : 'PROCESSAR',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF16A34A),
                            disabledBackgroundColor:
                                Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
