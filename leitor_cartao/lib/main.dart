import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/selection_screen.dart';
import 'screens/login_screen.dart';

class AppColors {
  static const Color primaryColor = Color(0xFF0DA6F2);
  static const Color secondaryColor = Color(0xFF003D5C);
  static const Color bgDark = Color(0xFF121E25);
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color bgSurface = Color(0xFF1A2A33);
  static const Color bgSurfaceLight = Color(0xFFFFFFFF);
  static const Color borderColor = Color(0xFFDBE2E6);
  static const Color textLight = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color successColor = Color(0xFF16A34A);
  static const Color dangerColor = Color(0xFFEF4444);
  static const Color warningColor = Color(0xFFF2A93B);
}

void main() {
  runApp(const CartaoRespostaApp());
}

class CartaoRespostaApp extends StatelessWidget {
  const CartaoRespostaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimuladoApp',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scaffoldBackgroundColor: AppColors.bgLight,
        cardTheme: CardTheme(
          color: AppColors.bgSurfaceLight,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.borderColor, width: 1),
          ),
        ),
      ),
      home: const AuthenticationWrapper(),
    );
  }
}

class AuthenticationWrapper extends StatefulWidget {
  const AuthenticationWrapper({super.key});

  @override
  State<AuthenticationWrapper> createState() => _AuthenticationWrapperState();
}

class _AuthenticationWrapperState extends State<AuthenticationWrapper> {
  bool _checkingAuth = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');

    setState(() {
      _isAuthenticated = accessToken != null;
      _checkingAuth = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) {
      return const Scaffold(
        backgroundColor: AppColors.bgLight,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryColor,
          ),
        ),
      );
    }

    if (_isAuthenticated) {
      return const SelectionScreen();
    } else {
      return const LoginScreen();
    }
  }
}
