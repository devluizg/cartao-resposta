// qr_capture_screen.dart
// Tela 2: Leitura de QR Code apenas
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'dart:io';
import 'simulado_selection_screen.dart';
import 'cartao_processing_screen.dart';

class QRScanResult {
  final int tipo;
  final String? versionCode;
  final int? simuladoId;
  final double? pontuacaoTotal;

  QRScanResult({required this.tipo, this.versionCode, this.simuladoId, this.pontuacaoTotal});
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
  QRViewController? _controller;
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  bool _isScanning = true;
  String? _lastScannedCode;
  QRScanResult? _scannedResult;

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      _controller?.pauseCamera();
    }
    _controller?.resumeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  QRScanResult? _parseQRCode(String rawData) {
    try {
      // Procura por T:X no QR code
      final tipoMatch = RegExp(r'\|T:(\d+)|\bT:(\d+)').firstMatch(rawData);
      if (tipoMatch == null) return null;

      final tipoStr = tipoMatch.group(1) ?? tipoMatch.group(2);
      final tipo = int.tryParse(tipoStr ?? '');
      if (tipo == null || tipo < 1) return null;

      // Extrai versão (opcional)
      final versionMatch = RegExp(r'ID:([^\|]+)').firstMatch(rawData);
      final versionCode = versionMatch?.group(1);

      // Extrai simulado ID (opcional)
      final simuladoMatch = RegExp(r'\|S:(\d+)').firstMatch(rawData);
      final simuladoId = simuladoMatch != null ? int.tryParse(simuladoMatch.group(1)!) : null;

      // Extrai pontuação total (opcional)
      final pontuacaoMatch = RegExp(r'\|P:([\d.]+)').firstMatch(rawData);
      final pontuacaoTotal = pontuacaoMatch != null ? double.tryParse(pontuacaoMatch.group(1)!) : null;

      return QRScanResult(tipo: tipo, versionCode: versionCode, simuladoId: simuladoId, pontuacaoTotal: pontuacaoTotal);
    } catch (e) {
      return null;
    }
  }

  void _onQRViewCreated(QRViewController controller) {
    _controller = controller;

    controller.scannedDataStream.listen((scanData) {
      if (!_isScanning) return;

      final code = scanData.code;
      if (code == null) return;
      final result = _parseQRCode(code);

      if (result != null && result.tipo >= 1 && result.tipo <= 5) {
        _isScanning = false;
        _controller?.pauseCamera();

        setState(() {
          _lastScannedCode = code;
          _scannedResult = result;
        });

        // Avança automaticamente após 1s
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _avancar();
          }
        });
      }
    });
  }

  void _avancar() {
    if (_scannedResult == null) return;

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
          QRView(
            key: _qrKey,
            onQRViewCreated: _onQRViewCreated,
            overlay: QrScannerOverlayShape(
              borderColor: const Color(0xFF0DA6F2),
              borderRadius: 10,
              borderLength: 30,
              borderWidth: 8,
              cutOutSize: 280,
            ),
          ),

          // INSTRUÇÃO CENTRAL (sobre câmera — mantém texto branco)
          if (_scannedResult == null)
            Positioned(
              bottom: 40,
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
              bottom: 24,
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
