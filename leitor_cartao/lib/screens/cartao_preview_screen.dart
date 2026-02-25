// cartao_preview_screen.dart
// Tela 4: Preview e Processamento do Cartão
import 'package:flutter/material.dart';
import 'dart:io';
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
      // ✨ TODO: Conectar com API de processamento OMR
      // Simular delay de processamento
      await Future.delayed(const Duration(seconds: 2));

      // Simular resultado (no futuro, será do servidor)
      final mockResult = CartaoResultData(
        simulado: widget.simulado,
        aluno: widget.aluno,
        tipoProva: widget.tipoProva,
        totalQuestoes: widget.simulado.numQuestoes,
        acertos: 38,
        erros: 7,
        score: 75.5,
        respostasMarcadas: List.generate(
          widget.simulado.numQuestoes,
          (i) => ['A', 'B', 'C', 'D', 'E'][(i * 3) % 5],
        ),
        tempoProcessamento: '2.3s',
        qualidade: 'Excelente',
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CartaoResultScreen(result: mockResult),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
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
