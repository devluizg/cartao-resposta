// cartao_preview_screen.dart
// Tela 4: Preview e Processamento do Cartão
import 'package:flutter/material.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../services/claude_vision_service.dart';
import 'simulado_selection_screen.dart';
import 'cartao_result_screen.dart' show CartaoResultData, CartaoResultScreen;

/// Tela 4: Preview do Cartão e Processamento
class CartaoPreviewScreen extends StatefulWidget {
  final File imageFile;
  final SimuladoData simulado;
  final AlunoData aluno;
  final int tipoProva;
  final String? versionCode;

  const CartaoPreviewScreen({
    super.key,
    required this.imageFile,
    required this.simulado,
    required this.aluno,
    required this.tipoProva,
    this.versionCode,
  });

  @override
  State<CartaoPreviewScreen> createState() => _CartaoPreviewScreenState();
}

class _CartaoPreviewScreenState extends State<CartaoPreviewScreen> {
  bool _isProcessingVision = false;
  List<String>? _respostasDetectadas;
  Map<int, String>? _gabaritoCarregado;
  int _acertos = 0;
  int _erros = 0;
  double _score = 0;

  static const List<String> _letters = ['A', 'B', 'C', 'D', 'E'];

  @override
  void initState() {
    super.initState();
    _processarComClaudeVision();
  }

  Future<void> _processarComClaudeVision() async {
    setState(() {
      _isProcessingVision = true;
      _respostasDetectadas = null;
    });

    try {
      final jsonData = await ClaudeVisionService.processarCartao(
        imageFile: widget.imageFile,
        numQuestoes: widget.simulado.numQuestoes,
      );

      final respostasJson = jsonData['respostas'] as Map<String, dynamic>;
      final List<String> respostas = List.generate(
        widget.simulado.numQuestoes,
        (i) => (respostasJson[(i + 1).toString()] as String?) ?? '',
      );

      final gabarito = await _carregarGabarito();
      int acertos = 0;
      int erros = 0;
      for (int i = 0; i < respostas.length; i++) {
        if (gabarito.containsKey(i + 1)) {
          if (respostas[i] == gabarito[i + 1]) acertos++;
          else erros++;
        }
      }

      if (mounted) {
        setState(() {
          _respostasDetectadas = respostas;
          _gabaritoCarregado = gabarito;
          _acertos = acertos;
          _erros = erros;
          _score = (acertos / widget.simulado.numQuestoes) * 100;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro Claude Vision: $e'),
            backgroundColor: Colors.deepPurple,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingVision = false);
    }
  }

  bool _confirmando = false;

  Future<void> _confirmar() async {
    if (_confirmando) return;
    setState(() => _confirmando = true);

    // Consumir crédito antes de registrar o resultado
    final apiService = ApiService();
    final creditoConsumido = await apiService.consumeCredit(
      studentId: widget.aluno.id,
      simuladoId: widget.simulado.id,
      action: 'correction',
    );

    if (!creditoConsumido && mounted) {
      setState(() => _confirmando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.bolt_rounded, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Sem créditos disponíveis para confirmar a correção.')),
            ],
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final result = CartaoResultData(
      simulado: widget.simulado,
      aluno: widget.aluno,
      tipoProva: widget.tipoProva,
      totalQuestoes: widget.simulado.numQuestoes,
      acertos: _acertos,
      erros: _erros,
      score: _score,
      respostasMarcadas: _respostasDetectadas!,
      tempoProcessamento: 'Claude Vision',
      qualidade: 'Claude Vision',
      gabarito: _gabaritoCarregado ?? {},
      versionCode: widget.versionCode,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CartaoResultScreen(result: result),
        ),
      );
    }
    setState(() => _confirmando = false);
  }

  Future<Map<int, String>> _carregarGabarito() async {
    try {
      final apiService = ApiService();
      final gabaritoString = await apiService.getGabarito(
        widget.simulado.id,
        tipo: widget.tipoProva.toString(),
      );
      if (gabaritoString == null || gabaritoString.isEmpty) return {};
      final Map<int, String> gabarito = {};
      gabaritoString.forEach((key, value) {
        try {
          gabarito[int.parse(key)] = value.toUpperCase();
        } catch (_) {}
      });
      return gabarito;
    } catch (_) {
      return {};
    }
  }

  // ────────────────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_isProcessingVision,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: !_isProcessingVision,
          leading: _isProcessingVision
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A2E), size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
          title: RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'SIMULADO',
                  style: TextStyle(color: Color(0xFF1A1A2E), fontSize: 16, fontWeight: FontWeight.w900),
                ),
                TextSpan(
                  text: 'APP',
                  style: TextStyle(color: Color(0xFF0DA6F2), fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: const Color(0xFFE5E7EB)),
          ),
        ),
        body: _isProcessingVision
            ? _buildLoadingLayout()
            : _respostasDetectadas != null
                ? _buildResultsLayout()
                : _buildErrorLayout(),
      ),
    );
  }

  // ── Layout: processando ──────────────────────────────────────────
  Widget _buildLoadingLayout() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 3.0,
              child: Image.file(widget.imageFile, fit: BoxFit.contain),
            ),
          ),
        ),
        _buildPanel(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF0DA6F2)),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Identificando respostas...',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _btnRefazer(),
          ],
        )),
      ],
    );
  }

  // ── Layout: resultados ───────────────────────────────────────────
  Widget _buildResultsLayout() {
    final hasGabarito =
        _gabaritoCarregado != null && _gabaritoCarregado!.isNotEmpty;

    return Column(
      children: [
        // Miniatura da foto
        _buildPhotoThumbnail(),

        // Resumo de acertos (quando gabarito disponível)
        if (hasGabarito) _buildSummaryBar(),

        // Diagrama esquemático (área principal)
        Expanded(child: _buildSchematicDiagram()),

        // Botões de ação
        _buildPanel(child: Row(
          children: [
            Expanded(child: _btnRefazer()),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _confirmando ? null : _confirmar,
                icon: _confirmando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 18),
                label: Text(
                  _confirmando ? 'AGUARDE...' : 'CONFIRMAR',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0DA6F2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        )),
      ],
    );
  }

  // ── Layout: erro ─────────────────────────────────────────────────
  Widget _buildErrorLayout() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 3.0,
              child: Image.file(widget.imageFile, fit: BoxFit.contain),
            ),
          ),
        ),
        _buildPanel(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                SizedBox(width: 8),
                Text(
                  'Falha ao identificar respostas',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _btnRefazer()),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _processarComClaudeVision,
                    icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                    label: const Text(
                      'TENTAR NOVAMENTE',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0DA6F2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        )),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // COMPONENTES
  // ────────────────────────────────────────────────────────────────

  /// Painel inferior
  Widget _buildPanel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: child,
    );
  }

  /// Miniatura da foto capturada (apenas referência visual)
  Widget _buildPhotoThumbnail() {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              widget.imageFile,
              height: 78,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_respostasDetectadas!.length} respostas detectadas',
                  style: const TextStyle(
                    color: Color(0xFF1A1A2E),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Confira o gabarito abaixo',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                ),
              ],
            ),
          ),
          const Icon(Icons.grid_view_rounded, color: Color(0xFF0DA6F2), size: 20),
        ],
      ),
    );
  }

  /// Barra de resumo de acertos/erros (só quando gabarito disponível)
  Widget _buildSummaryBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _summaryChip(
            icon: Icons.check_circle_outline,
            label: '$_acertos acertos',
            color: const Color(0xFF22C55E),
          ),
          _summaryChip(
            icon: Icons.cancel_outlined,
            label: '$_erros erros',
            color: const Color(0xFFEF4444),
          ),
          _summaryChip(
            icon: Icons.percent,
            label: '${_score.toStringAsFixed(0)}%',
            color: const Color(0xFF0DA6F2),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // DIAGRAMA ESQUEMÁTICO
  // ────────────────────────────────────────────────────────────────

  Widget _buildSchematicDiagram() {
    final respostas = _respostasDetectadas!;
    final gabarito = _gabaritoCarregado ?? {};
    final numQ = widget.simulado.numQuestoes;
    final numCols = numQ > 23 ? 2 : 1;
    final qPerCol = numCols == 1 ? numQ : (numQ + 1) ~/ 2;

    if (numCols == 1) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: _buildColumn(
          from: 1,
          to: numQ,
          respostas: respostas,
          gabarito: gabarito,
        ),
      );
    }

    // Duas colunas
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildColumn(
                from: 1,
                to: qPerCol,
                respostas: respostas,
                gabarito: gabarito,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildColumn(
                from: qPerCol + 1,
                to: numQ,
                respostas: respostas,
                gabarito: gabarito,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumn({
    required int from,
    required int to,
    required List<String> respostas,
    required Map<int, String> gabarito,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildColumnHeader(),
          for (int q = from; q <= to; q++)
            _buildQuestionRow(
              q: q,
              detected: q <= respostas.length ? respostas[q - 1] : '',
              gabAnswer: gabarito[q],
              isEven: (q - from) % 2 == 1,
            ),
        ],
      ),
    );
  }

  Widget _buildColumnHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FA),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      child: Row(
        children: [
          const SizedBox(width: 24),
          for (final letter in _letters)
            Expanded(
              child: Center(
                child: Text(
                  letter,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestionRow({
    required int q,
    required String detected,
    required String? gabAnswer,
    required bool isEven,
  }) {
    final detectedUpper = detected.toUpperCase();
    final hasGabarito = gabAnswer != null;

    return Container(
      color: isEven ? const Color(0xFFF9FAFB) : Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              q.toString().padLeft(2, '0'),
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          for (final letter in _letters)
            Expanded(
              child: Center(
                child: _buildBubble(
                  letter: letter,
                  detectedUpper: detectedUpper,
                  gabAnswer: hasGabarito ? gabAnswer : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBubble({
    required String letter,
    required String detectedUpper,
    required String? gabAnswer,
  }) {
    final isDetected = detectedUpper == letter;

    Color fill;
    Color border;
    Color textColor;

    if (isDetected) {
      final correct = gabAnswer == null || detectedUpper == gabAnswer;
      fill = correct ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
      border = correct ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
      textColor = Colors.white;
    } else {
      fill = Colors.transparent;
      border = const Color(0xFFD1D5DB);
      textColor = const Color(0xFF9CA3AF);
    }

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: border, width: 1.5),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: textColor,
            fontSize: 7,
            fontWeight: isDetected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // BOTÕES
  // ────────────────────────────────────────────────────────────────

  Widget _btnRefazer() {
    return OutlinedButton.icon(
      onPressed: () => Navigator.pop(context),
      icon: const Icon(Icons.refresh_rounded, color: Color(0xFF6B7280), size: 18),
      label: const Text(
        'REFAZER',
        style: TextStyle(
          color: Color(0xFF6B7280),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFFD1D5DB)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
