// cartao_processing_screen.dart
// Tela 3: Fotografia do Cartão com Moldura Inteligente + Flash + Captura Estável
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../services/image_quality_analyzer.dart';
import '../services/frame_alignment_analyzer.dart';
import '../widgets/frame_guide_painter.dart';
import 'simulado_selection_screen.dart';
import 'cartao_preview_screen.dart';
import 'capture_tips_screen.dart';

/// Tela 3: Fotografia do Cartão com Moldura Inteligente
class CartaoProcessingScreen extends StatefulWidget {
  final SimuladoData simulado;
  final AlunoData aluno;
  final int tipoProva;
  final String? versionCode;

  const CartaoProcessingScreen({
    super.key,
    required this.simulado,
    required this.aluno,
    required this.tipoProva,
    this.versionCode,
  });

  @override
  State<CartaoProcessingScreen> createState() => _CartaoProcessingScreenState();
}

class _CartaoProcessingScreenState extends State<CartaoProcessingScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _hasError = false;
  String _errorMessage = '';

  // Estados para feedback ao vivo
  LiveQualityState _liveQuality = LiveQualityState.analyzing;
  String _liveTip = 'Encaixe o cartão na moldura';
  bool _isAnalyzingLive = false;

  // Estados para alinhamento
  FrameAlignmentState _frameAlignment = FrameAlignmentState.analyzing;
  double _skewAngle = 0.0;

  // ✨ NOVO: Flash
  FlashMode _currentFlashMode = FlashMode.off;

  // ✨ NOVO: Captura estabilizada
  int _stableFrameCount = 0;
  static const int _requiredStableFrames = 8; // ~2s com análise a cada ~250ms
  bool _isStabilized = false;

  // ✨ NOVO: Controle de dicas
  bool _showTips = true;

  // ✨ NOVO: Sugestão de flash mostrada
  bool _flashSuggestionShown = false;
  int _badFrameCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.stopImageStream().catchError((_) {});
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
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

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      if (_controller!.value.isInitialized) {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setFlashMode(_currentFlashMode);
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

  Future<void> _onFrameReceived(CameraImage frame) async {
    if (_isAnalyzingLive || _isCapturing) return;

    _isAnalyzingLive = true;

    try {
      final lumaBytes = frame.planes[0].bytes;
      final width = frame.width;
      final height = frame.height;

      // Executar análise rápida em isolate para não travar a UI
      final liveState = await compute(
        _analyzeLiveFrameInIsolate,
        _FrameAnalysisData(lumaBytes, width, height),
      );

      if (mounted) {
        setState(() {
          _liveQuality = liveState;
          _liveTip =
              ImageQualityAnalyzer.getTipForLiveQualityState(liveState);

          // ✨ NOVO: Contar frames estáveis consecutivos
          if (liveState == LiveQualityState.excellent ||
              liveState == LiveQualityState.good) {
            _stableFrameCount++;
            if (_stableFrameCount >= _requiredStableFrames) {
              _isStabilized = true;
            }
          } else {
            _stableFrameCount = 0;
            _isStabilized = false;
          }

          // ✨ NOVO: Sugerir flash se muitos frames ruins
          if (liveState == LiveQualityState.bad) {
            _badFrameCount++;
            if (_badFrameCount >= 10 && !_flashSuggestionShown && _currentFlashMode == FlashMode.off) {
              _flashSuggestionShown = true;
              _suggestFlash();
            }
          } else {
            _badFrameCount = 0;
          }
        });
      }
    } catch (e) {
      print('❌ Erro ao analisar frame: $e');
    } finally {
      _isAnalyzingLive = false;
    }
  }

  /// Função estática para rodar em isolate
  static Future<LiveQualityState> _analyzeLiveFrameInIsolate(
    _FrameAnalysisData data,
  ) async {
    return ImageQualityAnalyzer.analyzeLiveFrameFast(
      data.lumaBytes,
      data.width,
      data.height,
    );
  }

  /// ✨ NOVO: Sugerir ativação do flash ao usuário
  void _suggestFlash() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.flash_on_rounded, color: Colors.yellow, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ambiente escuro detectado! Ative o flash para melhor leitura.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'ATIVAR',
          textColor: Colors.yellow,
          onPressed: () => _setFlashMode(FlashMode.torch),
        ),
      ),
    );
  }

  /// ✨ NOVO: Alternar modo de flash (OFF → TORCH → AUTO → OFF)
  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    FlashMode nextMode;
    switch (_currentFlashMode) {
      case FlashMode.off:
        nextMode = FlashMode.torch;
        break;
      case FlashMode.torch:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.off;
        break;
      default:
        nextMode = FlashMode.off;
    }

    await _setFlashMode(nextMode);
  }

  Future<void> _setFlashMode(FlashMode mode) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    await _controller!.setFlashMode(mode);
    setState(() {
      _currentFlashMode = mode;
      _badFrameCount = 0;
    });
  }

  /// Obter ícone baseado no modo de flash
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

  /// Obter label do flash
  String _getFlashLabel() {
    switch (_currentFlashMode) {
      case FlashMode.off:
        return 'OFF';
      case FlashMode.torch:
        return 'ON';
      case FlashMode.auto:
        return 'AUTO';
      default:
        return 'OFF';
    }
  }

  Color get _frameColor {
    switch (_liveQuality) {
      case LiveQualityState.analyzing:
        return const Color(0xFFF59E0B);
      case LiveQualityState.excellent:
        return const Color(0xFF22C55E);
      case LiveQualityState.good:
        return const Color(0xFF22C55E);
      case LiveQualityState.warning:
        return const Color(0xFFF97316);
      case LiveQualityState.bad:
        return const Color(0xFFEF4444);
    }
  }

  bool get _isReadyToCapture =>
      _isStabilized &&
      (_liveQuality == LiveQualityState.excellent ||
          _liveQuality == LiveQualityState.good);

  Future<void> _capturarFoto() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      await _controller!.stopImageStream().catchError((_) {});

      final XFile foto = await _controller!.takePicture();

      final dir = await getTemporaryDirectory();
      final String novoPath = path.join(
        dir.path,
        'cartao_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final File arquivoFinal = await File(foto.path).copy(novoPath);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CartaoPreviewScreen(
              imageFile: arquivoFinal,
              simulado: widget.simulado,
              aluno: widget.aluno,
              tipoProva: widget.tipoProva,
              versionCode: widget.versionCode,
            ),
          ),
        );
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

  /// ✨ NOVO: Callback quando dicas são fechadas → iniciar câmera
  void _onTipsClosed() {
    setState(() {
      _showTips = false;
    });
    _initCamera();
  }

  @override
  Widget build(BuildContext context) {
    // ✨ NOVO: Mostrar dicas primeiro
    if (_showTips) {
      return CaptureTipsScreen(onContinue: _onTipsClosed);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Passo 3: Fotografar Cartão',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        ),
        // ✨ NOVO: Ações no AppBar
        actions: [
          // Botão de flash
          _buildFlashButton(),
        ],
        elevation: 0,
      ),
      body: SafeArea(
        child: _hasError
            ? _buildErrorView()
            : !_isCameraReady
                ? _buildLoadingView()
                : _buildCameraWithGuide(),
      ),
    );
  }

  /// ✨ NOVO: Botão de flash no AppBar
  Widget _buildFlashButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: _toggleFlash,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _currentFlashMode == FlashMode.off
                ? Colors.white.withOpacity(0.1)
                : Colors.yellow.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: _currentFlashMode != FlashMode.off
                ? Border.all(color: Colors.yellow.shade300, width: 1)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getFlashIcon(),
                color: _currentFlashMode == FlashMode.off
                    ? Colors.white54
                    : Colors.yellow,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                _getFlashLabel(),
                style: TextStyle(
                  color: _currentFlashMode == FlashMode.off
                      ? Colors.white54
                      : Colors.yellow,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
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
            child: const Text('Tentar novamente',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraWithGuide() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cameraAspect = _controller!.value.aspectRatio;
        final displayAspect = 1 / cameraAspect;

        return Stack(
          fit: StackFit.expand,
          children: [
            // CÂMERA AO VIVO
            Center(
              child: AspectRatio(
                aspectRatio: displayAspect,
                child: CameraPreview(_controller!),
              ),
            ),

            // MOLDURA INTELIGENTE (com guias de canto)
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: FrameGuidePainter(
                frameColor: _frameColor,
                alignmentState: _frameAlignment,
                skewAngle: _skewAngle,
                showAdvancedGuides: true,
              ),
            ),

            // ✨ STATUS BADGE (TOPO) com indicador de estabilização
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: _buildStatusBadge(),
            ),

            // DICA DINÂMICA (BASE)
            Positioned(
              bottom: 80,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _liveQuality == LiveQualityState.bad
                          ? Icons.warning_rounded
                          : _liveQuality == LiveQualityState.warning
                              ? Icons.info_rounded
                              : Icons.wb_sunny_outlined,
                      color: _frameColor,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _liveTip,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // BOTÃO DE CAPTURA (com indicador de estabilização)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: _buildCaptureButton(),
            ),
          ],
        );
      },
    );
  }

  /// ✨ NOVO: Badge de status com barra de estabilização
  Widget _buildStatusBadge() {
    final badgeColor = _isReadyToCapture
        ? const Color(0xFF22C55E)
        : _liveQuality == LiveQualityState.bad
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);

    final progress = _isStabilized
        ? 1.0
        : (_stableFrameCount / _requiredStableFrames).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor.withOpacity(0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isReadyToCapture
                    ? Icons.check_circle_rounded
                    : _isStabilized
                        ? Icons.schedule_rounded
                        : Icons.pending_rounded,
                color: badgeColor,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                _isReadyToCapture
                    ? '✅ PRONTO — Pode fotografar!'
                    : _stableFrameCount > 0
                        ? 'Estabilizando... mantenha firme'
                        : _liveQuality == LiveQualityState.bad
                            ? '🔦 Ative o flash ou melhore a luz'
                            : 'Encaixe o cartão na moldura',
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          // Barra de progresso de estabilização
          if (!_isStabilized && _stableFrameCount > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ✨ NOVO: Botão de captura com estado visual
  Widget _buildCaptureButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _isCapturing ? null : _capturarFoto,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _isReadyToCapture
                    ? const Color(0xFF22C55E)
                    : Colors.white30,
                width: 4,
              ),
              color: _isCapturing
                  ? Colors.grey.shade700
                  : _isReadyToCapture
                      ? Colors.white.withOpacity(0.3)
                      : Colors.white.withOpacity(0.1),
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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isReadyToCapture
                            ? Colors.white
                            : Colors.white38,
                      ),
                      child: _isReadyToCapture
                          ? const Icon(
                              Icons.camera_alt_rounded,
                              color: Color(0xFF22C55E),
                              size: 28,
                            )
                          : const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.white54,
                              size: 24,
                            ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Dados para enviar ao isolate
class _FrameAnalysisData {
  final List<int> lumaBytes;
  final int width;
  final int height;
  _FrameAnalysisData(this.lumaBytes, this.width, this.height);
}
