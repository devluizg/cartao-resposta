class QuestaoModel {
  final int id;
  final String disciplina;
  final String conteudo;
  final String enunciado;
  final String alternativaA;
  final String alternativaB;
  final String alternativaC;
  final String alternativaD;
  final String alternativaE;
  final String respostaCorreta;
  final String nivelDificuldade;

  QuestaoModel({
    required this.id,
    required this.disciplina,
    required this.conteudo,
    required this.enunciado,
    required this.alternativaA,
    required this.alternativaB,
    required this.alternativaC,
    required this.alternativaD,
    required this.alternativaE,
    required this.respostaCorreta,
    required this.nivelDificuldade,
  });

  factory QuestaoModel.fromJson(Map<String, dynamic> json) {
    return QuestaoModel(
      id: json['id'] as int,
      disciplina: json['disciplina'] as String,
      conteudo: json['conteudo'] as String,
      enunciado: json['enunciado'] as String,
      alternativaA: json['alternativa_a'] as String,
      alternativaB: json['alternativa_b'] as String,
      alternativaC: json['alternativa_c'] as String,
      alternativaD: json['alternativa_d'] as String,
      alternativaE: json['alternativa_e'] as String,
      respostaCorreta: json['resposta_correta'] as String,
      nivelDificuldade: json['nivel_dificuldade'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'disciplina': disciplina,
      'conteudo': conteudo,
      'enunciado': enunciado,
      'alternativa_a': alternativaA,
      'alternativa_b': alternativaB,
      'alternativa_c': alternativaC,
      'alternativa_d': alternativaD,
      'alternativa_e': alternativaE,
      'resposta_correta': respostaCorreta,
      'nivel_dificuldade': nivelDificuldade,
    };
  }
}

class QuestaoListResponse {
  final int count;
  final String? next;
  final String? previous;
  final List<QuestaoModel> results;

  QuestaoListResponse({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  factory QuestaoListResponse.fromJson(Map<String, dynamic> json) {
    return QuestaoListResponse(
      count: json['count'] as int,
      next: json['next'] as String?,
      previous: json['previous'] as String?,
      results: (json['results'] as List<dynamic>)
          .map((e) => QuestaoModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
