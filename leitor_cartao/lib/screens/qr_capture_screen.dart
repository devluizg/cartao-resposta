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

  QRScanResult({required this.tipo, this.versionCode});
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

      return QRScanResult(tipo: tipo, versionCode: versionCode);
    } catch (e) {
      return null;
    }
  }

  void _onQRViewCreated(QRViewController controller) {
    _controller = controller;

    controller.scannedDataStream.listen((scanData) {
      if (!_isScanning) return;

      final code = scanData.code;
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
        backgroundColor: Colors.black,
        title: const Text(
          'Passo 2: Ler QR Code',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        ),
        elevation: 0,
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

          // INSTRUÇÃO CENTRAL
          if (_scannedResult == null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.qr_code_2_rounded,
                    color: Color(0xFF0DA6F2),
                    size: 64,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Aponte para o QR code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No topo do cartão-resposta',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Simulado: ${widget.simulado.nome}\nAluno: ${widget.aluno.nome}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // SUCESSO: QR CODE DETECTADO
          if (_scannedResult != null)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.white, size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'QR Code Detectado!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tipo de Prova:',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'TIPO ${_scannedResult!.tipo}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (_scannedResult!.versionCode != null) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Versão:',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              _scannedResult!.versionCode!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Courier',
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Encaminhando para fotografia do cartão...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // BOTÃO: VOLTAR
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
