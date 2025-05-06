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

class QuestaoSimuladoModel {
  final int ordem;
  final QuestaoModel questao;

  QuestaoSimuladoModel({
    required this.ordem,
    required this.questao,
  });

  factory QuestaoSimuladoModel.fromJson(Map<String, dynamic> json) {
    return QuestaoSimuladoModel(
      ordem: json['ordem'] as int,
      questao: QuestaoModel.fromJson(json['questao'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ordem': ordem,
      'questao': questao.toJson(),
    };
  }
}

class SimuladoModel {
  final int id;
  final String titulo;
  final String descricao;
  final String? cabecalho;
  final String? instrucoes;
  final List<QuestaoSimuladoModel> questoes;
  final DateTime dataCriacao;
  final DateTime ultimaModificacao;
  final List<int> classes;

  SimuladoModel({
    required this.id,
    required this.titulo,
    required this.descricao,
    this.cabecalho,
    this.instrucoes,
    required this.questoes,
    required this.dataCriacao,
    required this.ultimaModificacao,
    required this.classes,
  });

  factory SimuladoModel.fromJson(Map<String, dynamic> json) {
    return SimuladoModel(
      id: json['id'] as int,
      titulo: json['titulo'] as String,
      descricao: json['descricao'] as String,
      cabecalho: json['cabecalho'] as String?,
      instrucoes: json['instrucoes'] as String?,
      questoes: (json['questoes'] as List<dynamic>)
          .map((q) => QuestaoSimuladoModel.fromJson(q as Map<String, dynamic>))
          .toList(),
      dataCriacao: DateTime.parse(json['data_criacao'] as String),
      ultimaModificacao: DateTime.parse(json['ultima_modificacao'] as String),
      classes: List<int>.from(json['classes']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titulo': titulo,
      'descricao': descricao,
      'cabecalho': cabecalho,
      'instrucoes': instrucoes,
      'questoes': questoes.map((q) => q.toJson()).toList(),
      'data_criacao': dataCriacao.toIso8601String(),
      'ultima_modificacao': ultimaModificacao.toIso8601String(),
      'classes': classes,
    };
  }
}

class SimuladoListResponse {
  final int count;
  final String? next;
  final String? previous;
  final List<SimuladoModel> results;

  SimuladoListResponse({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  factory SimuladoListResponse.fromJson(Map<String, dynamic> json) {
    return SimuladoListResponse(
      count: json['count'] as int,
      next: json['next'] as String?,
      previous: json['previous'] as String?,
      results: (json['results'] as List<dynamic>)
          .map((e) => SimuladoModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
