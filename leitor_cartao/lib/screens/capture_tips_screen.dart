// capture_tips_screen.dart
// Tela de dicas visuais antes de abrir a câmera
import 'package:flutter/material.dart';

/// Tela com 3 dicas rápidas antes de abrir a câmera
class CaptureTipsScreen extends StatelessWidget {
  final VoidCallback onContinue;

  const CaptureTipsScreen({super.key, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // Título
              const Icon(
                Icons.camera_alt_rounded,
                color: Color(0xFF0DA6F2),
                size: 56,
              ),
              const SizedBox(height: 16),
              const Text(
                'Dicas para a melhor foto',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Siga estas dicas para garantir 100% de precisão na leitura',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Dica 1
              _buildTip(
                icon: Icons.wb_sunny_rounded,
                color: const Color(0xFFF59E0B),
                title: 'Boa iluminação',
                description:
                    'Use um local bem iluminado. Evite sombras sobre o cartão. Se necessário, ative o flash.',
              ),

              const SizedBox(height: 20),

              // Dica 2
              _buildTip(
                icon: Icons.crop_free_rounded,
                color: const Color(0xFF22C55E),
                title: 'Folha reta e plana',
                description:
                    'Coloque o cartão sobre uma superfície plana e clara. Encaixe os 4 quadrados pretos nos cantos da moldura.',
              ),

              const SizedBox(height: 20),

              // Dica 3
              _buildTip(
                icon: Icons.phone_android_rounded,
                color: const Color(0xFF0DA6F2),
                title: 'Mantenha firme',
                description:
                    'Segure o celular paralelo ao cartão, a ~25cm de distância. Aguarde o indicador ficar verde antes de capturar.',
              ),

              const Spacer(),

              // Botão continuar
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0DA6F2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Abrir câmera',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, color: Colors.white),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Skip
              TextButton(
                onPressed: onContinue,
                child: const Text(
                  'Pular dicas',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTip({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 13,
                    height: 1.4,
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
