import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/login_screen.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onExit;
  final bool showBack;

  const CustomAppBar({
    super.key,
    this.onExit,
    this.showBack = false,
  });

  Future<void> _handleExit(BuildContext context) async {
    if (onExit != null) {
      onExit!();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.remove('user_name');
      await prefs.remove('user_email');
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const Color primary      = Color(0xFF0DA6F2);
    const Color primaryDark  = Color(0xFF003D5C);
    const Color borderColor  = Color(0xFFDBE2E6);
    const Color textSub      = Color(0xFF475569);

    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: primaryDark, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            )
          : null,
      title: Row(
        children: [
          // Logo SimuladoApp
          Image.asset(
            'assets/images/nova_logo.png',
            width: 32,
            height: 32,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 10),
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'SIMULADO',
                  style: TextStyle(
                    color: primaryDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                TextSpan(
                  text: 'APP',
                  style: TextStyle(
                    color: primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _handleExit(context),
          child: const Text(
            'Sair',
            style: TextStyle(
              color: textSub,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: borderColor),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);
}
