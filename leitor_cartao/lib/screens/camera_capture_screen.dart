// camera_capture_screen.dart
// Tela de captura guiada com câmera AO VIVO e overlay de enquadramento
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Resultado da captura: imagem e metadados
class CaptureResult {
  final File imageFile;
  final int numColunas;
  CaptureResult({required this.imageFile, required this.numColunas});
}

/// Tela de captura guiada do cartão-resposta com câmera ao vivo.
/// Mostra o preview da câmera traseira com uma moldura overlay proporcional
/// ao cartão A4, marcadores de canto e um botão de captura.
class CameraCaptureScreen extends StatefulWidget {
  final int numQuestoes;
  final int tipoProva;

  const CameraCaptureScreen({
    super.key,
    required this.numQuestoes,
    required this.tipoProva,
  });

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _hasError = false;
  String _errorMessage = '';
  File? _capturedImage;
  _ScreenState _screenState = _ScreenState.camera; // começa na câmera ao vivo

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Gerenciar ciclo de vida da câmera
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  int get _numColunas {
    if (widget.numQuestoes <= 23) return 1;
    if (widget.numQuestoes <= 45) return 2;
    return 3;
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Nenhuma câmera encontrada';
        });
        return;
      }

      // Usar câmera traseira
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high, // 1280x720 — bom equilíbrio qualidade/performance
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      // Travar auto-focus contínuo para melhor qualidade
      if (_controller!.value.isInitialized) {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setFlashMode(FlashMode.off);
      }

      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _hasError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Erro ao iniciar câmera: $e';
        });
      }
    }
  }

  Future<void> _capturarFoto() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      // Capturar imagem
      final XFile foto = await _controller!.takePicture();

      // Mover para diretório temporário com nome descritivo
      final dir = await getTemporaryDirectory();
      final String novoPath = path.join(
        dir.path,
        'cartao_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final File arquivoFinal = await File(foto.path).copy(novoPath);

      if (mounted) {
        setState(() {
          _capturedImage = arquivoFinal;
          _screenState = _ScreenState.preview;
          _isCapturing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _hasError = true;
          _errorMessage = 'Erro ao capturar: $e';
        });
      }
    }
  }

  void _refazer() {
    setState(() {
      _capturedImage = null;
      _screenState = _ScreenState.camera;
    });
  }

  void _confirmarImagem() {
    if (_capturedImage == null) return;
    Navigator.pop(
      context,
      CaptureResult(
        imageFile: _capturedImage!,
        numColunas: _numColunas,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
        bottom: true,
        child: _screenState == _ScreenState.preview && _capturedImage != null
            ? _buildPreviewScreen()
            : _buildCameraScreen(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TELA DA CÂMERA AO VIVO
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCameraScreen() {
    return Column(
      children: [
        // Header compacto
        _buildHeader(),

        // Área da câmera com overlay
        Expanded(
          child: _hasError
              ? _buildErrorView()
              : !_isCameraReady
                  ? _buildLoadingView()
                  : _buildCameraWithOverlay(),
        ),

        // Barra inferior com botão de captura
        _buildCaptureBar(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.black,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fotografar Cartão-Resposta',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Enquadre os 4 marcadores nos cantos',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
              ],
            ),
          ),
          // Badge com info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0DA6F2).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${widget.numQuestoes}Q · ${_numColunas}Col',
              style: const TextStyle(
                color: Color(0xFF0DA6F2),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF0DA6F2)),
          SizedBox(height: 16),
          Text(
            'Iniciando câmera...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(
            _errorMessage,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _hasError = false;
                _isCameraReady = false;
              });
              _initCamera();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0DA6F2),
            ),
            child:
                const Text('Tentar novamente', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraWithOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calcular tamanho do preview da câmera
        final double cameraAspect = _controller!.value.aspectRatio;
        // O CameraPreview mostra retrato mas reporta ratio invertido
        final double displayAspect = 1 / cameraAspect;

        return Stack(
          fit: StackFit.expand,
          children: [
            // ── CÂMERA AO VIVO ──
            Center(
              child: AspectRatio(
                aspectRatio: displayAspect,
                child: CameraPreview(_controller!),
              ),
            ),

            // ── OVERLAY ESCURO com recorte transparente ──
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _OverlayPainter(
                frameRect: _calcFrameRect(constraints),
              ),
            ),

            // ── MOLDURA DO CARTÃO (borda + marcadores) ──
            Positioned.fromRect(
              rect: _calcFrameRect(constraints),
              child: _buildFrameDecoration(),
            ),

            // ── DICA de enquadramento ──
            Positioned(
              bottom: 8,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wb_sunny_outlined,
                        color: Color(0xFFF59E0B), size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Boa iluminação • Sem sombras • Cartão reto',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Calcula o retângulo da moldura (proporção A4) centralizado na área disponível
  Rect _calcFrameRect(BoxConstraints constraints) {
    const double a4Ratio = 1.0 / 1.414; // largura/altura A4
    final double availW = constraints.maxWidth;
    final double availH = constraints.maxHeight;

    // Calcular maior moldura A4 que cabe na tela com margem
    const double margin = 24.0;
    double frameW = availW - margin * 2;
    double frameH = frameW / a4Ratio;

    if (frameH > availH - margin * 2) {
      frameH = availH - margin * 2;
      frameW = frameH * a4Ratio;
    }

    final double left = (availW - frameW) / 2;
    final double top = (availH - frameH) / 2;

    return Rect.fromLTWH(left, top, frameW, frameH);
  }

  Widget _buildFrameDecoration() {
    const Color frameColor = Color(0xFFF59E0B); // Amarelo guia

    return IgnorePointer(
      child: Stack(
        children: [
          // Borda principal
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: frameColor, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // Cantos em L (guias visuais)
          ..._buildCorners(frameColor),

          // Marcadores de canto (representam os círculos do cartão impresso)
          _positionedDot(8, 8, true, true, frameColor),
          _positionedDot(8, 8, true, false, frameColor),
          _positionedDot(8, 8, false, true, frameColor),
          _positionedDot(8, 8, false, false, frameColor),

          // Divisórias de coluna
          if (_numColunas >= 2)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      for (int i = 1; i < _numColunas; i++)
                        Positioned(
                          left: constraints.maxWidth * i / _numColunas,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 1,
                            color: frameColor.withOpacity(0.3),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

          // Label central
          Center(
            child: Text(
              'CARTÃO\nRESPOSTA',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: frameColor.withOpacity(0.25),
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _positionedDot(
      double margin, double size, bool isTop, bool isLeft, Color color) {
    return Positioned(
      top: isTop ? margin : null,
      bottom: !isTop ? margin : null,
      left: isLeft ? margin : null,
      right: !isLeft ? margin : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.5),
          border: Border.all(color: color, width: 1.5),
        ),
      ),
    );
  }

  List<Widget> _buildCorners(Color color) {
    const double len = 24;
    const double thick = 3;

    return [
      // Top-left
      Positioned(
          top: -1,
          left: -1,
          child: _cornerShape(color, len, thick, true, true)),
      // Top-right
      Positioned(
          top: -1,
          right: -1,
          child: _cornerShape(color, len, thick, true, false)),
      // Bottom-left
      Positioned(
          bottom: -1,
          left: -1,
          child: _cornerShape(color, len, thick, false, true)),
      // Bottom-right
      Positioned(
          bottom: -1,
          right: -1,
          child: _cornerShape(color, len, thick, false, false)),
    ];
  }

  Widget _cornerShape(
      Color color, double len, double thick, bool isTop, bool isLeft) {
    return SizedBox(
      width: len,
      height: len,
      child: CustomPaint(
        painter: _CornerPainter(
          color: color,
          thickness: thick,
          isTop: isTop,
          isLeft: isLeft,
        ),
      ),
    );
  }

  Widget _buildCaptureBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Botão de flash (opcional)
          _buildSmallButton(
            icon: Icons.flash_off,
            onTap: () async {
              if (_controller == null) return;
              final current = _controller!.value.flashMode;
              final next = current == FlashMode.off
                  ? FlashMode.torch
                  : FlashMode.off;
              await _controller!.setFlashMode(next);
              setState(() {});
            },
          ),

          const SizedBox(width: 32),

          // ── BOTÃO DE CAPTURA (grande, circular) ──
          GestureDetector(
            onTap: _isCapturing ? null : _capturarFoto,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                color: _isCapturing
                    ? Colors.grey.shade700
                    : Colors.white.withOpacity(0.2),
              ),
              child: _isCapturing
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
          ),

          const SizedBox(width: 32),

          // Botão de fechar / cancelar
          _buildSmallButton(
            icon: Icons.close,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallButton(
      {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.12),
        ),
        child: Icon(icon, color: Colors.white70, size: 22),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TELA DE PREVIEW (após captura)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPreviewScreen() {
    return Column(
      children: [
        _buildHeader(),

        // Imagem capturada
        Expanded(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.file(
                    _capturedImage!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              // Banner de confirmação
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF22C55E).withOpacity(0.5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: Color(0xFF22C55E), size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Verifique se os cantos e bolhas estão visíveis',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Botões: Refazer / Usar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          color: Colors.black,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _refazer,
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white70, size: 18),
                  label: const Text(
                    'REFAZER',
                    style: TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _confirmarImagem,
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
                  label: const Text(
                    'USAR ESTA FOTO',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS E PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

enum _ScreenState { camera, preview }

/// Pinta o overlay escuro semi-transparente com um buraco retangular transparente
class _OverlayPainter extends CustomPainter {
  final Rect frameRect;
  _OverlayPainter({required this.frameRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.55);

    // Desenhar overlay escuro com buraco
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final holePath = Path()
      ..addRRect(
          RRect.fromRectAndRadius(frameRect, const Radius.circular(4)));
    final overlayPath = Path()
      ..addRect(fullRect)
      ..addPath(holePath, Offset.zero);
    overlayPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(overlayPath, paint);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.frameRect != frameRect;
}

/// Pinta um canto em L
class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool isTop;
  final bool isLeft;

  _CornerPainter({
    required this.color,
    required this.thickness,
    required this.isTop,
    required this.isLeft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double x = isLeft ? 0 : size.width;
    final double y = isTop ? 0 : size.height;
    final double endX = isLeft ? size.width : 0;
    final double endY = isTop ? size.height : 0;

    canvas.drawLine(Offset(x, y), Offset(endX, y), paint); // horizontal
    canvas.drawLine(Offset(x, y), Offset(x, endY), paint); // vertical
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.color != color || old.isTop != isTop || old.isLeft != isLeft;
}
