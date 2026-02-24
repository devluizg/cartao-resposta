// multi_shot_capture_screen.dart
// Tela para capturar múltiplas fotos (2-3) e processar votação
import 'package:flutter/material.dart';
import 'dart:io';
import '../services/multi_shot_voting_service.dart';

/// Widget para exibir resultado de votação
class MultiShotVotingResultDialog extends StatelessWidget {
  final MultiShotVotingResult result;
  final VoidCallback onConfirm;
  final VoidCallback onRetry;

  const MultiShotVotingResultDialog({
    super.key,
    required this.result,
    required this.onConfirm,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final recommendation = MultiShotVotingService.getRecommendation(result);
    final shouldRetry = MultiShotVotingService.shouldRetry(result);

    // Determinar cor baseado em concordância
    Color bannerColor;
    IconData bannerIcon;
    if (result.overallAgreement >= 0.85) {
      bannerColor = Colors.green.shade700;
      bannerIcon = Icons.check_circle;
    } else if (result.overallAgreement >= 0.70) {
      bannerColor = Colors.blue.shade700;
      bannerIcon = Icons.info;
    } else {
      bannerColor = Colors.orange.shade700;
      bannerIcon = Icons.warning_amber;
    }

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bannerColor.withOpacity(0.2),
              border: Border(
                bottom: BorderSide(
                  color: bannerColor.withOpacity(0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(bannerIcon, color: bannerColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Votação Multi-Shot',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${result.shots.length} foto${result.shots.length > 1 ? 's' : ''} capturada${result.shots.length > 1 ? 's' : ''}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Conteúdo
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Recomendação
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bannerColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: bannerColor.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      recommendation,
                      style: TextStyle(
                        color: bannerColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Estatísticas
                  Text(
                    'Concordância Geral',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatMetric(
                          label: 'Acordo',
                          value:
                              '${(result.overallAgreement * 100).toStringAsFixed(1)}%',
                          color: bannerColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatMetric(
                          label: 'Ambíguas',
                          value: '${result.ambiguousQuestions.length}',
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatMetric(
                          label: 'Nítidas',
                          value:
                              '${result.questionVotes.length - result.ambiguousQuestions.length}',
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Questões ambíguas (se houver)
                  if (result.ambiguousQuestions.isNotEmpty) ...[
                    Text(
                      'Questões com Discordância',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.2),
                        ),
                      ),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: result.ambiguousQuestions
                            .map(
                              (q) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.orange.withOpacity(0.4),
                                  ),
                                ),
                                child: Text(
                                  'Q$q',
                                  style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Detalhes das capturas
                  Text(
                    'Qualidade das Fotos',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: result.shots
                        .map(
                          (shot) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _buildShotQualityBar(
                              shotNumber: shot.shotNumber,
                              qualityScore: shot.imageQualityScore,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),

          // Botões
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                if (shouldRetry)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('REFAZER'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.orange.withOpacity(0.5),
                        ),
                        foregroundColor: Colors.orange,
                      ),
                    ),
                  ),
                if (shouldRetry) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('USAR VOTAÇÃO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: bannerColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Widget para métrica de estatística
  Widget _buildStatMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Widget para barra de qualidade de foto
  Widget _buildShotQualityBar({
    required int shotNumber,
    required double qualityScore,
  }) {
    final percentage = qualityScore * 100;
    final color = percentage >= 75
        ? Colors.green
        : percentage >= 60
            ? Colors.blue
            : Colors.orange;

    return Row(
      children: [
        Text(
          'Foto $shotNumber',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: qualityScore,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${percentage.toStringAsFixed(0)}%',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Dialog para capturar múltiplas fotos
class MultiShotCaptureDialog extends StatefulWidget {
  final Function(List<File> images) onComplete;

  const MultiShotCaptureDialog({
    super.key,
    required this.onComplete,
  });

  @override
  State<MultiShotCaptureDialog> createState() => _MultiShotCaptureDialogState();
}

class _MultiShotCaptureDialogState extends State<MultiShotCaptureDialog> {
  int _currentShot = 1;
  final _images = <File>[];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              border: Border(
                bottom: BorderSide(
                  color: Colors.blue.withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.photo_camera,
                  color: Colors.blue.shade300,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Captura Múltipla',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Foto $_currentShot de 3',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Conteúdo
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _currentShot / 3,
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation(
                      Colors.blue.shade300,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Instruções
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: Colors.blue.shade300,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentShot == 1
                              ? 'Primeira captura: tire uma foto bem enquadrada'
                              : 'Foto $_currentShot: ligeiramente diferente da anterior',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Status das imagens capturadas
                if (_images.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Imagens Capturadas',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: List.generate(
                          3,
                          (index) => Expanded(
                            child: Container(
                              height: 40,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: index < _images.length
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: index < _images.length
                                      ? Colors.green.withOpacity(0.5)
                                      : Colors.white.withOpacity(0.1),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  index < _images.length
                                      ? '✅ Foto ${index + 1}'
                                      : 'Foto ${index + 1}',
                                  style: TextStyle(
                                    color: index < _images.length
                                        ? Colors.green.shade300
                                        : Colors.white.withOpacity(0.5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Botões
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('CANCELAR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white.withOpacity(0.7),
                    side: BorderSide(
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _currentShot <= 3
                        ? () {
                            // Simular captura
                            setState(() {
                              _currentShot++;
                              if (_currentShot <= 3) {
                                // Simular que imagem foi capturada
                                _images.add(File(''));
                              }
                            });

                            if (_currentShot > 3) {
                              Navigator.pop(context);
                              widget.onComplete(_images);
                            }
                          }
                        : null,
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: Text(_currentShot <= 3
                        ? 'CAPTURAR FOTO $_currentShot'
                        : 'CONCLUÍDO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
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
