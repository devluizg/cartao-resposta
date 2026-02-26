// cartao_processing_screen.dart
// Tela 3: Fotografia do Cartão com Moldura Inteligente
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
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
        await _controller!.setFlashMode(FlashMode.off);
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
      final liveState = await ImageQualityAnalyzer.analyzeLiveFrameFast(
        lumaBytes,
        frame.width,
        frame.height,
      );

      if (mounted) {
        setState(() {
          _liveQuality = liveState;
          _liveTip =
              ImageQualityAnalyzer.getTipForLiveQualityState(liveState);
        });
      }
    } catch (e) {
      print('❌ Erro ao analisar frame: $e');
    } finally {
      _isAnalyzingLive = false;
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
      _liveQuality == LiveQualityState.excellent ||
      _liveQuality == LiveQualityState.good;

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

  @override
  Widget build(BuildContext context) {
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

            // MOLDURA INTELIGENTE (6 indicadores)
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: FrameGuidePainter(
                frameColor: _frameColor,
                alignmentState: _frameAlignment,
                skewAngle: _skewAngle,
                showAdvancedGuides: true,
              ),
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

            // BOTÃO DE CAPTURA
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
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
                        border: Border.all(color: _frameColor, width: 4),
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
                ],
              ),
            ),

            // STATUS BADGE (TOPO)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _frameColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _frameColor.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isReadyToCapture
                          ? Icons.check_circle
                          : Icons.schedule,
                      color: _frameColor,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isReadyToCapture ? 'PRONTO' : 'ANALISANDO',
                      style: TextStyle(
                        color: _frameColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
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
}
