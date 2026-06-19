# Graph Report - /home/luiz/cartao-resposta/leitor_cartao  (2026-04-17)

## Corpus Check
- Corpus is ~31,680 words - fits in a single context window. You may not need a graph.

## Summary
- 154 nodes · 172 edges · 29 communities detected
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 8 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_API Layer & Data Models|API Layer & Data Models]]
- [[_COMMUNITY_Windows Native Runner|Windows Native Runner]]
- [[_COMMUNITY_Screen Navigation & Auth|Screen Navigation & Auth]]
- [[_COMMUNITY_Card Capture & OMR Screens|Card Capture & OMR Screens]]
- [[_COMMUNITY_Linux Native Runner|Linux Native Runner]]
- [[_COMMUNITY_OMR Vision Pipeline|OMR Vision Pipeline]]
- [[_COMMUNITY_iOS App Delegate|iOS App Delegate]]
- [[_COMMUNITY_Windows Flutter Window|Windows Flutter Window]]
- [[_COMMUNITY_Test Runners|Test Runners]]
- [[_COMMUNITY_Plugin Registrants|Plugin Registrants]]
- [[_COMMUNITY_Credits & Purchases|Credits & Purchases]]
- [[_COMMUNITY_macOS Main Window|macOS Main Window]]
- [[_COMMUNITY_Windows Utilities|Windows Utilities]]
- [[_COMMUNITY_macOS Plugin Registrant|macOS Plugin Registrant]]
- [[_COMMUNITY_Windows Entry Point|Windows Entry Point]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]

## God Nodes (most connected - your core abstractions)
1. `ApiService` - 25 edges
2. `CartaoProcessingScreen (screen 3 - camera + guide)` - 7 edges
3. `Create()` - 6 edges
4. `Destroy()` - 6 edges
5. `SelectionScreen (main hub)` - 6 edges
6. `AppDelegate` - 5 edges
7. `MessageHandler()` - 5 edges
8. `QRCaptureScreen (screen 2 - manual flow)` - 5 edges
9. `SimuladoData (shared DTO)` - 5 edges
10. `AlunoData (shared DTO)` - 5 edges

## Surprising Connections (you probably didn't know these)
- `QrScanResult (data class)` --semantically_similar_to--> `QRScanResult (data class, full fields)`  [INFERRED] [semantically similar]
  lib/main.dart → lib/screens/qr_capture_screen.dart
- `AuthService` --semantically_similar_to--> `ApiService`  [INFERRED] [semantically similar]
  lib/services/auth_service.dart → lib/services/api_service.dart
- `ImageQualityAnalyzer` --conceptually_related_to--> `OMR Card Reading (Optical Mark Recognition)`  [INFERRED]
  lib/services/image_quality_analyzer.dart → lib/services/claude_vision_service.dart
- `FrameAlignmentAnalyzer` --conceptually_related_to--> `OMR Card Reading (Optical Mark Recognition)`  [INFERRED]
  lib/services/frame_alignment_analyzer.dart → lib/services/claude_vision_service.dart
- `CameraMask Widget` --conceptually_related_to--> `OMR Card Reading (Optical Mark Recognition)`  [INFERRED]
  lib/widgets/camera_mask.dart → lib/services/claude_vision_service.dart

## Hyperedges (group relationships)
- **New QR-first scan flow (SelectionScreen → QR Scanner → auto-identify or QuickSelection → CartaoProcessing)** — selection_SelectionScreen, selection_QRSimuladoScannerScreen, auto_identification_flow, quick_selection_QuickSelectionScreen, cartao_processing_CartaoProcessingScreen [EXTRACTED 0.98]
- **QR parse regex implementations (all parse S:, T:, A:, C:, P:, ID: fields)** — main_parseQrCodeCompleto, selection_qrParseLogic, qr_capture_parseQRCode, qr_format_fields [EXTRACTED 1.00]
- **SimuladoData + AlunoData propagated through all screens** — simulado_selection_SimuladoData, simulado_selection_AlunoData, qr_capture_QRCaptureScreen, quick_selection_QuickSelectionScreen, cartao_processing_CartaoProcessingScreen, cartao_preview_CartaoPreviewScreen, cartao_result_CartaoResultData [EXTRACTED 1.00]
- **Manual flow: SimuladoSelectionScreen → QRCaptureScreen → CartaoProcessingScreen** — simulado_selection_SimuladoSelectionScreen, qr_capture_QRCaptureScreen, cartao_processing_CartaoProcessingScreen [EXTRACTED 1.00]
- **Legacy TelaInicial flow (QrScanScreen → CameraCaptureScreen → CartaoRespostaPreviewScreen → ResultadoScreen)** — main_TelaInicial, main_QrScanScreen, camera_capture_CameraCaptureScreen, cartao_resposta_preview_CartaoRespostaPreviewScreen, resultado_ResultadoScreen [EXTRACTED 0.95]
- **OMR Card Reading Pipeline** — image_quality_analyzer_ImageQualityAnalyzer, frame_alignment_analyzer_FrameAlignmentAnalyzer, claude_vision_service_ClaudeVisionService, api_endpoint_processar_cartao_backend, concept_omr_reading [INFERRED 0.90]
- **ApiService consumes data models** — api_service_ApiService, simulado_model_SimuladoModel, student_model_StudentModel, class_model_ClassModel, resultado_model_ResultadoModel [EXTRACTED 1.00]
- **Credit Purchase Flow** — credit_manager_CreditManager, compras_service_ComprasService, external_google_play_iap, api_endpoint_comprar_creditos, produto_credito_ProdutoCredito [EXTRACTED 1.00]
- **Simulado Correction Submission Flow** — api_endpoint_corrigir, api_endpoint_resultados_submit, concept_versioncode, resultado_model_ResultadoModel [EXTRACTED 0.95]
- **StringDecoder used across all models** — utils_StringDecoder, simulado_model_SimuladoModel, student_model_StudentModel, class_model_ClassModel, resultado_model_ResultadoModel, questao_model_QuestaoModel [EXTRACTED 1.00]

## Communities

### Community 0 - "API Layer & Data Models"
Cohesion: 0.09
Nodes (30): GET /api/app-config/, GET /api/classes/{id}/simulados/, GET /api/classes/{id}/students/, GET /api/classes/, POST /api/consume_credit/, POST /api/simulados/{id}/corrigir/, GET /api/users/credits/history/, GET /api/credits/plans/ (+22 more)

### Community 1 - "Windows Native Runner"
Cohesion: 0.17
Nodes (16): Create(), Destroy(), EnableFullDpiSupportIfAvailable(), GetClientArea(), GetThisFromHandle(), GetWindowClass(), MessageHandler(), OnCreate() (+8 more)

### Community 2 - "Screen Navigation & Auth"
Cohesion: 0.13
Nodes (19): Auto-identification flow (QR has alunoId+turmaId), CameraCaptureScreen (legacy camera screen), CaptureResult (data class), CartaoRespostaPreviewScreen (legacy result preview), LoginScreen, LojaCreditosScreen, AuthenticationWrapper, CartaoRespostaApp (root widget) (+11 more)

### Community 3 - "Card Capture & OMR Screens"
Cohesion: 0.38
Nodes (10): CaptureTipsScreen, CartaoPreviewScreen (screen 4 - process + result), CartaoProcessingScreen (screen 3 - camera + guide), CartaoResultData (result DTO), CartaoResultScreen (screen 5 - result display), QRCaptureScreen (screen 2 - manual flow), QuickSelectionScreen (post-QR turma+aluno picker), AlunoData (shared DTO) (+2 more)

### Community 4 - "Linux Native Runner"
Cohesion: 0.22
Nodes (0): 

### Community 5 - "OMR Vision Pipeline"
Cohesion: 0.29
Nodes (8): POST /api/processar-imagem-cartao/ (Django backend OMR), ClaudeVisionService, OMR Card Reading (Optical Mark Recognition), Anthropic Claude API (api.anthropic.com/v1/messages), FrameAlignmentAnalyzer, ImageQualityAnalyzer, CameraMask Widget, FrameGuidePainter Widget

### Community 6 - "iOS App Delegate"
Cohesion: 0.33
Nodes (2): AppDelegate, FlutterAppDelegate

### Community 7 - "Windows Flutter Window"
Cohesion: 0.33
Nodes (1): FlutterWindow()

### Community 8 - "Test Runners"
Cohesion: 0.4
Nodes (2): RunnerTests, XCTestCase

### Community 9 - "Plugin Registrants"
Cohesion: 0.4
Nodes (2): GeneratedPluginRegistrant, -registerWithRegistry

### Community 10 - "Credits & Purchases"
Cohesion: 0.5
Nodes (5): POST /api/comprar_creditos/ (validate Google Play purchase), ComprasService, CreditManager, Google Play In-App Purchase, ProdutoCredito

### Community 11 - "macOS Main Window"
Cohesion: 0.5
Nodes (2): MainFlutterWindow, NSWindow

### Community 12 - "Windows Utilities"
Cohesion: 0.67
Nodes (2): GetCommandLineArguments(), Utf8FromUtf16()

### Community 13 - "macOS Plugin Registrant"
Cohesion: 1.0
Nodes (0): 

### Community 14 - "Windows Entry Point"
Cohesion: 1.0
Nodes (0): 

### Community 15 - "Community 15"
Cohesion: 1.0
Nodes (0): 

### Community 16 - "Community 16"
Cohesion: 1.0
Nodes (0): 

### Community 17 - "Community 17"
Cohesion: 1.0
Nodes (0): 

### Community 18 - "Community 18"
Cohesion: 1.0
Nodes (1): MainActivity

### Community 19 - "Community 19"
Cohesion: 1.0
Nodes (0): 

### Community 20 - "Community 20"
Cohesion: 1.0
Nodes (0): 

### Community 21 - "Community 21"
Cohesion: 1.0
Nodes (0): 

### Community 22 - "Community 22"
Cohesion: 1.0
Nodes (0): 

### Community 23 - "Community 23"
Cohesion: 1.0
Nodes (0): 

### Community 24 - "Community 24"
Cohesion: 1.0
Nodes (0): 

### Community 25 - "Community 25"
Cohesion: 1.0
Nodes (0): 

### Community 26 - "Community 26"
Cohesion: 1.0
Nodes (0): 

### Community 27 - "Community 27"
Cohesion: 1.0
Nodes (1): ImagensProcessadasScreen

### Community 28 - "Community 28"
Cohesion: 1.0
Nodes (1): CustomAppBar Widget

## Knowledge Gaps
- **27 isolated node(s):** `-registerWithRegistry`, `MainActivity`, `ImagensProcessadasScreen`, `CameraCaptureScreen (legacy camera screen)`, `CaptureResult (data class)` (+22 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `macOS Plugin Registrant`** (2 nodes): `RegisterGeneratedPlugins()`, `GeneratedPluginRegistrant.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Entry Point`** (2 nodes): `main.cpp`, `wWinMain()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 15`** (2 nodes): `RegisterPlugins()`, `generated_plugin_registrant.cc`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 16`** (2 nodes): `main.cc`, `main()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 17`** (2 nodes): `fl_register_plugins()`, `generated_plugin_registrant.cc`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 18`** (2 nodes): `MainActivity.kt`, `MainActivity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 19`** (1 nodes): `Runner-Bridging-Header.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 20`** (1 nodes): `GeneratedPluginRegistrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 21`** (1 nodes): `resource.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 22`** (1 nodes): `utils.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 23`** (1 nodes): `win32_window.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 24`** (1 nodes): `generated_plugin_registrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 25`** (1 nodes): `my_application.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 26`** (1 nodes): `generated_plugin_registrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 27`** (1 nodes): `ImagensProcessadasScreen`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 28`** (1 nodes): `CustomAppBar Widget`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ApiService` connect `API Layer & Data Models` to `Credits & Purchases`, `OMR Vision Pipeline`?**
  _High betweenness centrality (0.066) - this node is a cross-community bridge._
- **Why does `POST /api/processar-imagem-cartao/ (Django backend OMR)` connect `OMR Vision Pipeline` to `API Layer & Data Models`?**
  _High betweenness centrality (0.021) - this node is a cross-community bridge._
- **What connects `-registerWithRegistry`, `MainActivity`, `ImagensProcessadasScreen` to the rest of the system?**
  _27 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `API Layer & Data Models` be split into smaller, more focused modules?**
  _Cohesion score 0.09 - nodes in this community are weakly interconnected._
- **Should `Screen Navigation & Auth` be split into smaller, more focused modules?**
  _Cohesion score 0.13 - nodes in this community are weakly interconnected._