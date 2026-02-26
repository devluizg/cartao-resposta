// camera_capture_screen.dart
// Tela de captura guiada com câmera AO VIVO e overlay de enquadramento
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../services/image_quality_analyzer.dart';
import '../services/frame_alignment_analyzer.dart';
import '../widgets/frame_guide_painter.dart';

/// Resultado da captura: imagem e metadados
class CaptureResult {
  final File imageFile;
  final int numColunas;
  final ImageQualityResult? qualityResult; // ✨ NOVO: Score de qualidade
  final String? versionCode; // ✨ NOVO: Código de versão do QR
  CaptureResult({
    required this.imageFile,
    required this.numColunas,
    this.qualityResult,
    this.versionCode,
  });
}

/// Tela de captura guiada do cartão-resposta com câmera ao vivo.
/// Mostra o preview da câmera traseira com uma moldura overlay proporcional
/// ao cartão A4, marcadores de canto e um botão de captura.
class CameraCaptureScreen extends StatefulWidget {
  final int numQuestoes;
  final int tipoProva;
  final String? versionCode; // ✨ NOVO: Código de versão do QR (opcional)

  const CameraCaptureScreen({
    super.key,
    required this.numQuestoes,
    required this.tipoProva,
    this.versionCode,
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
  ImageQualityResult? _qualityResult; // ✨ NOVO: Resultado de qualidade
  bool _isAnalyzingQuality = false; // ✨ NOVO: Flag de análise
  FlashMode _currentFlashMode = FlashMode.off; // ✨ NOVO: Rastrear modo de flash
  _ScreenState _screenState = _ScreenState.camera; // começa na câmera ao vivo

  // ✨ NOVO: Estados para feedback ao vivo
  LiveQualityState _liveQuality = LiveQualityState.analyzing;
  String _liveTip = 'Encaixe o cartão na moldura';
  bool _isAnalyzingLive = false;

  // ✨ NOVO: Estados para alinhamento de frame
  FrameAlignmentState _frameAlignment = FrameAlignmentState.analyzing;
  double _skewAngle = 0.0;
  bool _showAdvancedGuides = true; // Mostra guias avançadas

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.stopImageStream().catchError((_) {}); // ✨ NOVO: Parar stream
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

      // Configurar câmera: foco automático + flash desligado
      if (_controller!.value.isInitialized) {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setFlashMode(FlashMode.off);
        _currentFlashMode = FlashMode.off;

        // ✨ NOVO: Iniciar análise ao vivo de frames
        _startLiveQualityAnalysis();
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
      // ✨ NOVO: Parar análise ao vivo antes de capturar
      await _controller!.stopImageStream().catchError((_) {});

      // Capturar imagem
      final XFile foto = await _controller!.takePicture();

      // Mover para diretório temporário com nome descritivo
      final dir = await getTemporaryDirectory();
      final String novoPath = path.join(
        dir.path,
        'cartao_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final File arquivoFinal = await File(foto.path).copy(novoPath);

      // ✨ NOVO: Analisar qualidade da imagem
      setState(() => _isAnalyzingQuality = true);
      final qualityResult = await ImageQualityAnalyzer.analyzeImage(
        XFile(arquivoFinal.path),
      );

      if (mounted) {
        setState(() {
          _capturedImage = arquivoFinal;
          _qualityResult = qualityResult;
          _screenState = _ScreenState.preview;
          _isCapturing = false;
          _isAnalyzingQuality = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _isAnalyzingQuality = false;
          _hasError = true;
          _errorMessage = 'Erro ao capturar: $e';
        });
      }
    }
  }

  void _refazer() {
    setState(() {
      _capturedImage = null;
      _qualityResult = null; // ✨ NOVO: Limpar resultado
      _screenState = _ScreenState.camera;
      _liveQuality = LiveQualityState.analyzing; // ✨ NOVO: Reiniciar análise
      _liveTip = 'Encaixe o cartão na moldura';
    });
    // ✨ NOVO: Reiniciar análise ao vivo
    _startLiveQualityAnalysis();
  }

  /// ✨ NOVO: Iniciar análise ao vivo de qualidade dos frames
  void _startLiveQualityAnalysis() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      _controller!.startImageStream(_onFrameReceived).catchError((e) {
        print('❌ Erro ao iniciar stream: $e');
      });
    } catch (e) {
      print('❌ Erro ao iniciar stream: $e');
    }
  }

  /// ✨ NOVO: Callback para processar cada frame da câmera
  Future<void> _onFrameReceived(CameraImage frame) async {
    if (_isAnalyzingLive ||
        _screenState == _ScreenState.preview ||
        _isCapturing) {
      return;
    }

    _isAnalyzingLive = true;

    try {
      // Extrair canal Y (luminância) para análise rápida
      final lumaBytes = frame.planes[0].bytes;
      final width = frame.width;
      final height = frame.height;

      // Executar análise rápida em isolate
      final liveState = await compute(
        _analyzeLiveFrameInIsolate,
        _FrameAnalysisData(lumaBytes, width, height),
      );

      if (mounted) {
        setState(() {
          _liveQuality = liveState;
          _liveTip = ImageQualityAnalyzer.getTipForLiveQualityState(liveState);
        });
      }
    } catch (e) {
      print('❌ Erro ao analisar frame: $e');
    } finally {
      _isAnalyzingLive = false;
    }
  }

  /// ✨ NOVO: Função estática para rodar em isolate
  static Future<LiveQualityState> _analyzeLiveFrameInIsolate(
    _FrameAnalysisData data,
  ) async {
    return ImageQualityAnalyzer.analyzeLiveFrameFast(
      data.lumaBytes,
      data.width,
      data.height,
    );
  }

  /// ✨ NOVO: Alternar modo de flash (OFF → TORCH → AUTO → OFF)
  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final nextMode = _getNextFlashMode(_currentFlashMode);
    await _controller!.setFlashMode(nextMode);

    setState(() {
      _currentFlashMode = nextMode;
    });
  }

  /// ✨ NOVO: Determinar próximo modo de flash
  FlashMode _getNextFlashMode(FlashMode current) {
    switch (current) {
      case FlashMode.off:
        return FlashMode.torch; // Acender contínuo
      case FlashMode.torch:
        return FlashMode.auto; // Automático
      case FlashMode.auto:
        return FlashMode.off; // Desligar
      default:
        return FlashMode.off;
    }
  }

  /// ✨ NOVO: Obter ícone baseado no modo de flash
  IconData _getFlashIcon() {
    switch (_currentFlashMode) {
      case FlashMode.off:
        return Icons.flash_off_rounded;
      case FlashMode.torch:
        return Icons.flash_on_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      default:
        return Icons.flash_off_rounded;
    }
  }

  /// ✨ NOVO: Obter descrição do modo de flash
  String _getFlashLabel() {
    switch (_currentFlashMode) {
      case FlashMode.off:
        return 'Flash OFF';
      case FlashMode.torch:
        return 'Flash ON';
      case FlashMode.auto:
        return 'Flash AUTO';
      default:
        return 'Flash OFF';
    }
  }

  void _confirmarImagem() {
    if (_capturedImage == null) return;

    // ✨ NOVO: Bloquear se qualidade < 60
    if (_qualityResult != null && !_qualityResult!.isAcceptable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_qualityResult!.recommendation),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      CaptureResult(
        imageFile: _capturedImage!,
        numColunas: _numColunas,
        qualityResult: _qualityResult, // ✨ NOVO: Passar resultado
        versionCode: widget.versionCode, // ✨ NOVO: Passar version code do QR
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
                  'Enquadre os quadrados pretos de cada coluna',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
              ],
            ),
          ),
          // Badge com info (mostra se foi lido do QR)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: widget.versionCode != null
                  ? const Color(0xFF22C55E).withOpacity(0.2)
                  : const Color(0xFF0DA6F2).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.versionCode != null)
                  const Icon(Icons.qr_code_2, size: 12, color: Color(0xFF22C55E))
                else
                  const SizedBox.shrink(),
                if (widget.versionCode != null) const SizedBox(width: 4) else const SizedBox.shrink(),
                Text(
                  '${widget.numQuestoes}Q · ${_numColunas}Col${widget.versionCode != null ? ' · QR ✓' : ''}',
                  style: TextStyle(
                    color: widget.versionCode != null
                        ? const Color(0xFF22C55E)
                        : const Color(0xFF0DA6F2),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
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

            // ── MOLDURA DO CARTÃO (borda + marcadores + guias avançadas) ──
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: FrameGuidePainter(
                frameColor: _frameColor,
                alignmentState: _frameAlignment,
                skewAngle: _skewAngle,
                showAdvancedGuides: _showAdvancedGuides,
              ),
            ),

            // ── DICA de enquadramento (dinâmica) com alinhamento ──
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        _frameAlignment == FrameAlignmentState.badAngle ||
                                _frameAlignment == FrameAlignmentState.warningAngle
                            ? Icons.straighten_rounded
                            : _liveQuality == LiveQualityState.bad
                                ? Icons.warning_rounded
                                : _liveQuality == LiveQualityState.warning
                                    ? Icons.info_rounded
                                    : Icons.wb_sunny_outlined,
                        key: ValueKey(
                            '${_liveQuality}_${_frameAlignment}'),
                        color: _frameColor,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                        child: Text(
                          _liveTipWithAlignment, // ✨ Usar dica com alinhamento
                          style: const TextStyle(fontSize: 11),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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

  /// ✨ NOVO: Obter cor dinâmica baseada na qualidade ao vivo
  Color get _frameColor {
    switch (_liveQuality) {
      case LiveQualityState.analyzing:
        return const Color(0xFFF59E0B); // Amarelo
      case LiveQualityState.excellent:
        return const Color(0xFF22C55E); // Verde
      case LiveQualityState.good:
        return const Color(0xFF22C55E); // Verde
      case LiveQualityState.warning:
        return const Color(0xFFF97316); // Laranja
      case LiveQualityState.bad:
        return const Color(0xFFEF4444); // Vermelho
    }
  }

  /// ✨ NOVO: Gerar dica com informações de alinhamento
  String get _liveTipWithAlignment {
    // Se moldura está inclinada, priorizar feedback de alinhamento
    if (_frameAlignment == FrameAlignmentState.badAngle) {
      return '❌ Ângulo ${_skewAngle.toStringAsFixed(1)}° • Deixe reto';
    }
    if (_frameAlignment == FrameAlignmentState.warningAngle) {
      return '⚠️ Inclinado ${_skewAngle.toStringAsFixed(1)}° • Corrija';
    }
    // Caso contrário, usar feedback de qualidade
    return _liveTip;
  }

  Widget _positionedSquare(
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
          shape: BoxShape.rectangle, // Mudança: de circle para rectangle
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
          // ✨ BOTÃO DE FLASH (com ícone dinâmico e tooltip)
          Tooltip(
            message: _getFlashLabel(),
            child: _buildFlashButton(),
          ),

          const SizedBox(width: 32),

          // ── BOTÃO DE CAPTURA (grande, circular) ──
          GestureDetector(
            onTap: _isCapturing ? null : _capturarFoto,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _frameColor, width: 4), // ✨ NOVO: Cor dinâmica
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

  /// ✨ NOVO: Botão de flash melhorado com feedback visual
  Widget _buildFlashButton() {
    return GestureDetector(
      onTap: _toggleFlash,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _currentFlashMode == FlashMode.off
              ? Colors.white.withOpacity(0.12)
              : Colors.yellow.withOpacity(0.25),
          border: _currentFlashMode != FlashMode.off
              ? Border.all(color: Colors.yellow.shade300, width: 1.5)
              : null,
        ),
        child: Icon(
          _getFlashIcon(),
          color: _currentFlashMode == FlashMode.off
              ? Colors.white70
              : Colors.yellow.shade300,
          size: 22,
        ),
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

              // ✨ NOVO: Banner de qualidade ou confirmação
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: _buildQualityBanner(),
              ),
            ],
          ),
        ),

        // ✨ NOVO: Card de análise de qualidade detalhada
        if (_qualityResult != null) _buildQualityDetailsCard(),

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
                  onPressed: _isAnalyzingQuality ? null : _confirmarImagem,
                  icon: _isAnalyzingQuality
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _qualityResult?.isAcceptable ?? false
                                  ? Colors.white
                                  : Colors.red,
                            ),
                          ),
                        )
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 18),
                  label: Text(
                    _isAnalyzingQuality
                        ? 'ANALISANDO...'
                        : (_qualityResult?.isAcceptable ?? false)
                            ? 'USAR ESTA FOTO'
                            : 'QUALIDADE BAIXA',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_qualityResult?.isAcceptable ?? false)
                        ? const Color(0xFF16A34A)
                        : Colors.grey.shade700,
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

  /// ✨ NOVO: Banner que muda cor baseado na qualidade
  Widget _buildQualityBanner() {
    if (_isAnalyzingQuality) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Color(0xFFF59E0B)),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Analisando qualidade...',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    if (_qualityResult == null) {
      return Container(
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
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    final quality = _qualityResult!;
    final bgColor = quality.isExcellent
        ? Colors.green.shade900.withOpacity(0.7)
        : quality.isGood
            ? Colors.blue.shade900.withOpacity(0.7)
            : Colors.orange.shade900.withOpacity(0.7);

    final borderColor = quality.isExcellent
        ? const Color(0xFF22C55E)
        : quality.isGood
            ? const Color(0xFF0DA6F2)
            : const Color(0xFFF59E0B);

    final icon = quality.isExcellent
        ? Icons.check_circle
        : quality.isGood
            ? Icons.info
            : Icons.warning_amber_rounded;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor.withOpacity(0.8)),
      ),
      child: Row(
        children: [
          Icon(icon, color: borderColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Qualidade: ${quality.overallScore.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: borderColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  quality.recommendation,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ NOVO: Card com detalhes técnicos de qualidade
  Widget _buildQualityDetailsCard() {
    if (_qualityResult == null) return const SizedBox.shrink();

    final q = _qualityResult!;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          // Grid 2x3 de métricas
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _buildQualityMetric('☀️ Brilho', q.brightness.toStringAsFixed(0),
                  q.isBrightnessBad),
              _buildQualityMetric('📊 Contraste', q.contrast.toStringAsFixed(0),
                  q.isContrastBad),
              _buildQualityMetric('🎯 Nitidez',
                  '${(q.sharpness * 100).toStringAsFixed(0)}%', q.isSharpnessBad),
              _buildQualityMetric('💡 Iluminação',
                  '${(q.illuminationUniformity * 100).toStringAsFixed(0)}%',
                  q.isIlluminationBad),
              _buildQualityMetric('📐 Cantos',
                  '${(q.cornerVisibility * 100).toStringAsFixed(0)}%',
                  q.isCornersNotVisible),
              _buildQualityMetric('⭐ Score', '${q.overallScore.toStringAsFixed(0)}%',
                  !q.isAcceptable),
            ],
          ),
        ],
      ),
    );
  }

  /// ✨ NOVO: Widget para uma métrica individual
  Widget _buildQualityMetric(String label, String value, bool isBad) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isBad
            ? Colors.red.shade900.withOpacity(0.3)
            : Colors.green.shade900.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isBad
              ? Colors.red.shade400.withOpacity(0.5)
              : Colors.green.shade400.withOpacity(0.5),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white60),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isBad ? Colors.redAccent : Colors.greenAccent,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS, CLASSES E PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

/// ✨ NOVO: Classe para passar dados ao isolate
class _FrameAnalysisData {
  final List<int> lumaBytes;
  final int width;
  final int height;

  _FrameAnalysisData(this.lumaBytes, this.width, this.height);
}

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
