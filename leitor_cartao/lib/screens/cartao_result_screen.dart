// cartao_result_screen.dart
// Tela 5: Resultado e Análise do Cartão Processado
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/custom_app_bar.dart';
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
  final Map<int, String> gabarito;
  final String? versionCode;

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
    required this.gabarito,
    this.versionCode,
  });
}

// ─── Paleta ────────────────────────────────────────────────────────────────
const _kBgColor    = Color(0xFFF5F7FA);
const _kCardColor  = Colors.white;
const _kBlue       = Color(0xFF0DA6F2);
const _kGreen      = Color(0xFF22C55E);
const _kRed        = Color(0xFFEF4444);
const _kTextMain   = Color(0xFF1A1A2E);
const _kTextSub    = Color(0xFF6B7280);
const _kDivider    = Color(0xFFE5E7EB);

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
  bool _enviando = false;
  bool _enviado = false;
  String? _erroEnvio;

  @override
  void initState() {
    super.initState();
    _submeterResultado();
  }

  Future<void> _submeterResultado() async {
    setState(() {
      _enviando = true;
      _erroEnvio = null;
    });

    try {
      final Map<String, String> respostasMap = {};
      for (int i = 0; i < widget.result.respostasMarcadas.length; i++) {
        respostasMap[(i + 1).toString()] = widget.result.respostasMarcadas[i];
      }

      final Map<String, String> gabaritoMap = {};
      widget.result.gabarito.forEach((k, v) => gabaritoMap[k.toString()] = v);

      final versao = 'versao${widget.result.tipoProva}';
      final nota = _notaCalculada;

      final apiService = ApiService();
      final sucesso = await apiService.submitStudentResults(
        studentId: widget.result.aluno.id,
        simuladoId: widget.result.simulado.id,
        versao: versao,
        nota: nota,
        respostasAluno: respostasMap,
        gabarito: gabaritoMap,
      );

      if (mounted) {
        setState(() {
          _enviando = false;
          _enviado = sucesso;
          _erroEnvio = sucesso ? null : 'Erro ao enviar resultado';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _erroEnvio = 'Erro: $e';
        });
      }
    }
  }

  // Nota proporcional: acertos × notaMaxima / numQuestoes
  double get _notaCalculada {
    final total = widget.result.totalQuestoes;
    if (total == 0) return 0;
    return widget.result.acertos * widget.result.simulado.notaMaxima / total;
  }

  Color get _notaColor {
    final pct = widget.result.score;
    if (pct >= 70) return _kGreen;
    if (pct >= 50) return const Color(0xFFF59E0B);
    return _kRed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: CustomAppBar(showBack: true),
      body: Column(
        children: [
          // Banner de envio
          _buildStatusBanner(),
          // Conteúdo scrollável
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Card de identificação
                  _buildIdentCard(),
                  const SizedBox(height: 12),
                  // Card de nota
                  _buildNotaCard(),
                  const SizedBox(height: 12),
                  // Card de questões
                  _buildQuestoesCard(),
                  const SizedBox(height: 24),
                  // Botão NOVO CARTÃO
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text(
                      'NOVO CARTÃO',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    if (_enviando) {
      return _bannerContainer(
        color: const Color(0xFFEFF6FF),
        borderColor: const Color(0xFFBFDBFE),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kBlue),
            ),
            const SizedBox(width: 10),
            const Text(
              'Enviando resultado...',
              style: TextStyle(color: _kBlue, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    if (_enviado) {
      return _bannerContainer(
        color: const Color(0xFFF0FDF4),
        borderColor: const Color(0xFFBBF7D0),
        child: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: _kGreen, size: 16),
            SizedBox(width: 10),
            Text(
              'Resultado enviado com sucesso',
              style: TextStyle(color: _kGreen, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    if (_erroEnvio != null) {
      return _bannerContainer(
        color: const Color(0xFFFFF1F2),
        borderColor: const Color(0xFFFECACA),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: _kRed, size: 16),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Erro ao enviar resultado',
                style: TextStyle(color: _kRed, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            GestureDetector(
              onTap: _submeterResultado,
              child: const Text(
                'TENTAR NOVAMENTE',
                style: TextStyle(
                  color: _kRed,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                  decorationColor: _kRed,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _bannerContainer({
    required Color color,
    required Color borderColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: child,
    );
  }

  Widget _buildIdentCard() {
    final r = widget.result;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Identificação'),
          const SizedBox(height: 12),
          _identRow(Icons.quiz_rounded, 'Simulado', r.simulado.nome),
          _divider(),
          _identRow(Icons.person_rounded, 'Aluno', r.aluno.nome),
          _divider(),
          _identRow(
            Icons.groups_rounded,
            'Turma',
            r.aluno.turmaNome ?? '—',
          ),
          _divider(),
          _identRow(
            Icons.ballot_rounded,
            'Tipo de Prova',
            'TIPO ${r.tipoProva}',
          ),
        ],
      ),
    );
  }

  Widget _buildNotaCard() {
    final nota = _notaCalculada;
    final notaMax = widget.result.simulado.notaMaxima;
    final acertos = widget.result.acertos;
    final total = widget.result.totalQuestoes;
    final erros = widget.result.erros;
    final color = _notaColor;

    return _card(
      child: Column(
        children: [
          _cardTitle('Resultado'),
          const SizedBox(height: 20),
          // Nota grande
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                nota.toStringAsFixed(nota % 1 == 0 ? 0 : 1),
                style: TextStyle(
                  color: color,
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  ' / ${notaMax.toStringAsFixed(notaMax % 1 == 0 ? 0 : 1)}',
                  style: const TextStyle(
                    color: _kTextSub,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Barra de progresso
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? acertos / total : 0,
              minHeight: 8,
              backgroundColor: _kDivider,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 16),
          // Acertos / Erros
          Row(
            children: [
              Expanded(
                child: _statBox(
                  icon: Icons.check_circle_rounded,
                  iconColor: _kGreen,
                  label: 'Acertos',
                  value: '$acertos',
                  sub: 'de $total questões',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statBox(
                  icon: Icons.cancel_rounded,
                  iconColor: _kRed,
                  label: 'Erros',
                  value: '$erros',
                  sub: 'de $total questões',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestoesCard() {
    final respostas = widget.result.respostasMarcadas;
    final gabarito = widget.result.gabarito;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Gabarito Detalhado'),
          const SizedBox(height: 4),
          Text(
            '${respostas.length} questões processadas',
            style: const TextStyle(color: _kTextSub, fontSize: 12),
          ),
          const SizedBox(height: 12),
          // Cabeçalho da tabela
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                SizedBox(width: 32, child: Text('Nº', style: TextStyle(color: _kTextSub, fontSize: 12, fontWeight: FontWeight.w700))),
                Expanded(child: Center(child: Text('Aluno', style: TextStyle(color: _kTextSub, fontSize: 12, fontWeight: FontWeight.w700)))),
                Expanded(child: Center(child: Text('Gabarito', style: TextStyle(color: _kTextSub, fontSize: 12, fontWeight: FontWeight.w700)))),
                SizedBox(width: 28),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Linhas de questões
          ...List.generate(respostas.length, (i) {
            final qNum = i + 1;
            final marcou = respostas[i];
            final correto = gabarito[qNum] ?? '—';
            final acertou = marcou.isNotEmpty &&
                marcou != '?' &&
                marcou.toUpperCase() == correto.toUpperCase();
            final isEven = i % 2 == 0;

            return Container(
              decoration: BoxDecoration(
                color: isEven ? Colors.white : _kBgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$qNum.',
                      style: const TextStyle(color: _kTextMain, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _bubbleChip(
                        label: marcou.isEmpty || marcou == '?' ? '—' : marcou.toUpperCase(),
                        color: acertou ? _kGreen : _kRed,
                        light: !acertou && (marcou.isEmpty || marcou == '?'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _bubbleChip(
                        label: correto.toUpperCase(),
                        color: _kBlue,
                        light: false,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    child: Icon(
                      acertou ? Icons.check_rounded : Icons.close_rounded,
                      color: acertou ? _kGreen : _kRed,
                      size: 18,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }

  Widget _cardTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _kTextMain,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _identRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: _kBlue, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: _kTextSub, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: _kTextMain, fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return const Divider(color: _kDivider, height: 1, thickness: 1);
  }

  Widget _statBox({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: iconColor.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: iconColor, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: _kTextMain, fontSize: 12, fontWeight: FontWeight.w700)),
          Text(sub, style: const TextStyle(color: _kTextSub, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _bubbleChip({
    required String label,
    required Color color,
    required bool light,
  }) {
    return Container(
      width: 32,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: light ? Colors.transparent : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: light ? _kDivider : color.withOpacity(0.5),
          width: 1.2,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: light ? _kTextSub : color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
