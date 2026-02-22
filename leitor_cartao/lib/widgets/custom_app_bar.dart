import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/login_screen.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onReload;
  final VoidCallback? onExit;

  const CustomAppBar({
    super.key,
    this.onReload,
    this.onExit,
  });

  Future<void> _handleExit(BuildContext context) async {
    if (onExit != null) {
      onExit!();
    } else {
      // Comportamento padrão de logout
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('access_token');
        await prefs.remove('refresh_token');
        await prefs.remove('user_name');
        await prefs.remove('user_email');

        if (!context.mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      } catch (e) {
        // Silenciar erros
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cores extraídas de selection_screen.dart / AppColors
    const Color primaryColor = Color(0xFF0DA6F2);
    const Color secondaryColor = Color(0xFF003D5C);
    const Color borderColor = Color(0xFFDBE2E6);
    const Color textSub = Color(0xFF475569);

    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: secondaryColor,
      automaticallyImplyLeading: false, // Remove o botão de voltar padrão
      title: Row(
        children: [
          // Logo
          Image.asset(
            'assets/images/nova_logo.png',
            height: 32,
            width: 32,
            errorBuilder: (context, error, stackTrace) {
              // Fallback se a imagem não carregar
              return Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryColor, secondaryColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: 20,
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          const Text(
            'SimuladoApp',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: secondaryColor,
            ),
          ),
        ],
      ),
      actions: [
        // Botão Recarregar
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Recarregar',
          onPressed: onReload,
          color: textSub,
        ),
        // Botão Sair
        TextButton.icon(
          onPressed: () => _handleExit(context),
          icon: const Icon(
            Icons.logout_rounded,
            color: textSub,
            size: 20,
          ),
          label: const Text(
            'Sair',
            style: TextStyle(
              color: textSub,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: borderColor,
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);
}
