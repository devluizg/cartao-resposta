/// Data classes compartilhadas entre telas do fluxo de correção.
class SimuladoData {
  final int id;
  final String nome;
  final int numQuestoes;
  final String? dataCriacao;
  final double notaMaxima;

  const SimuladoData({
    required this.id,
    required this.nome,
    required this.numQuestoes,
    this.dataCriacao,
    this.notaMaxima = 10.0,
  });
}

class AlunoData {
  final int id;
  final String nome;
  final String matricula;
  final String? turmaNome;

  const AlunoData({
    required this.id,
    required this.nome,
    required this.matricula,
    this.turmaNome,
  });
}
