// cartao_result_screen.dart
// Tela 5: Resultado e Análise do Cartão Processado
import 'package:flutter/material.dart';
import 'simulado_selection_screen.dart';

class CartaoResultData {
  final SimuladoData simulado;
  final AlunoData aluno;
  final int tipoProva;
  final int totalQuestoes;
  final int acertos;
  final int erros;
  final double score;
  final List<String> respostasMarcadas;
  final String tempoProcessamento;
  final String qualidade;

  CartaoResultData({
    required this.simulado,
    required this.aluno,
    required this.tipoProva,
    required this.totalQuestoes,
    required this.acertos,
    required this.erros,
    required this.score,
    required this.respostasMarcadas,
    required this.tempoProcessamento,
    required this.qualidade,
  });
}

/// Tela 5: Resultado e Análise do Cartão Processado
class CartaoResultScreen extends StatefulWidget {
  final CartaoResultData result;

  const CartaoResultScreen({
    super.key,
    required this.result,
  });

  @override
  State<CartaoResultScreen> createState() => _CartaoResultScreenState();
}

class _CartaoResultScreenState extends State<CartaoResultScreen> {
  bool _expandedRespostas = false;

  Color get _scoreColor {
    if (widget.result.score >= 70) {
      return const Color(0xFF22C55E); // Verde
    } else if (widget.result.score >= 50) {
      return const Color(0xFFF59E0B); // Amarelo
    } else {
      return const Color(0xFFEF4444); // Vermelho
    }
  }

  String get _performanceLabel {
    if (widget.result.score >= 85) {
      return 'Excelente!';
    } else if (widget.result.score >= 70) {
      return 'Bom!';
    } else if (widget.result.score >= 50) {
      return 'Adequado';
    } else {
      return 'Precisa melhorar';
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text(
            'Passo 5: Resultado',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          elevation: 0,
          automaticallyImplyLeading: true,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              // CABEÇALHO COM SCORE
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Column(
                  children: [
                    // SCORE CIRCULAR
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _scoreColor,
                          width: 8,
                        ),
                        color: _scoreColor.withOpacity(0.1),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${widget.result.score.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: _scoreColor,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _performanceLabel,
                              style: TextStyle(
                                color: _scoreColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // INFORMAÇÕES DO SIMULADO E ALUNO
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(
                            icon: Icons.assignment,
                            label: 'Simulado',
                            value: widget.result.simulado.nome,
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            icon: Icons.person,
                            label: 'Aluno',
                            value: widget.result.aluno.nome,
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            icon: Icons.ballot,
                            label: 'Tipo de Prova',
                            value: 'TIPO ${widget.result.tipoProva}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // MÉTRICAS DETALHADAS
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detalhes da Correção',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // GRID DE MÉTRICAS
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      children: [
                        _buildMetricCard(
                          icon: Icons.check_circle,
                          color: const Color(0xFF22C55E),
                          label: 'Acertos',
                          value: '${widget.result.acertos}',
                          subtitle:
                              'de ${widget.result.totalQuestoes} questões',
                        ),
                        _buildMetricCard(
                          icon: Icons.cancel,
                          color: const Color(0xFFEF4444),
                          label: 'Erros',
                          value: '${widget.result.erros}',
                          subtitle:
                              'de ${widget.result.totalQuestoes} questões',
                        ),
                        _buildMetricCard(
                          icon: Icons.schedule,
                          color: const Color(0xFF0DA6F2),
                          label: 'Tempo',
                          value: widget.result.tempoProcessamento,
                          subtitle: 'de processamento',
                        ),
                        _buildMetricCard(
                          icon: Icons.photo,
                          color: const Color(0xFFF59E0B),
                          label: 'Qualidade',
                          value: widget.result.qualidade,
                          subtitle: 'da fotografia',
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // RESPOSTAS MARCADAS
                    const Text(
                      'Respostas Marcadas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          // RESUMO (sempre visível)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Mostrando resposta de cada questão',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _expandedRespostas =
                                              !_expandedRespostas;
                                        });
                                      },
                                      child: Icon(
                                        _expandedRespostas
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // PREVIEW COMPACTADO: Primeiras 5 respostas
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: List.generate(
                                    _expandedRespostas
                                        ? widget.result.respostasMarcadas
                                            .length
                                        : (widget
                                                .result.respostasMarcadas.length >
                                            5
                                            ? 5
                                            : widget.result.respostasMarcadas
                                                .length),
                                    (i) {
                                      final resposta = widget
                                          .result.respostasMarcadas[i];
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0DA6F2)
                                              .withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: const Color(0xFF0DA6F2)
                                                .withOpacity(0.5),
                                          ),
                                        ),
                                        child: Text(
                                          'Q${i + 1}: $resposta',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),

                                // "Ver mais" se houver mais de 5
                                if (!_expandedRespostas &&
                                    widget.result.respostasMarcadas.length >
                                        5)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(
                                      '... e mais ${widget.result.respostasMarcadas.length - 5} questões',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // BOTÕES DE AÇÃO
                    Row(
                      children: [
                        // NOVO CARTÃO
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              // Volta para a tela de seleção
                              Navigator.of(context).popUntil(
                                (route) => route.isFirst,
                              );
                            },
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('NOVO CARTÃO'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0DA6F2),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // COMPARTILHAR (placeholder)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Compartilhar resultado'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.share),
                            label: const Text('COMPARTILHAR'),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // INFO: Resultado será sincronizado com servidor
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade900.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF0DA6F2).withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_rounded,
                            color: Color(0xFF0DA6F2),
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Este resultado será sincronizado com o servidor quando houver conexão.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: const Color(0xFF0DA6F2),
          size: 18,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
