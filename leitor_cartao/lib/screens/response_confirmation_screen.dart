// response_confirmation_screen.dart
// Tela para o usuário confirmar e editar respostas detectadas pela API
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:io';
import '../services/correction_feedback_service.dart';

class ResponseConfirmationScreen extends StatefulWidget {
  /// Respostas detectadas pela API
  /// Map<questão_número, resposta> ex: {1: 'A', 2: 'C', ...}
  final Map<int, String?> apiResponses;

  /// Confiança de cada resposta (0-1)
  final Map<int, double>? apiConfidences;

  /// Gabarito esperado (para comparação opcional)
  final Map<int, String>? expectedAnswers;

  /// Arquivo de imagem (para hash)
  final File? imageFile;

  /// Número total de questões
  final int totalQuestions;

  /// Callback ao confirmar
  final Function(Map<int, String?> corrections)? onConfirm;

  const ResponseConfirmationScreen({
    super.key,
    required this.apiResponses,
    this.apiConfidences,
    this.expectedAnswers,
    this.imageFile,
    required this.totalQuestions,
    this.onConfirm,
  });

  @override
  State<ResponseConfirmationScreen> createState() =>
      _ResponseConfirmationScreenState();
}

class _ResponseConfirmationScreenState extends State<ResponseConfirmationScreen> {
  late Map<int, String?> _userResponses;
  late CorrectionFeedbackService _feedbackService;
  bool _isSavingFeedback = false;

  // Contar correções
  int get _correctionCount {
    int count = 0;
    for (int q = 1; q <= widget.totalQuestions; q++) {
      if (_userResponses[q] != widget.apiResponses[q]) {
        count++;
      }
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    _userResponses = Map.from(widget.apiResponses);
    _feedbackService = CorrectionFeedbackService();
    _feedbackService.init();
  }

  /// Calcular hash da imagem para rastreamento
  Future<String> _getImageHash() async {
    if (widget.imageFile == null) return 'unknown';
    try {
      final bytes = await widget.imageFile!.readAsBytes();
      return md5.convert(bytes).toString().substring(0, 8);
    } catch (e) {
      return 'error';
    }
  }

  /// Salvar feedback e ir para resultado
  Future<void> _confirmarEAvançar() async {
    if (_isSavingFeedback) return;

    setState(() => _isSavingFeedback = true);

    try {
      // Calcular correções
      final corrections = <QuestionCorrection>[];
      int questionsCorrect = 0;
      int questionsApiCorrect = 0;

      for (int q = 1; q <= widget.totalQuestions; q++) {
        final apiResp = widget.apiResponses[q];
        final userResp = _userResponses[q];
        final expected = widget.expectedAnswers?[q];

        // Se usuário corrigiu (mudou de API)
        if (userResp != apiResp && userResp != null) {
          questionsCorrect++;

          // Verificar se a correção estava correta
          final wasCorrect = userResp == expected;

          corrections.add(QuestionCorrection(
            questionNumber: q,
            apiResponse: apiResp,
            userResponse: userResp,
            apiConfidence: widget.apiConfidences?[q],
            timestamp: DateTime.now(),
            imageHash: await _getImageHash(),
            wasCorrect: wasCorrect,
          ));
        }

        // Contar acertos da API
        if (apiResp == expected) {
          questionsApiCorrect++;
        }
      }

      // Calcular acurácia
      final accuracyBefore = expected != null
          ? questionsApiCorrect / widget.totalQuestions
          : 0.0;

      // Acurácia após correções
      int correctAfter = 0;
      for (int q = 1; q <= widget.totalQuestions; q++) {
        if (_userResponses[q] == widget.expectedAnswers?[q]) {
          correctAfter++;
        }
      }
      final accuracyAfter = expected != null
          ? correctAfter / widget.totalQuestions
          : 0.0;

      // Salvar sessão se houver gabarito e correções
      if (expected != null && corrections.isNotEmpty) {
        final session = ReadingSessionFeedback(
          sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
          sessionDate: DateTime.now(),
          imageHash: await _getImageHash(),
          totalQuestions: widget.totalQuestions,
          corrections: corrections,
          apiAccuracyBefore: accuracyBefore,
          apiAccuracyAfter: accuracyAfter,
          questionsCorrect: questionsCorrect,
          questionsAcertouApi: questionsApiCorrect,
        );

        await _feedbackService.saveSession(session);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Feedback salvo: $questionsCorrect correção(ões)',
              ),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }

      // Chamar callback
      if (widget.onConfirm != null) {
        widget.onConfirm!(_userResponses);
      }

      if (mounted) {
        Navigator.pop(context, _userResponses);
      }
    } catch (e) {
      print('❌ Erro ao salvar feedback: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingFeedback = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A2A3A),
        title: const Text(
          'Confirmar Respostas',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _correctionCount > 0
                      ? Colors.orange.shade700.withOpacity(0.8)
                      : Colors.green.shade700.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _correctionCount > 0
                      ? '✏️ ${_correctionCount} correção${_correctionCount > 1 ? "ões" : ""}'
                      : '✅ Sem edições',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header com info
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blue.shade300,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Toque na resposta para editar. A API detectou ${widget.apiResponses.length} respostas.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lista de respostas
          Expanded(
            child: ListView.builder(
              itemCount: widget.totalQuestions,
              itemBuilder: (context, index) {
                final questionNum = index + 1;
                final apiResp = widget.apiResponses[questionNum];
                final userResp = _userResponses[questionNum];
                final confidence = widget.apiConfidences?[questionNum] ?? 0.0;
                final expected = widget.expectedAnswers?[questionNum];

                final wasEdited = apiResp != userResp;
                final isCorrect = userResp == expected;

                return _buildQuestionTile(
                  questionNum: questionNum,
                  apiResponse: apiResp,
                  userResponse: userResp,
                  confidence: confidence,
                  expectedAnswer: expected,
                  wasEdited: wasEdited,
                  isCorrect: isCorrect,
                  onChanged: (newResp) {
                    setState(() {
                      _userResponses[questionNum] = newResp;
                    });
                  },
                );
              },
            ),
          ),

          // Botões de ação
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('CANCELAR'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                      ),
                      foregroundColor: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSavingFeedback ? null : _confirmarEAvançar,
                    icon: _isSavingFeedback
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                Colors.white.withOpacity(0.7),
                              ),
                            ),
                          )
                        : const Icon(Icons.check_circle, size: 18),
                    label: Text(
                      _isSavingFeedback ? 'SALVANDO...' : 'CONFIRMAR',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Widget para uma questão individual
  Widget _buildQuestionTile({
    required int questionNum,
    required String? apiResponse,
    required String? userResponse,
    required double confidence,
    required String? expectedAnswer,
    required bool wasEdited,
    required bool isCorrect,
    required Function(String?) onChanged,
  }) {
    final alternatives = ['A', 'B', 'C', 'D', 'E'];

    // Determinar cor do status
    Color statusColor;
    String statusIcon;
    if (wasEdited) {
      statusColor = isCorrect ? Colors.green : Colors.orange;
      statusIcon = isCorrect ? '✅' : '✏️';
    } else {
      statusColor =
          isCorrect ? Colors.green.shade700 : Colors.red.shade700;
      statusIcon = isCorrect ? '✅' : '❌';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: wasEdited ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Número + Status
            Row(
              children: [
                Text(
                  'Q$questionNum',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  statusIcon,
                  style: const TextStyle(fontSize: 14),
                ),
                const Spacer(),
                // Mostrar confiança da API
                if (confidence > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${(confidence * 100).toStringAsFixed(0)}% conf',
                      style: TextStyle(
                        color: Colors.blue.shade300,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Row com resposta API + Edição
            Row(
              children: [
                // Resposta detectada
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'API detectou:',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: Text(
                        apiResponse ?? '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 12),

                // Seta
                Icon(
                  Icons.arrow_forward,
                  color: Colors.white.withOpacity(0.3),
                  size: 18,
                ),

                const SizedBox(width: 12),

                // Seletor de alternativas
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sua resposta:',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: alternatives.map((alt) {
                          final isSelected = userResponse == alt;
                          final isApiChoice = apiResponse == alt;

                          return GestureDetector(
                            onTap: () => onChanged(alt),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? statusColor.withOpacity(0.8)
                                    : isApiChoice
                                        ? Colors.blue.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected
                                      ? statusColor
                                      : isApiChoice
                                          ? Colors.blue
                                          : Colors.white.withOpacity(0.2),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  alt,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.7),
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Info extras (se houver gabarito)
            if (expectedAnswer != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green.shade400,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Gabarito: $expectedAnswer',
                      style: TextStyle(
                        color: Colors.green.shade400,
                        fontSize: 11,
                      ),
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
