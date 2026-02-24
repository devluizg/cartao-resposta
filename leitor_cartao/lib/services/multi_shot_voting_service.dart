// multi_shot_voting_service.dart
// Serviço para votação de múltiplas capturas (Multi-Shot Voting)
// Captura 2-3 fotos do cartão e faz votação por questão

import 'package:intl/intl.dart';

/// Resultado de uma única captura (uma foto processada pela API)
class SingleShotResult {
  final int shotNumber;        // 1, 2 ou 3
  final Map<int, String?> responses;   // {questão: resposta}
  final Map<int, double> confidences;  // {questão: confiança 0-1}
  final double imageQualityScore;      // Score de qualidade da imagem
  final DateTime timestamp;

  SingleShotResult({
    required this.shotNumber,
    required this.responses,
    required this.confidences,
    required this.imageQualityScore,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'shot_number': shotNumber,
    'responses': responses,
    'confidences': confidences,
    'image_quality_score': imageQualityScore,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Resultado de votação para uma questão
class QuestionVote {
  final int questionNumber;
  final Map<String, int> voteCount;     // {resposta: contagem}
  final String? winnerResponse;         // Resposta vencedora
  final double winnerConfidence;        // Confiança média da resposta vencedora
  final int shotsAgreed;                // Quantas fotos concordaram
  final int totalShots;                 // Total de fotos
  final bool isAmbiguous;               // true se houver empate/discordância
  final List<String?> allResponses;     // Todas as respostas capturadas

  QuestionVote({
    required this.questionNumber,
    required this.voteCount,
    required this.winnerResponse,
    required this.winnerConfidence,
    required this.shotsAgreed,
    required this.totalShots,
    required this.isAmbiguous,
    required this.allResponses,
  });

  /// Concordância percentual (quantos % concordam com vencedor)
  double get agreementRate => shotsAgreed / totalShots;

  Map<String, dynamic> toJson() => {
    'question_number': questionNumber,
    'vote_count': voteCount,
    'winner_response': winnerResponse,
    'winner_confidence': winnerConfidence,
    'shots_agreed': shotsAgreed,
    'total_shots': totalShots,
    'is_ambiguous': isAmbiguous,
    'agreement_rate': agreementRate,
  };
}

/// Resultado final da votação em todas as questões
class MultiShotVotingResult {
  final List<SingleShotResult> shots;                    // Todas as capturas
  final Map<int, QuestionVote> questionVotes;           // Votação por questão
  final Map<int, String?> finalResponses;              // Respostas finais
  final Map<int, double> finalConfidences;             // Confiança final
  final double overallAgreement;                        // Taxa de concordância geral
  final List<int> ambiguousQuestions;                   // Questões com discordância
  final String summaryText;

  MultiShotVotingResult({
    required this.shots,
    required this.questionVotes,
    required this.finalResponses,
    required this.finalConfidences,
    required this.overallAgreement,
    required this.ambiguousQuestions,
    required this.summaryText,
  });

  Map<String, dynamic> toJson() => {
    'shots': shots.map((s) => s.toJson()).toList(),
    'question_votes': questionVotes.map(
      (k, v) => MapEntry(k.toString(), v.toJson()),
    ),
    'final_responses': finalResponses,
    'final_confidences': finalConfidences,
    'overall_agreement': overallAgreement,
    'ambiguous_questions': ambiguousQuestions,
    'summary': summaryText,
  };
}

/// Serviço de votação multi-shot
class MultiShotVotingService {
  /// Realizar votação com múltiplas capturas
  static MultiShotVotingResult performVoting({
    required List<SingleShotResult> shots,
    required int totalQuestions,
    double ambiguityThreshold = 0.7,  // Se agreement < 70%, é ambíguo
  }) {
    if (shots.isEmpty) {
      throw Exception('Nenhuma captura fornecida');
    }

    if (shots.length > 3) {
      throw Exception('Máximo de 3 capturas permitido');
    }

    final questionVotes = <int, QuestionVote>{};
    final finalResponses = <int, String?>{};
    final finalConfidences = <int, double>{};
    final ambiguousQuestions = <int>[];

    int totalAgreements = 0;

    // Processar cada questão
    for (int q = 1; q <= totalQuestions; q++) {
      final voteCount = <String?, int>{};
      final allResponses = <String?>[];
      final confidenceValues = <double>[];

      // Contar votos
      for (final shot in shots) {
        final response = shot.responses[q];
        final confidence = shot.confidences[q] ?? 0.0;

        allResponses.add(response);
        confidenceValues.add(confidence);

        voteCount[response] = (voteCount[response] ?? 0) + 1;
      }

      // Encontrar vencedor
      String? winner;
      int maxVotes = 0;

      for (final entry in voteCount.entries) {
        if (entry.value > maxVotes) {
          maxVotes = entry.value;
          winner = entry.key;
        }
      }

      // Calcular confiança média do vencedor
      double winnerConfidence = 0.0;
      int winnerCount = 0;
      for (int i = 0; i < shots.length; i++) {
        if (shots[i].responses[q] == winner) {
          winnerConfidence += shots[i].confidences[q] ?? 0.0;
          winnerCount++;
        }
      }
      if (winnerCount > 0) {
        winnerConfidence /= winnerCount;
      }

      // Detectar ambiguidade
      final agreementRate = maxVotes / shots.length;
      final isAmbiguous = agreementRate < ambiguityThreshold;

      if (!isAmbiguous) {
        totalAgreements++;
      } else {
        ambiguousQuestions.add(q);
      }

      // Criar voto para questão
      final vote = QuestionVote(
        questionNumber: q,
        voteCount: voteCount,
        winnerResponse: winner,
        winnerConfidence: winnerConfidence,
        shotsAgreed: maxVotes,
        totalShots: shots.length,
        isAmbiguous: isAmbiguous,
        allResponses: allResponses,
      );

      questionVotes[q] = vote;
      finalResponses[q] = winner;
      finalConfidences[q] = winnerConfidence;
    }

    // Calcular concordância geral
    final overallAgreement = totalAgreements / totalQuestions;

    // Gerar texto de resumo
    final summaryText = _generateSummary(
      shots: shots,
      totalQuestions: totalQuestions,
      ambiguousQuestions: ambiguousQuestions,
      overallAgreement: overallAgreement,
    );

    return MultiShotVotingResult(
      shots: shots,
      questionVotes: questionVotes,
      finalResponses: finalResponses,
      finalConfidences: finalConfidences,
      overallAgreement: overallAgreement,
      ambiguousQuestions: ambiguousQuestions,
      summaryText: summaryText,
    );
  }

  /// Gerar resumo em texto
  static String _generateSummary({
    required List<SingleShotResult> shots,
    required int totalQuestions,
    required List<int> ambiguousQuestions,
    required double overallAgreement,
  }) {
    StringBuffer buffer = StringBuffer();

    buffer.writeln('═══════════════════════════════════════════════════════');
    buffer.writeln('MULTI-SHOT VOTING RESULT');
    buffer.writeln('═══════════════════════════════════════════════════════\n');

    buffer.writeln('📸 CAPTURAS:');
    for (int i = 0; i < shots.length; i++) {
      final shot = shots[i];
      buffer.writeln(
        '   Shot ${shot.shotNumber}: ${(shot.imageQualityScore * 100).toStringAsFixed(0)}% qualidade',
      );
    }

    buffer.writeln('\n🎯 VOTAÇÃO:');
    buffer.writeln(
      '   Total de questões: $totalQuestions',
    );
    buffer.writeln(
      '   Concordância geral: ${(overallAgreement * 100).toStringAsFixed(1)}%',
    );
    buffer.writeln(
      '   Questões com concordância: ${totalQuestions - ambiguousQuestions.length}/$totalQuestions',
    );

    if (ambiguousQuestions.isNotEmpty) {
      buffer.writeln('\n⚠️  QUESTÕES AMBÍGUAS:');
      for (final q in ambiguousQuestions) {
        buffer.writeln('   Q$q');
      }
    }

    buffer.writeln(
      '\n✅ RECOMENDAÇÃO: ${overallAgreement >= 0.9 ? 'Alta confiança - respostas estão consistentes' : overallAgreement >= 0.7 ? 'Confiança média - revise questões ambíguas' : 'Baixa confiança - capture novamente'}',
    );

    return buffer.toString();
  }

  /// Comparar resultados de múltiplas capturas (para debug)
  static String compareShots(List<SingleShotResult> shots) {
    if (shots.isEmpty) return 'Nenhuma captura';

    StringBuffer buffer = StringBuffer();
    buffer.writeln('COMPARAÇÃO DE CAPTURAS:');
    buffer.writeln('═══════════════════════════════════════════════════════\n');

    final maxQuestions = shots
        .fold<int>(0, (max, shot) => max > shot.responses.length ? max : shot.responses.length);

    for (int q = 1; q <= maxQuestions; q++) {
      final responses = shots.map((s) => s.responses[q] ?? '?').join(' | ');
      final confs = shots
          .map((s) => '${((s.confidences[q] ?? 0) * 100).toStringAsFixed(0)}%')
          .join(' | ');

      buffer.writeln('Q$q:');
      buffer.writeln('   Respostas: $responses');
      buffer.writeln('   Confiança: $confs');
    }

    return buffer.toString();
  }

  /// Calcular melhoria de confiança com multi-shot
  static Map<int, double> calculateConfidenceImprovement(
    List<SingleShotResult> shots,
  ) {
    if (shots.isEmpty) return {};

    final improvement = <int, double>{};
    final maxQuestions = shots
        .fold<int>(0, (max, shot) => max > shot.responses.length ? max : shot.responses.length);

    for (int q = 1; q <= maxQuestions; q++) {
      final confidences = shots
          .map((s) => s.confidences[q] ?? 0.0)
          .toList();

      if (confidences.isEmpty) continue;

      final avgConfidence = confidences.reduce((a, b) => a + b) / confidences.length;
      final maxConfidence = confidences.reduce((a, b) => a > b ? a : b);

      // Melhoria é a diferença entre confiança máxima e média
      improvement[q] = maxConfidence - avgConfidence;
    }

    return improvement;
  }

  /// Gerar recomendação para o usuário
  static String getRecommendation(MultiShotVotingResult result) {
    final agreement = result.overallAgreement;

    if (agreement >= 0.95) {
      return '🟢 EXCELENTE: Todas as capturas concordam! Use estas respostas com confiança.';
    } else if (agreement >= 0.85) {
      return '🔵 ÓTIMO: Boa concordância entre capturas. Respostas são confiáveis.';
    } else if (agreement >= 0.70) {
      return '🟠 BOM: Concordância moderada. Revise as questões destacadas.';
    } else if (agreement >= 0.50) {
      return '🟠 CUIDADO: Baixa concordância. Muitas questões com discordância.';
    } else {
      return '🔴 CRÍTICO: Capturas muito diferentes! Refaça com melhor qualidade.';
    }
  }

  /// Decidir se deve capturar novamente
  static bool shouldRetry(MultiShotVotingResult result) {
    // Recomenda refazer se concordância < 70% ou muitas questões ambíguas
    return result.overallAgreement < 0.70 ||
        result.ambiguousQuestions.length > result.questionVotes.length * 0.3;
  }
}
