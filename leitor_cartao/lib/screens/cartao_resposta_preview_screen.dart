//cartao_resposta_preview_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'resultado_screen.dart';
import '../services/credit_manager.dart';
import 'dart:developer' as developer;

class CartaoRespostaPreviewScreen extends StatefulWidget {
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
  State<CartaoRespostaPreviewScreen> createState() =>
      _CartaoRespostaPreviewScreenState();
}

class _CartaoRespostaPreviewScreenState
    extends State<CartaoRespostaPreviewScreen> {
  // Design System - Nova Paleta (Modo Escuro para Preview)
  static const Color primary = Color(0xFF0DA6F2);       // Azul claro/primário
  static const Color primaryDark = Color(0xFF003D5C);   // Azul escuro
  static const Color bgDark = Color(0xFF121E25);        // Azul escuro (fundo)
  static const Color surfaceDark = Color(0xFF1A2A33);   // Cards (fundo)
  static const Color success = Color(0xFF16A34A);       // Verde (link icon color)
  static const Color danger = Color(0xFFDC2626);        // Vermelho (mantido do material default, ajustado)
  static const Color textLight = Color(0xFFF8FAFC);     // Texto claro (Cinza super claro)

  // Sistema de créditos
  final CreditManager _creditManager = CreditManager();
  bool _checkingCredits = false;
  bool _processingCorrection = false;
  int _availableCredits = 0;
  bool _hasCheckedCredits = false;

  @override
  void initState() {
    super.initState();
    _checkUserCredits();
  }

  /// Verificar créditos do usuário
  Future<void> _checkUserCredits() async {
    if (_hasCheckedCredits) return;

    setState(() {
      _checkingCredits = true;
    });

    try {
      final credits = await _creditManager.getAvailableCredits();
      if (mounted) {
        setState(() {
          _availableCredits = credits;
          _checkingCredits = false;
          _hasCheckedCredits = true;
        });

        developer.log('💰 Créditos disponíveis: $_availableCredits');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _availableCredits = 0;
          _checkingCredits = false;
          _hasCheckedCredits = true;
        });

        developer.log('💰 Erro ao verificar créditos: $e');
      }
    }
  }

  /// Confirmar correção com verificação de créditos (sem popup de confirmação)
  Future<void> _confirmarCorrecao() async {
    // Se ainda está verificando créditos, aguardar
    if (_checkingCredits) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 16),
              Text('Verificando créditos...'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Verificar créditos atualizados
    final hasCredits =
        await _creditManager.getAvailableCredits(forceRefresh: true);

    if (hasCredits <= 0) {
      // Mostrar dialog de créditos insuficientes
      await CreditManager.showInsufficientCreditsDialog(
        // ignore: use_build_context_synchronously
        context,
        currentCredits: hasCredits,
        onBuyCredits: () async {
          // Navegar para a tela de compra de créditos
          Navigator.pop(context); // Fechar o dialog primeiro

          final result = await Navigator.pushNamed(context, '/loja-creditos');

          // Se o usuário comprou créditos, recarregar os créditos disponíveis
          if (result == true) {
            await _checkUserCredits();

            // Mostrar mensagem de sucesso
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 16),
                      Text('Créditos adquiridos com sucesso!'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
        },
      );
      return;
    }

    // ✅ Processar correção diretamente (sem popup de confirmação)
    await _processCorrection();
  }

  /// Processar correção e consumir crédito
  Future<void> _processCorrection() async {
    setState(() {
      _processingCorrection = true;
    });

    // Mostrar loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            color: const Color(0xFF1D203A), // AppColors.bgSurface
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(
                  color: Color(0xFF31355B), width: 1), // AppColors.borderColor
            ),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: primary, // AppColors.primaryColor
                    backgroundColor: Color(0xFF31355B), // AppColors.borderColor
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Processando correção...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFFE0E6F1), // AppColors.textLight
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Consumindo crédito',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8C96C3), // AppColors.textMuted
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      // Consumir o crédito
      final creditConsumed = await _creditManager.consumeCredit(
        studentId: widget.alunoId ?? 0,
        simuladoId: widget.simuladoId ?? 0,
        action: 'simulado_correction',
      );

      // Fechar loading
      if (mounted) Navigator.pop(context);

      if (!creditConsumed) {
        // Erro ao consumir crédito
        if (mounted) {
          setState(() {
            _processingCorrection = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error, color: Colors.white),
                  SizedBox(width: 16),
                  Text('Erro ao processar crédito. Tente novamente.'),
                ],
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Atualizar créditos localmente
      setState(() {
        _availableCredits = _availableCredits - 1;
        _processingCorrection = false;
      });

      // Sucesso - navegar para resultados
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 16),
                Text('Crédito consumido com sucesso!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Navegar para a tela de resultados
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResultadoScreen(
              nomeAluno: widget.nomeAluno,
              notaFinal: widget.notaFinal,
              respostasAluno: widget.respostasAluno,
              gabarito: widget.gabarito,
              tipoProva: widget.tipoProva,
              pontuacaoTotal: widget.pontuacaoTotal,
              alunoId: widget.alunoId,
              simuladoId: widget.simuladoId,
              turmaId: widget.turmaId,
              nomeTurma: widget.nomeTurma,
              nomeSimulado: widget.nomeSimulado,
            ),
          ),
        );
      }
    } catch (e) {
      // Fechar loading se ainda estiver aberto
      if (mounted) {
        Navigator.pop(context);

        setState(() {
          _processingCorrection = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 16),
                Expanded(child: Text('Erro inesperado: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      developer.log('💳 Erro ao processar correção: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calcular estatísticas
    final int totalQuestoes = widget.gabarito.length;
    final int questoesAcertadas = widget.gabarito.keys
        .where((questao) =>
            widget.respostasAluno[questao] == widget.gabarito[questao])
        .length;

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: const Text(
          'Visualização da Correção',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Mostrar créditos na AppBar
          if (_hasCheckedCredits && !_checkingCredits)
            Container(
              margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _availableCredits > 0
                    ? success.withOpacity(0.2)
                    : danger.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _availableCredits > 0 ? success : danger,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    size: 16,
                    color: _availableCredits > 0 ? success : danger,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_availableCredits',
                    style: TextStyle(
                      color: _availableCredits > 0 ? success : danger,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

          if (_checkingCredits)
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Camada de fundo escura
          Container(
            color: bgDark,
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
                      color: surfaceDark.withOpacity(0.9),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            Text(
                              widget.nomeAluno,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (widget.nomeTurma != null &&
                                widget.nomeTurma!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Turma: ${widget.nomeTurma}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                            if (widget.nomeSimulado != null &&
                                widget.nomeSimulado!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Simulado: ${widget.nomeSimulado}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Versão da prova: ${widget.tipoProva}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Acertos: $questoesAcertadas/$totalQuestoes questões',
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
                          widget.imagemProcessada,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
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
                        onPressed: _processingCorrection
                            ? null
                            : () {
                                Navigator.pop(
                                    context); // Volta para a tela anterior
                              },
                        icon: Icon(
                          Icons.refresh,
                          color: _processingCorrection
                              ? Colors.grey
                              : Colors.white,
                        ),
                        label: Text(
                          'RECOMEÇAR',
                          style: TextStyle(
                            color: _processingCorrection
                                ? Colors.grey
                                : Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _processingCorrection ? Colors.grey : danger,
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
                        onPressed:
                            _processingCorrection ? null : _confirmarCorrecao,
                        icon: _processingCorrection
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                Icons.check,
                                color:
                                    (_checkingCredits || _processingCorrection)
                                        ? Colors.grey
                                        : Colors.white,
                              ),
                        label: Text(
                          _processingCorrection
                              ? 'PROCESSANDO...'
                              : 'CONFIRMAR',
                          style: TextStyle(
                            color: (_checkingCredits || _processingCorrection)
                                ? Colors.grey
                                : Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              (_checkingCredits || _processingCorrection)
                                  ? Colors.grey
                                  : (_availableCredits > 0
                                      ? success
                                      : success),
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
