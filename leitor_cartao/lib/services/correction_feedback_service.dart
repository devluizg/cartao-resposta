// correction_feedback_service.dart
// Serviço para salvar feedback de correções do usuário (user-in-the-loop)
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

/// Representa uma correção individual de uma questão
class QuestionCorrection {
  final int questionNumber;
  final String? apiResponse;      // O que a API detectou
  final String userResponse;      // O que o usuário corrigiu para
  final double? apiConfidence;    // Confiança da API (0-1)
  final DateTime timestamp;
  final String imageHash;         // Hash da imagem para rastrear
  final bool wasCorrect;          // true se API acertou, false se errou

  QuestionCorrection({
    required this.questionNumber,
    required this.apiResponse,
    required this.userResponse,
    this.apiConfidence,
    required this.timestamp,
    required this.imageHash,
    required this.wasCorrect,
  });

  /// Converter para JSON para armazenamento
  Map<String, dynamic> toJson() => {
    'question_number': questionNumber,
    'api_response': apiResponse,
    'user_response': userResponse,
    'api_confidence': apiConfidence,
    'timestamp': timestamp.toIso8601String(),
    'image_hash': imageHash,
    'was_correct': wasCorrect,
  };

  /// Criar a partir de JSON
  factory QuestionCorrection.fromJson(Map<String, dynamic> json) =>
      QuestionCorrection(
        questionNumber: json['question_number'] as int,
        apiResponse: json['api_response'] as String?,
        userResponse: json['user_response'] as String,
        apiConfidence: (json['api_confidence'] as num?)?.toDouble(),
        timestamp: DateTime.parse(json['timestamp'] as String),
        imageHash: json['image_hash'] as String,
        wasCorrect: json['was_correct'] as bool,
      );
}

/// Resultado de uma sessão de leitura (com possíveis correções)
class ReadingSessionFeedback {
  final String sessionId;
  final DateTime sessionDate;
  final String imageHash;
  final int totalQuestions;
  final List<QuestionCorrection> corrections; // Apenas questões que foram corrigidas
  final double apiAccuracyBefore;    // Acurácia antes das correções
  final double apiAccuracyAfter;     // Acurácia após correções do usuário
  final int questionsCorrect;        // Quantas questões o usuário corrigiu
  final int questionsAcertouApi;     // Quantas a API acertou

  ReadingSessionFeedback({
    required this.sessionId,
    required this.sessionDate,
    required this.imageHash,
    required this.totalQuestions,
    required this.corrections,
    required this.apiAccuracyBefore,
    required this.apiAccuracyAfter,
    required this.questionsCorrect,
    required this.questionsAcertouApi,
  });

  /// Converter para JSON
  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'session_date': sessionDate.toIso8601String(),
    'image_hash': imageHash,
    'total_questions': totalQuestions,
    'corrections': corrections.map((c) => c.toJson()).toList(),
    'api_accuracy_before': apiAccuracyBefore,
    'api_accuracy_after': apiAccuracyAfter,
    'questions_correct': questionsCorrect,
    'questions_api_correct': questionsAcertouApi,
  };

  /// Criar a partir de JSON
  factory ReadingSessionFeedback.fromJson(Map<String, dynamic> json) =>
      ReadingSessionFeedback(
        sessionId: json['session_id'] as String,
        sessionDate: DateTime.parse(json['session_date'] as String),
        imageHash: json['image_hash'] as String,
        totalQuestions: json['total_questions'] as int,
        corrections: (json['corrections'] as List<dynamic>)
            .map((c) => QuestionCorrection.fromJson(c as Map<String, dynamic>))
            .toList(),
        apiAccuracyBefore: (json['api_accuracy_before'] as num).toDouble(),
        apiAccuracyAfter: (json['api_accuracy_after'] as num).toDouble(),
        questionsCorrect: json['questions_correct'] as int,
        questionsAcertouApi: json['questions_api_correct'] as int,
      );
}

/// Serviço para gerenciar feedback de correções
class CorrectionFeedbackService {
  static const String _storageKey = 'reading_sessions_feedback';
  late final SharedPreferences _prefs;

  CorrectionFeedbackService();

  /// Inicializar serviço
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Salvar uma sessão de leitura com correções
  Future<void> saveSession(ReadingSessionFeedback session) async {
    try {
      final sessions = await getSessions();
      sessions.add(session);

      // Manter apenas últimas 100 sessões
      if (sessions.length > 100) {
        sessions.removeRange(0, sessions.length - 100);
      }

      final json = jsonEncode(sessions.map((s) => s.toJson()).toList());
      await _prefs.setString(_storageKey, json);

      print('✅ Sessão salva: ${session.sessionId}');
      print('   Questões corrigidas: ${session.questionsCorrect}/${session.totalQuestions}');
      print('   API acurácia: ${(session.apiAccuracyBefore * 100).toStringAsFixed(1)}% → ${(session.apiAccuracyAfter * 100).toStringAsFixed(1)}%');
    } catch (e) {
      print('❌ Erro ao salvar sessão: $e');
    }
  }

  /// Recuperar todas as sessões
  Future<List<ReadingSessionFeedback>> getSessions() async {
    try {
      final jsonStr = _prefs.getString(_storageKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        return [];
      }

      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((item) => ReadingSessionFeedback.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Erro ao carregar sessões: $e');
      return [];
    }
  }

  /// Obter estatísticas agregadas
  Future<Map<String, dynamic>> getAggregateStats() async {
    final sessions = await getSessions();

    if (sessions.isEmpty) {
      return {
        'total_sessions': 0,
        'total_questions_read': 0,
        'total_corrections': 0,
        'average_api_accuracy_before': 0.0,
        'average_api_accuracy_after': 0.0,
        'api_improvement': 0.0,
        'most_corrected_questions': <int>[],
      };
    }

    int totalCorrections = 0;
    double sumAccuracyBefore = 0;
    double sumAccuracyAfter = 0;
    Map<int, int> correctionCounts = {};

    for (final session in sessions) {
      totalCorrections += session.questionsCorrect;
      sumAccuracyBefore += session.apiAccuracyBefore;
      sumAccuracyAfter += session.apiAccuracyAfter;

      for (final correction in session.corrections) {
        correctionCounts[correction.questionNumber] =
            (correctionCounts[correction.questionNumber] ?? 0) + 1;
      }
    }

    // Questões mais frequentemente corrigidas
    final sortedQuestions = correctionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mostCorrected = sortedQuestions.take(5).map((e) => e.key).toList();

    return {
      'total_sessions': sessions.length,
      'total_questions_read': sessions.fold<int>(
        0,
        (sum, s) => sum + s.totalQuestions,
      ),
      'total_corrections': totalCorrections,
      'average_api_accuracy_before': sumAccuracyBefore / sessions.length,
      'average_api_accuracy_after': sumAccuracyAfter / sessions.length,
      'api_improvement':
          (sumAccuracyAfter - sumAccuracyBefore) / sessions.length,
      'most_corrected_questions': mostCorrected,
    };
  }

  /// Obter detalhes de uma questão específica
  Future<Map<String, dynamic>> getQuestionStats(int questionNumber) async {
    final sessions = await getSessions();
    final corrections = <QuestionCorrection>[];

    for (final session in sessions) {
      for (final correction in session.corrections) {
        if (correction.questionNumber == questionNumber) {
          corrections.add(correction);
        }
      }
    }

    if (corrections.isEmpty) {
      return {
        'question_number': questionNumber,
        'total_corrections': 0,
        'api_error_rate': 0.0,
        'common_corrections': {},
      };
    }

    // Contar correções comuns
    Map<String, int> correctionMap = {};
    int apiErrors = 0;

    for (final correction in corrections) {
      if (!correction.wasCorrect) {
        apiErrors++;
        final key =
            '${correction.apiResponse ?? "?"}→${correction.userResponse}';
        correctionMap[key] = (correctionMap[key] ?? 0) + 1;
      }
    }

    return {
      'question_number': questionNumber,
      'total_corrections': corrections.length,
      'api_error_rate': apiErrors / corrections.length,
      'common_corrections': correctionMap,
    };
  }

  /// Exportar feedback em formato legível
  Future<String> exportFeedback() async {
    final sessions = await getSessions();
    final stats = await getAggregateStats();

    StringBuffer buffer = StringBuffer();
    buffer.writeln('═══════════════════════════════════════════════════════');
    buffer.writeln('FEEDBACK DE LEITURA OMR - RELATÓRIO');
    buffer.writeln('═══════════════════════════════════════════════════════\n');

    buffer.writeln('📊 ESTATÍSTICAS AGREGADAS:');
    buffer.writeln('   Sessões lidas: ${stats['total_sessions']}');
    buffer.writeln('   Total de questões: ${stats['total_questions_read']}');
    buffer.writeln('   Correções do usuário: ${stats['total_corrections']}');
    buffer.writeln(
        '   Acurácia API (antes): ${(stats['average_api_accuracy_before'] * 100).toStringAsFixed(1)}%');
    buffer.writeln(
        '   Acurácia API (depois): ${(stats['average_api_accuracy_after'] * 100).toStringAsFixed(1)}%');
    buffer.writeln(
        '   Melhoria: ${(stats['api_improvement'] * 100).toStringAsFixed(1)}%\n');

    if ((stats['most_corrected_questions'] as List).isNotEmpty) {
      buffer.writeln('⚠️  QUESTÕES MAIS CORRIGIDAS:');
      for (final q in stats['most_corrected_questions'] as List<int>) {
        final qStats = await getQuestionStats(q);
        buffer.writeln(
            '   Q${q}: ${qStats['total_corrections']} correções (${(qStats['api_error_rate'] * 100).toStringAsFixed(0)}% erro)');
      }
      buffer.writeln();
    }

    buffer.writeln('📅 ÚLTIMAS 10 SESSÕES:');
    for (final session in sessions.reversed.take(10)) {
      buffer.writeln('   ${DateFormat('dd/MM HH:mm').format(session.sessionDate)}');
      buffer.writeln(
          '      ${session.questionsAcertouApi}/${session.totalQuestions} acertos (${(session.apiAccuracyBefore * 100).toStringAsFixed(0)}%)');
      if (session.questionsCorrect > 0) {
        buffer.writeln('      ✏️  ${session.questionsCorrect} correções do usuário');
      }
    }

    return buffer.toString();
  }

  /// Limpar histórico
  Future<void> clearHistory() async {
    await _prefs.remove(_storageKey);
    print('🗑️  Histórico de feedback limpo');
  }
}
