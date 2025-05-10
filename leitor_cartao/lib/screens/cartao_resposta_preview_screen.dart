//cartao_resposta_preview_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'resultado_screen.dart';

class CartaoRespostaPreviewScreen extends StatelessWidget {
  final Uint8List imagemProcessada;
  final Map<String, String> respostasAluno;
  final Map<String, String> gabarito;
  final String nomeAluno;
  final double notaFinal;
  final int tipoProva;
  final double pontuacaoTotal;

  // Adicionar campos para conectar com o site
  final int? alunoId;
  final int? simuladoId;
  final int? turmaId;
  final String? nomeTurma;
  final String? nomeSimulado;

  const CartaoRespostaPreviewScreen({
    super.key,
    required this.imagemProcessada,
    required this.respostasAluno,
    required this.gabarito,
    required this.nomeAluno,
    required this.notaFinal,
    required this.tipoProva,
    required this.pontuacaoTotal,
    this.alunoId,
    this.simuladoId,
    this.turmaId,
    this.nomeTurma,
    this.nomeSimulado,
  });

  @override
  Widget build(BuildContext context) {
    // Calcular estatísticas
    final int totalQuestoes = gabarito.length;
    final int questoesAcertadas = gabarito.keys
        .where((questao) => respostasAluno[questao] == gabarito[questao])
        .length;
    // ignore: unused_local_variable
    final double percentualAcerto =
        totalQuestoes > 0 ? (questoesAcertadas / totalQuestoes) * 100 : 0;

    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        title: const Text(
          'Visualização da Correção',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Camada de fundo escura
          Container(
            color: Colors.black87,
          ),

          // Conteúdo central - Cartão resposta e informações
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Informações sobre o aluno e nota
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Card(
                      color: Colors.white.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            Text(
                              nomeAluno,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (nomeTurma != null && nomeTurma!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Turma: $nomeTurma',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                            if (nomeSimulado != null &&
                                nomeSimulado!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Simulado: $nomeSimulado',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Nota: ${notaFinal.toStringAsFixed(1)} de $pontuacaoTotal · Acertos: $questoesAcertadas/$totalQuestoes',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            Text(
                              'Versão da prova: $tipoProva',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Cartão resposta com zoom habilitado
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 3.0,
                        boundaryMargin: const EdgeInsets.all(20.0),
                        child: Image.memory(
                          imagemProcessada,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),

                  // Fim da Column, SafeArea e Center
                ],
              ),
            ),
          ),
          // Botões na parte inferior
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Botão de recomeçar
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context); // Volta para a tela anterior
                        },
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text('RECOMEÇAR',
                            style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),

                  // Botão de confirmar
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Navegar para a tela de resultados
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ResultadoScreen(
                                nomeAluno: nomeAluno,
                                notaFinal: notaFinal,
                                respostasAluno: respostasAluno,
                                gabarito: gabarito,
                                tipoProva: tipoProva,
                                pontuacaoTotal: pontuacaoTotal,
                                // Passar os IDs e nomes para a tela de resultados
                                alunoId: alunoId,
                                simuladoId: simuladoId,
                                turmaId: turmaId,
                                nomeTurma: nomeTurma,
                                nomeSimulado: nomeSimulado,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: const Text('CONFIRMAR',
                            style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
