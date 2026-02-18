import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../services/api_service.dart';
import 'selection_screen.dart';

// Enum para ambientes (mantido para desenvolvimento futuro, se necessário)
enum Environment { development, production }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  String _errorMessage = '';
  final ApiService _apiService = ApiService();
  StreamSubscription<Uri>? _deepLinkSubscription;

  // Design System - Tema Claro com Cyan e Azul
  static const Color primary = Color(0xFF0DA6F2);        // Azul corporativo
  static const Color primaryLight = Color(0xFF4FA3F7);   // Azul claro
  static const Color primaryDark = Color(0xFF0084D4);    // Azul escuro
  static const Color cyan = Color(0xFF00BCD4);           // Cyan vibrante
  static const Color cyanLight = Color(0xFF4DD0E1);      // Cyan claro
  static const Color bgLight = Color(0xFFF0F8FF);        // Fundo azul muito claro
  static const Color bgDark = Color(0xFF1A1A2E);         // Fundo escuro (não usado neste tema)
  static const Color surfaceLight = Color(0xFFFFFFFF);   // Superfície branca
  static const Color surfaceDark = Color(0xFF1E1E1E);    // Superfície escura (não usado)
  static const Color textMainLight = Color(0xFF0D3B66);  // Texto principal azul escuro
  static const Color textMainDark = Color(0xFFF0F2F4);   // Texto principal (não usado)
  static const Color textSubLight = Color(0xFF4A6FA5);   // Texto secundário azul médio
  static const Color textSubDark = Color(0xFF9AA0A6);    // Texto secundário (não usado)
  static const Color errorColor = Color(0xFFD32F2F);     // Vermelho erro
  static const Color successColor = Color(0xFF388E3C);   // Verde sucesso
  static const Color borderLight = Color(0xFFB3E5FC);    // Border cyan claro
  static const Color borderDark = Color(0xFF333333);     // Border escuro (não usado)

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _setupDeepLinks();
  }

  void _setupDeepLinks() {
    final appLinks = AppLinks();
    _deepLinkSubscription = appLinks.uriLinkStream.listen((uri) {
      print('Deep link recebido: $uri');
      if (uri.scheme == 'simuladoapp' && uri.host == 'oauth') {
        _handleOAuthCallback(uri.toString());
      }
    });
  }

  Future<void> _handleOAuthCallback(String callbackUrl) async {
    print('=== PROCESSANDO CALLBACK OAUTH ===');
    print('URL: $callbackUrl');

    final uri = Uri.parse(callbackUrl);
    final access = uri.queryParameters['access'];
    final refresh = uri.queryParameters['refresh'];
    final email = uri.queryParameters['email'];
    final error = uri.queryParameters['error'];

    if (error != null) {
      print('❌ Erro no callback: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Erro ao fazer login com Google. Tente novamente.';
        });
      }
      return;
    }

    if (access != null && refresh != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', access);
      await prefs.setString('refresh_token', refresh);
      print('✅ Tokens salvos!');

      await _apiService.getUserInfo();

      if (mounted) {
        setState(() { _isLoading = false; });
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const SelectionScreen()),
        );
      }
    } else {
      print('❌ Tokens ausentes no callback');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Erro ao completar autenticação com Google.';
        });
      }
    }
  }

  Future<void> _initializeApp() async {
    // Configurar para servidor de produção na Hetzner
    _apiService.setBaseUrl('https://simuladoapp.com.br');
    print('=== INICIALIZAÇÃO DO APP ===');
    debugPrint('App inicializado em modo PRODUÇÃO');
    debugPrint('URL do servidor: https://simuladoapp.com.br');
    print('URL configurada: https://simuladoapp.com.br');

    // Verificar conexão
    print('Testando conexão com servidor...');
    await _checkConnection();
  }

  Future<void> _checkConnection() async {
    bool isConnected = await _apiService.testConnection();
    print('Resultado do teste de conexão: $isConnected');

    if (!isConnected && mounted) {
      print('❌ ERRO: Não foi possível conectar ao servidor');
      setState(() {
        _errorMessage =
            'Não foi possível conectar ao servidor. Verifique sua conexão com a internet.';
      });
    } else if (mounted) {
      print('✅ Conexão com servidor estabelecida com sucesso');
      setState(() {
        _errorMessage = '';
      });
      debugPrint('Conexão com o servidor estabelecida com sucesso.');
    }
  }

  Future<void> _loginWithGoogle() async {
    print('\n=== INICIANDO LOGIN COM GOOGLE ===');

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Abre o Chrome completo (não Custom Tab). Quando o OAuth terminar,
      // o servidor redireciona para simuladoapp://oauth/callback?...
      // Android detecta o deep link e traz este app para o primeiro plano.
      // O callback é capturado pelo listener em _setupDeepLinks().
      final authUrl = Uri.parse(
        'https://simuladoapp.com.br/accounts/google/login/?process=login&next=/api/auth/google/complete/',
      );

      print('🌐 Abrindo Chrome...');
      print('Auth URL: $authUrl');

      final launched = await launchUrl(
        authUrl,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        print('❌ Não foi possível abrir o navegador');
        setState(() {
          _isLoading = false;
          _errorMessage = 'Não foi possível abrir o navegador. Tente novamente.';
        });
      }
      // Fica em _isLoading = true aguardando o deep link em _handleOAuthCallback
    } catch (e) {
      print('❌ Erro ao abrir navegador: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erro ao abrir o navegador. Tente novamente.';
      });
    }
  }

  Future<void> _launchWebsite(String urlString) async {
    print('Tentando abrir URL: $urlString');
    final Uri url = Uri.parse(urlString);
    print('URI parseada: $url');

    print('Verificando se pode abrir a URL...');
    if (await canLaunchUrl(url)) {
      print('✅ URL pode ser aberta, lançando...');
      await launchUrl(url, mode: LaunchMode.externalApplication);
      print('✅ URL lançada com sucesso');
    } else {
      print('❌ ERRO: Não foi possível abrir a URL: $url');
      debugPrint('Could not launch $url');
      if (mounted) {
        setState(() {
          _errorMessage = 'Não foi possível abrir o site.';
        });
      }
    }
  }

  Future<void> _login() async {
    print('\n=== INICIANDO LOGIN NORMAL (EMAIL/SENHA) ===');

    if (!_formKey.currentState!.validate()) {
      print('❌ Validação de formulário falhou');
      return;
    }

    print('✅ Formulário validado com sucesso');
    print('Email: ${_usernameController.text.trim()}');
    print('Senha: ${_passwordController.text.isNotEmpty ? "[SENHA FORNECIDA - ${_passwordController.text.length} caracteres]" : "[SENHA VAZIA]"}');

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      print('Chamando _apiService.login()...');
      final success = await _apiService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      print('Resultado da chamada login(): $success');

      if (success) {
        print('✅ Login bem-sucedido! Navegando para SelectionScreen...');
        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const SelectionScreen()),
        );
      } else {
        print('❌ Login falhou: Credenciais inválidas');
        setState(() {
          _errorMessage = 'Credenciais inválidas. Verifique seu Email e Senha.';
        });
      }
    } catch (e, stackTrace) {
      print('❌ EXCEÇÃO durante o login:');
      print('Erro: $e');
      print('Tipo do erro: ${e.runtimeType}');
      print('Stack trace:');
      print(stackTrace);
      setState(() {
        _errorMessage =
            'Erro de conexão com o servidor. Tente novamente mais tarde.';
      });
      debugPrint('Exception during login: $e');
    } finally {
      if (mounted) {
        print('Finalizando processo de login, _isLoading = false');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Tema claro sempre ativo
  Color get _bgColor => bgLight;
  Color get _surfaceColor => surfaceLight;
  Color get _textMain => textMainLight;
  Color get _textSub => textSubLight;
  Color get _borderColor => borderLight;

  Widget _buildLogo({double padding = 0}) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Image.asset(
        'assets/images/nova_logo.png',
        fit: BoxFit.contain,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            color: _bgColor,
            child: isSmallScreen
                ? _buildMobileLayout()
                : _buildDesktopLayout(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Header com Logo
        _buildHeader(),
        // Form Container
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
          child: _buildFormCard(),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left side - Branding com gradiente cyan/azul
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cyan,
                  primaryDark,
                ],
              ),
            ),
            child: Center(
              child: _buildBrandingSide(),
            ),
          ),
        ),
        // Right side - Form
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48.0),
              child: _buildFormCard(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          // Logo com gradiente cyan
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cyanLight.withOpacity(0.3),
                  primary.withOpacity(0.3),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cyan.withOpacity(0.4),
                width: 1.5,
              ),
            ),
            child: _buildLogo(padding: 8),
          ),
          const SizedBox(height: 24),
          // Título
          Text(
            'SimuladoApp',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: primaryDark,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Acesse seus simulados',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: _textSub,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBrandingSide() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Logo maior com fundo branco semi-transparente
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: _buildLogo(padding: 10),
        ),
        const SizedBox(height: 32),
        // Título
        const Text(
          'Bem-vindo ao\nSimuladoApp',
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.2,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        // Descrição
        const Text(
          'Organize, avalie e evolua\ncom sua turma.',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Color(0xFFE0F2F1),
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderLight,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: cyan.withOpacity(0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: primary.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Título do form
            Text(
              'Acessar Conta',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: _textMain,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Entre com suas credenciais para continuar',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _textSub,
              ),
            ),
            const SizedBox(height: 28),

            // Mensagem de erro
            if (_errorMessage.isNotEmpty)
              _buildErrorMessage(),

            // Campo de Email
            _buildEmailField(),
            const SizedBox(height: 20),

            // Campo de Senha
            _buildPasswordField(),
            const SizedBox(height: 28),

            // Botão de Login
            _buildLoginButton(),
            const SizedBox(height: 20),

            // Divider
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: _borderColor,
                    height: 1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Ou continuar com',
                    style: TextStyle(
                      fontSize: 12,
                      color: _textSub,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: _borderColor,
                    height: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Google Sign In (placeholder)
            _buildGoogleButton(),
            const SizedBox(height: 24),

            // Footer
            Column(
              children: [
                Center(
                  child: RichText(
                    text: TextSpan(
                      text: 'Não tem uma conta? ',
                      style: TextStyle(
                        fontSize: 14,
                        color: _textSub,
                        fontWeight: FontWeight.w400,
                      ),
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => _launchWebsite(
                              'https://simuladoapp.com.br/accounts/register/',
                            ),
                            child: Text(
                              'Criar conta',
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: () => _launchWebsite('https://simuladoapp.com.br/'),
                    child: Text(
                      '🌐 Visitar SimuladoApp',
                      style: TextStyle(
                        fontSize: 12,
                        color: cyan,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: errorColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: errorColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.error_outline_rounded,
              color: errorColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage,
              style: TextStyle(
                color: errorColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'E-mail',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textMain,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _usernameController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(
            color: _textMain,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: 'seu@email.com',
            hintStyle: TextStyle(
              color: _textSub.withOpacity(0.6),
              fontSize: 15,
            ),
            prefixIcon: Icon(
              Icons.mail_outline_rounded,
              color: _textSub,
              size: 20,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _borderColor,
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _borderColor,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: primary,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: errorColor,
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: errorColor,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          validator: (value) {
            print('Validando email: "$value"');
            if (value == null || value.isEmpty) {
              print('❌ Validação email: campo vazio');
              return 'Por favor, insira seu e-mail';
            }
            if (!value.contains('@')) {
              print('❌ Validação email: não contém @');
              return 'E-mail inválido';
            }
            print('✅ Validação email: OK');
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Senha',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textMain,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          obscureText: !_isPasswordVisible,
          style: TextStyle(
            color: _textMain,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: TextStyle(
              color: _textSub.withOpacity(0.6),
              fontSize: 15,
            ),
            prefixIcon: Icon(
              Icons.lock_outline_rounded,
              color: _textSub,
              size: 20,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _textSub,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _isPasswordVisible = !_isPasswordVisible;
                });
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _borderColor,
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _borderColor,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: primary,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: errorColor,
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: errorColor,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          validator: (value) {
            print('Validando senha: ${value != null && value.isNotEmpty ? "[${value.length} caracteres]" : "[vazio]"}');
            if (value == null || value.isEmpty) {
              print('❌ Validação senha: campo vazio');
              return 'Por favor, insira sua senha';
            }
            if (value.length < 4) {
              print('❌ Validação senha: menos de 4 caracteres');
              return 'Senha deve ter pelo menos 4 caracteres';
            }
            print('✅ Validação senha: OK');
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          disabledBackgroundColor: primary.withOpacity(0.5),
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: primary.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                  backgroundColor: primary.withOpacity(0.3),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.login_rounded, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Entrar',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _loginWithGoogle,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: borderLight,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.white,
          foregroundColor: _textMain,
        ),
        child: _isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(primary),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Ícone do Google (letra G estilizada)
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: primary.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'G',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Entrar com Google',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textMain,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
