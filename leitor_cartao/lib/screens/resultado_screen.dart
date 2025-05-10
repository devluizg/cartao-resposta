//resultado_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ResultadoScreen extends StatefulWidget {
  final String nomeAluno;
  final double notaFinal;
  final Map<String, String> respostasAluno;
  final Map<String, String> gabarito;
  final int tipoProva;
  final double pontuacaoTotal;

  // Adicionando os campos necessários para enviar para o site
  final int? alunoId;
  final int? simuladoId;
  final int? turmaId;
  final String? nomeTurma;
  final String? nomeSimulado;

  const ResultadoScreen({
    super.key,
    required this.nomeAluno,
    required this.notaFinal,
    required this.respostasAluno,
    required this.gabarito,
    this.tipoProva = 1,
    this.pontuacaoTotal = 10.0,
    this.alunoId, // Campo para o ID do aluno
    this.simuladoId, // Campo para o ID do simulado
    this.turmaId, // Campo para o ID da turma
    this.nomeTurma, // Campo para o nome da turma
    this.nomeSimulado, // Campo para o nome do simulado
  });

  @override
  State<ResultadoScreen> createState() => _ResultadoScreenState();
}

class _ResultadoScreenState extends State<ResultadoScreen> {
  bool _isSubmitting = false;
  bool _hasSubmitted = false;
  String _submissionMessage = '';

  @override
  Widget build(BuildContext context) {
    // Calcular o percentual de acerto
    final int totalQuestoes = widget.gabarito.length;
    final int questoesAcertadas = widget.gabarito.keys
        .where(
          (questao) =>
              widget.respostasAluno[questao] == widget.gabarito[questao],
        )
        .length;
    final double percentualAcerto =
        totalQuestoes > 0 ? (questoesAcertadas / totalQuestoes) * 100 : 0;

    // Verificar se temos os dados necessários para submissão
    final bool canSubmit =
        widget.alunoId != null && widget.simuladoId != null && !_hasSubmitted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado do Aluno'),
        actions: [
          // Botão de compartilhar na app bar
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Implementar funcionalidade de compartilhamento
              _shareResults();
            },
            tooltip: 'Compartilhar resultados',
          ),
        ],
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Aluno: ${widget.nomeAluno}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        // Status de envio
                        if (_hasSubmitted)
                          Chip(
                            label: const Text('Enviado'),
                            avatar: const Icon(Icons.check, size: 16),
                            backgroundColor: Colors.green.withOpacity(0.2),
                            labelStyle: const TextStyle(color: Colors.green),
                          ),
                      ],
                    ),
                    if (widget.nomeTurma != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        'Turma: ${widget.nomeTurma}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                    if (widget.nomeSimulado != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        'Simulado: ${widget.nomeSimulado}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Mostrar o tipo de prova
                    Text(
                      'Versão da Prova: ${widget.tipoProva}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Exibir a nota final formatada com 1 casa decimal
                    Row(
                      children: [
                        const Text(
                          'Nota Final: ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.notaFinal.toStringAsFixed(1)} de ${widget.pontuacaoTotal}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color:
                                widget.notaFinal >= (widget.pontuacaoTotal / 2)
                                    ? Colors.green
                                    : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Exibir percentual de acerto
                    Row(
                      children: [
                        const Text(
                          'Acertos: ',
                          style: TextStyle(fontSize: 16),
                        ),
                        Text(
                          '$questoesAcertadas de $totalQuestoes (${percentualAcerto.toStringAsFixed(1)}%)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: percentualAcerto >= 60
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Mostrar mensagem de submissão se houver
            if (_submissionMessage.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _hasSubmitted
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _hasSubmitted ? Colors.green : Colors.red,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _hasSubmitted ? Icons.check_circle : Icons.error,
                      color: _hasSubmitted ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _submissionMessage,
                        style: TextStyle(
                          color: _hasSubmitted ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Botão para enviar resultados para o site
            if (canSubmit || _hasSubmitted)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: ElevatedButton.icon(
                  onPressed: (_isSubmitting || _hasSubmitted)
                      ? null
                      : _submitResultsToWebsite,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_hasSubmitted ? Icons.check : Icons.cloud_upload),
                  label: Text(_isSubmitting
                      ? 'Enviando...'
                      : _hasSubmitted
                          ? 'Resultados Enviados'
                          : 'Enviar Resultados para o Site'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasSubmitted ? Colors.grey : Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    disabledBackgroundColor:
                        _hasSubmitted ? Colors.green.withOpacity(0.6) : null,
                  ),
                ),
              ),

            const SizedBox(height: 12),
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
                itemCount: widget.gabarito.length,
                itemBuilder: (context, index) {
                  final numeroQuestao = (index + 1).toString();
                  final respostaCorreta = widget.gabarito[numeroQuestao] ?? '-';
                  final respostaAluno =
                      widget.respostasAluno[numeroQuestao] ?? 'Não respondida';
                  final bool acertou = respostaAluno == respostaCorreta;

                  // Calcular valor da questão com base na pontuação total
                  final double valorQuestao =
                      widget.pontuacaoTotal / widget.gabarito.length;

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
            // Botões de navegação
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Voltar'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // Navegar para a tela inicial
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      },
                      icon: const Icon(Icons.home),
                      label: const Text('Início'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
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

  // Método para enviar resultados para o site
  Future<void> _submitResultsToWebsite() async {
    // Verificar novamente se temos os dados necessários
    if (widget.alunoId == null || widget.simuladoId == null) {
      setState(() {
        _submissionMessage =
            'Não foi possível enviar: dados do aluno ou simulado faltando';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submissionMessage = '';
    });

    try {
      final apiService = ApiService();
      final versao =
          'versao${widget.tipoProva}'; // Converter para versao1, versao2, etc.

      // Mostrar snackbar informando que está enviando
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 16),
              Text('Enviando resultados para o site...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      final success = await apiService.submitStudentResults(
        studentId: widget.alunoId!,
        simuladoId: widget.simuladoId!,
        versao: versao,
        nota: widget.notaFinal,
        respostasAluno: widget.respostasAluno,
        gabarito: widget.gabarito,
      );

      setState(() {
        _isSubmitting = false;
        _hasSubmitted = success;
        _submissionMessage = success
            ? 'Resultados enviados com sucesso para o site!'
            : 'Falha ao enviar resultados. Tente novamente.';
      });

      // Mostrar snackbar com resultado da operação
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 16),
              Text(success
                  ? 'Resultados enviados com sucesso!'
                  : 'Falha ao enviar resultados.'),
            ],
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _submissionMessage = 'Erro ao enviar: $e';
      });

      // Mostrar snackbar com erro
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 16),
              Expanded(child: Text('Erro ao enviar: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // Método para compartilhar os resultados
  void _shareResults() {
    // Aqui você pode implementar o compartilhamento usando pacotes como share_plus
    // Por exemplo, compartilhar um texto com o resultado
    // ignore: unused_local_variable
    final message = 'Resultado de ${widget.nomeAluno} no simulado '
        '${widget.nomeSimulado ?? ""}:\n'
        'Nota: ${widget.notaFinal.toStringAsFixed(1)} de ${widget.pontuacaoTotal}\n'
        'Acertos: ${widget.gabarito.keys.where(
              (questao) =>
                  widget.respostasAluno[questao] == widget.gabarito[questao],
            ).length} de ${widget.gabarito.length}';

    // Exemplo de implementação (necessitaria do pacote share_plus):
    // Share.share(message);

    // Como alternativa, mostrar um snackbar informando que a função está em desenvolvimento
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Função de compartilhamento em desenvolvimento'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
