// qr_capture_screen.dart
// Tela 2: Leitura de QR Code apenas
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'simulado_selection_screen.dart';
import 'cartao_processing_screen.dart';

class QRScanResult {
  final int tipo;
  final String? versionCode;
  final int? simuladoId;
  final double? pontuacaoTotal;
  final int? alunoId;
  final int? turmaId;

  QRScanResult({
    required this.tipo,
    this.versionCode,
    this.simuladoId,
    this.pontuacaoTotal,
    this.alunoId,
    this.turmaId,
  });
}

/// Tela 2: Leitura de QR Code (somente scanner)
class QRCaptureScreen extends StatefulWidget {
  final SimuladoData simulado;
  final AlunoData aluno;

  const QRCaptureScreen({
    super.key,
    required this.simulado,
    required this.aluno,
  });

  @override
  State<QRCaptureScreen> createState() => _QRCaptureScreenState();
}

class _QRCaptureScreenState extends State<QRCaptureScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isScanning = true;
  String? _lastScannedCode;
  QRScanResult? _scannedResult;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  QRScanResult? _parseQRCode(String rawData) {
    try {
      final tipoMatch = RegExp(r'\|T:(\d+)|\bT:(\d+)').firstMatch(rawData);
      if (tipoMatch == null) return null;

      final tipoStr = tipoMatch.group(1) ?? tipoMatch.group(2);
      final tipo = int.tryParse(tipoStr ?? '');
      if (tipo == null || tipo < 1) return null;

      final versionMatch = RegExp(r'ID:([^\|]+)').firstMatch(rawData);
      final versionCode = versionMatch?.group(1);

      final simuladoMatch = RegExp(r'\|S:(\d+)').firstMatch(rawData);
      final simuladoId = simuladoMatch != null ? int.tryParse(simuladoMatch.group(1)!) : null;

      final pontuacaoMatch = RegExp(r'\|P:([\d.]+)').firstMatch(rawData);
      final pontuacaoTotal = pontuacaoMatch != null ? double.tryParse(pontuacaoMatch.group(1)!) : null;

      final alunoMatch = RegExp(r'\|A:(\d+)').firstMatch(rawData);
      final alunoId = alunoMatch != null ? int.tryParse(alunoMatch.group(1)!) : null;

      final turmaMatch = RegExp(r'\|C:(\d+)').firstMatch(rawData);
      final turmaId = turmaMatch != null ? int.tryParse(turmaMatch.group(1)!) : null;

      return QRScanResult(
        tipo: tipo,
        versionCode: versionCode,
        simuladoId: simuladoId,
        pontuacaoTotal: pontuacaoTotal,
        alunoId: alunoId,
        turmaId: turmaId,
      );
    } catch (e) {
      return null;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null) continue;

      final result = _parseQRCode(code);
      if (result != null && result.tipo >= 1 && result.tipo <= 5) {
        _isScanning = false;
        _controller.stop();

        setState(() {
          _lastScannedCode = code;
          _scannedResult = result;
        });

        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _avancar();
        });
        break;
      }
    }
  }

  void _avancar() {
    if (_scannedResult == null) return;

    // Se o QR identifica um aluno e ele não bate com o aluno selecionado, avisa
    final qrAlunoId = _scannedResult!.alunoId;
    if (qrAlunoId != null && qrAlunoId != widget.aluno.id) {
      _isScanning = false;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Cartão não corresponde ao aluno'),
          content: Text(
            'Este cartão pertence ao aluno #$qrAlunoId, '
            'mas o aluno selecionado é ${widget.aluno.nome} (#${widget.aluno.id}).\n\n'
            'Deseja continuar mesmo assim?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _isScanning = true;
                  _scannedResult = null;
                  _lastScannedCode = null;
                });
                _controller.start();
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navegarParaProcessamento();
              },
              child: const Text('Continuar assim mesmo'),
            ),
          ],
        ),
      );
      return;
    }

    _navegarParaProcessamento();
  }

  void _navegarParaProcessamento() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CartaoProcessingScreen(
          simulado: widget.simulado,
          aluno: widget.aluno,
          tipoProva: _scannedResult!.tipo,
          versionCode: _scannedResult!.versionCode,
        ),
      ),
    );
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A2E), size: 20),
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
      body: Stack(
        children: [
          // QR SCANNER
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // OVERLAY: moldura de escaneamento
          Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF0DA6F2), width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // INSTRUÇÃO CENTRAL
          if (_scannedResult == null)
            Positioned(
              bottom: 40 + MediaQuery.of(context).padding.bottom,
              left: 20,
              right: 20,
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
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      '${widget.simulado.nome}  ·  ${widget.aluno.nome}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

          // SUCESSO: QR CODE DETECTADO
          if (_scannedResult != null)
            Positioned(
              bottom: 24 + MediaQuery.of(context).padding.bottom,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 22),
                        SizedBox(width: 10),
                        Text(
                          'QR Code Detectado!',
                          style: TextStyle(
                            color: Color(0xFF1A1A2E),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Tipo de Prova', style: TextStyle(color: Color(0xFF6B7280), fontSize: 10, fontWeight: FontWeight.w600)),
                              Text(
                                'TIPO ${_scannedResult!.tipo}',
                                style: const TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          if (_scannedResult!.versionCode != null) ...[
                            const SizedBox(width: 24),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Versão', style: TextStyle(color: Color(0xFF6B7280), fontSize: 10, fontWeight: FontWeight.w600)),
                                Text(
                                  _scannedResult!.versionCode!,
                                  style: const TextStyle(color: Color(0xFF1A1A2E), fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0DA6F2))),
                        SizedBox(width: 8),
                        Text(
                          'Encaminhando para fotografia...',
                          style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                        ),
                      ],
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
