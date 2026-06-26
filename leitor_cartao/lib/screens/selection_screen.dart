import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/models/class_model.dart';
import '../services/models/simulado_model.dart';
import '../widgets/custom_app_bar.dart';
import 'cartao_processing_screen.dart';
import 'login_screen.dart';
import 'quick_selection_screen.dart';
import 'shared_data.dart';

class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});

  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  final ApiService _apiService = ApiService();

  String _userName = 'Professor';
  int _creditos = 0;
  bool _carregandoCreditos = true;
  bool _carregandoQR = false;
  List<ClassModel> _turmas = [];

  static const Color primary     = Color(0xFF0DA6F2);
  static const Color primaryDark = Color(0xFF003D5C);
  static const Color bgLight     = Color(0xFFF8FAFC);
  static const Color textMain    = Color(0xFF003D5C);
  static const Color textSub     = Color(0xFF475569);
  static const Color borderLight = Color(0xFFDBE2E6);
  static const Color errorColor  = Color(0xFFDC2626);
  static const Color warnColor   = Color(0xFFEA580C);

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    await _carregarNome();
    _carregarCreditos();
    _carregarTurmas();
  }

  Future<void> _carregarNome() async {
    final prefs = await SharedPreferences.getInstance();
    final nome = prefs.getString('user_name');
    if (nome != null && mounted) setState(() => _userName = nome);
  }

  Future<void> _carregarCreditos() async {
    setState(() => _carregandoCreditos = true);
    try {
      final c = await _apiService.getUserCredits();
      if (mounted) setState(() {
        _creditos = c?['available_credits'] ?? 0;
        _carregandoCreditos = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregandoCreditos = false);
    }
  }

  Future<void> _carregarTurmas() async {
    try {
      final turmas = await _apiService.getClasses();
      if (mounted) setState(() => _turmas = turmas);
    } catch (_) {}
  }

  Future<void> _escanearQR() async {
    if (_creditos <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Sem créditos disponíveis. Adquira mais para continuar.'),
        backgroundColor: errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    final Map<String, dynamic>? qrData = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const _QRSimuladoScannerScreen()),
    );

    if (qrData == null || !mounted) return;

    final int? simuladoId = qrData['simuladoId'] as int?;
    if (simuladoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('QR sem dados do simulado. Regenere o PDF.'),
        backgroundColor: warnColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    setState(() => _carregandoQR = true);

    try {
      final simulado = await _apiService.getSimulado(simuladoId);
      if (!mounted) return;

      if (simulado == null) {
        setState(() => _carregandoQR = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Simulado #$simuladoId não encontrado'),
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        return;
      }

      final turmasFiltradas = _turmas
          .where((t) => simulado.classes.contains(t.id))
          .toList();

      final int? alunoId = qrData['alunoId'] as int?;
      final int? turmaId = qrData['turmaId'] as int?;

      // Auto-identificação: QR tem dados do aluno → pular seleção manual
      if (alunoId != null && turmaId != null && turmasFiltradas.isNotEmpty) {
        try {
          final students = await _apiService.getStudentsByClass(turmaId);
          final matching = students.where((s) => s.id == alunoId).toList();
          if (matching.isNotEmpty && mounted) {
            final student = matching.first;
            final turma = turmasFiltradas.firstWhere(
              (t) => t.id == turmaId,
              orElse: () => turmasFiltradas.first,
            );
            setState(() => _carregandoQR = false);
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CartaoProcessingScreen(
                  simulado: SimuladoData(
                    id: simulado.id,
                    nome: simulado.titulo,
                    numQuestoes: simulado.questoes.length,
                    dataCriacao: simulado.dataCriacao,
                    notaMaxima: simulado.notaMaxima,
                  ),
                  aluno: AlunoData(
                    id: student.id,
                    nome: student.name,
                    matricula: student.studentId?.toString() ?? 'N/A',
                    turmaNome: turma.name,
                  ),
                  tipoProva: qrData['tipo'] as int? ?? 1,
                  versionCode: qrData['versionCode'] as String?,
                  cartaoVersao: qrData['cartaoVersao'] as int?,
                ),
              ),
            );
            if (mounted) _carregarCreditos();
            return;
          }
        } catch (_) {
          // Falhou ao buscar aluno — cai no fluxo manual abaixo
        }
      }

      setState(() => _carregandoQR = false);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuickSelectionScreen(
            simulado: simulado,
            turmas: turmasFiltradas,
            tipoProva: qrData['tipo'] as int? ?? 1,
            versionCode: qrData['versionCode'] as String?,
            cartaoVersao: qrData['cartaoVersao'] as int?,
          ),
        ),
      );

      if (mounted) _carregarCreditos();
    } catch (e) {
      if (mounted) {
        setState(() => _carregandoQR = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_name');
    await prefs.remove('user_email');
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: CustomAppBar(onExit: _logout),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Saudação
              Text(
                'Bem-vindo(a), $_userName!',
                style: const TextStyle(
                  color: textMain,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Badge de créditos
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _creditos > 0
                      ? primary.withOpacity(0.07)
                      : errorColor.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _creditos > 0
                        ? primary.withOpacity(0.3)
                        : errorColor.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.bolt_rounded,
                        color: _creditos > 0 ? primary : errorColor, size: 20),
                    const SizedBox(width: 8),
                    _carregandoCreditos
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: primary),
                          )
                        : Text(
                            _creditos > 0
                                ? '$_creditos crédito${_creditos != 1 ? 's' : ''} disponíveis'
                                : 'Sem créditos — adquira mais para corrigir',
                            style: TextStyle(
                              color: _creditos > 0 ? primary : errorColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ],
                ),
              ),

              const Spacer(),

              // Ícone central
              Center(
                child: Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [primaryDark, primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withOpacity(0.3),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded,
                      color: Colors.white, size: 52),
                ),
              ),

              const SizedBox(height: 28),

              const Text(
                'Pronto para corrigir?',
                textAlign: TextAlign.center,
                style: TextStyle(color: textMain, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Escaneie o QR code no cartão-resposta para identificar o simulado e iniciar a correção.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSub, fontSize: 14, height: 1.5),
              ),

              const Spacer(),

              // Botão principal
              SizedBox(
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _carregandoQR ? null : _escanearQR,
                  icon: _carregandoQR
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.qr_code_scanner_rounded, size: 24),
                  label: Text(
                    _carregandoQR ? 'Identificando simulado...' : 'Escanear QR do cartão',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: borderLight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Scanner de QR para identificar o simulado ───────────────────────────────

class _QRSimuladoScannerScreen extends StatefulWidget {
  const _QRSimuladoScannerScreen();

  @override
  State<_QRSimuladoScannerScreen> createState() =>
      _QRSimuladoScannerScreenState();
}

class _QRSimuladoScannerScreenState extends State<_QRSimuladoScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  static const Color primary = Color(0xFF0DA6F2);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null) continue;

      final simuladoMatch = RegExp(r'\|S:(\d+)').firstMatch(code);
      final tipoMatch    = RegExp(r'\|T:(\d+)|\bT:(\d+)').firstMatch(code);
      final versionMatch = RegExp(r'ID:([^\|]+)').firstMatch(code);
      final pontuacaoMatch = RegExp(r'\|P:([\d.]+)').firstMatch(code);
      final alunoMatch  = RegExp(r'\|A:(\d+)').firstMatch(code);
      final turmaMatch  = RegExp(r'\|C:(\d+)').firstMatch(code);
      // v3: versão do LAYOUT do cartão (V:3 = fiduciais ao redor da grade) e
      // nº de questões (Q:45) — definem o aspecto da moldura e o deskew do backend.
      final layoutMatch = RegExp(r'\bV:(\d+)\b').firstMatch(code);
      final numMatch    = RegExp(r'\bQ:(\d+)\b').firstMatch(code);

      if (simuladoMatch != null && tipoMatch != null) {
        _scanned = true;
        _controller.stop();
        final tipoStr = tipoMatch.group(1) ?? tipoMatch.group(2);
        Navigator.pop(context, {
          'simuladoId':    int.tryParse(simuladoMatch.group(1)!),
          'tipo':          int.tryParse(tipoStr ?? '1') ?? 1,
          'versionCode':   versionMatch?.group(1),
          'pontuacaoTotal': pontuacaoMatch != null
              ? double.tryParse(pontuacaoMatch.group(1)!)
              : null,
          'alunoId': alunoMatch != null ? int.tryParse(alunoMatch.group(1)!) : null,
          'turmaId': turmaMatch != null ? int.tryParse(turmaMatch.group(1)!) : null,
          'cartaoVersao':  layoutMatch != null ? int.tryParse(layoutMatch.group(1)!) : null,
          'numQuestoesQR': numMatch != null ? int.tryParse(numMatch.group(1)!) : null,
        });
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF1A1A2E), size: 20),
        ),
        title: const Text(
          'Escanear cartão-resposta',
          style: TextStyle(
              color: Color(0xFF1A1A2E),
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: primary, width: 3),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Column(
              children: [
                const Text(
                  'Aponte para o QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'No topo do cartão-resposta',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
