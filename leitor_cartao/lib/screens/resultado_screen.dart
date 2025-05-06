import 'package:flutter/material.dart';

class ResultadoScreen extends StatelessWidget {
  final String nomeAluno;
  final double notaFinal;
  final Map<String, String> respostasAluno;
  final Map<String, String> gabarito;
  final int tipoProva; // Novo parâmetro
  final double pontuacaoTotal; // Novo parâmetro

  const ResultadoScreen({
    super.key,
    required this.nomeAluno,
    required this.notaFinal,
    required this.respostasAluno,
    required this.gabarito,
    this.tipoProva = 1, // Valor padrão
    this.pontuacaoTotal = 10.0, // Valor padrão
  });

  @override
  Widget build(BuildContext context) {
    // Calcular o percentual de acerto
    final int totalQuestoes = gabarito.length;
    final int questoesAcertadas = gabarito.keys
        .where(
          (questao) => respostasAluno[questao] == gabarito[questao],
        )
        .length;
    final double percentualAcerto =
        totalQuestoes > 0 ? (questoesAcertadas / totalQuestoes) * 100 : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado do Aluno'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aluno: $nomeAluno',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Mostrar o tipo de prova
                    Text(
                      'Tipo de Prova: $tipoProva',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Exibir a nota final formatada com 1 casa decimal
                    Text(
                      'Nota Final: ${notaFinal.toStringAsFixed(1)} de $pontuacaoTotal',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: notaFinal >= (pontuacaoTotal / 2)
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    const SizedBox(height: 5),
                    // Exibir percentual de acerto
                    Text(
                      'Acertos: $questoesAcertadas de $totalQuestoes (${percentualAcerto.toStringAsFixed(1)}%)',
                      style: TextStyle(
                        fontSize: 16,
                        color:
                            percentualAcerto >= 60 ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Detalhamento por questão:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: gabarito.length,
                itemBuilder: (context, index) {
                  final numeroQuestao = (index + 1).toString();
                  final respostaCorreta = gabarito[numeroQuestao] ?? '-';
                  final respostaAluno =
                      respostasAluno[numeroQuestao] ?? 'Não respondida';
                  final bool acertou = respostaAluno == respostaCorreta;

                  // Calcular valor da questão com base na pontuação total
                  final double valorQuestao = pontuacaoTotal / gabarito.length;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: acertou ? Colors.green : Colors.red,
                        child: Text(numeroQuestao),
                      ),
                      title: Text('Sua resposta: $respostaAluno'),
                      subtitle: Text('Correta: $respostaCorreta'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Exibir pontuação da questão
                          Text(
                            acertou
                                ? '+${valorQuestao.toStringAsFixed(1)}'
                                : '0,0',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: acertou ? Colors.green : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            acertou ? Icons.check : Icons.close,
                            color: acertou ? Colors.green : Colors.red,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
