// capture_tips_screen.dart
import 'package:flutter/material.dart';

class CaptureTipsScreen extends StatelessWidget {
  final VoidCallback onContinue;

  const CaptureTipsScreen({super.key, required this.onContinue});

  static const Color primary     = Color(0xFF0DA6F2);
  static const Color primaryDark = Color(0xFF003D5C);
  static const Color bgLight     = Color(0xFFF8FAFC);
  static const Color textMain    = Color(0xFF003D5C);
  static const Color textSub     = Color(0xFF475569);
  static const Color borderLight = Color(0xFFDBE2E6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: primaryDark, size: 20),
        ),
        title: RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'SIMULADO',
                style: TextStyle(color: primaryDark, fontSize: 15, fontWeight: FontWeight.w900),
              ),
              TextSpan(
                text: 'APP',
                style: TextStyle(color: primary, fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: borderLight),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.camera_alt_rounded, color: primary, size: 48),
              const SizedBox(height: 14),
              const Text(
                'Dicas para melhor leitura',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textMain,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Siga estas dicas para garantir 100% de precisão',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSub, fontSize: 13),
              ),

              const SizedBox(height: 28),

              _tip(
                icon: Icons.wb_sunny_rounded,
                color: const Color(0xFFF59E0B),
                title: 'Boa iluminação',
                desc: 'Use local bem iluminado. Evite sombras sobre o cartão. Se necessário, ative o flash.',
              ),
              const SizedBox(height: 14),
              _tip(
                icon: Icons.crop_free_rounded,
                color: const Color(0xFF22C55E),
                title: 'Alinhe os marcadores',
                desc: 'Encaixe os 4 círculos pretos do cartão dentro dos círculos verdes da moldura.',
              ),
              const SizedBox(height: 14),
              _tip(
                icon: Icons.phone_android_rounded,
                color: primary,
                title: 'Mantenha firme',
                desc: 'Segure o celular paralelo ao cartão, a ~25 cm. Aguarde o indicador ficar verde.',
              ),

              const Spacer(),

              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(Icons.camera_alt_rounded, size: 20),
                  label: const Text(
                    'Abrir câmera',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              TextButton(
                onPressed: onContinue,
                child: const Text(
                  'Pular dicas',
                  style: TextStyle(color: textSub, fontSize: 13),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tip({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(desc,
                    style: const TextStyle(
                        color: textSub, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
