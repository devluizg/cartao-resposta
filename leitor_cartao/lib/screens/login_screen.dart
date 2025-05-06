import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'selection_screen.dart'; // ✅ Importação correta da tela de seleção

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
  String _errorMessage = '';
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
    _checkConnection();
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('server_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _apiService.setBaseUrl(savedUrl);
      debugPrint('Loaded server URL: $savedUrl');
    }
  }

  Future<void> _checkConnection() async {
    bool isConnected = await _apiService.testConnection();
    if (!isConnected && mounted) {
      setState(() {
        _errorMessage =
            'Não foi possível conectar ao servidor. Verifique a conexão.';
      });
    } else if (mounted) {
      setState(() {
        _errorMessage = '';
      });
      debugPrint('Conexão com o servidor estabelecida com sucesso.');
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final success = await _apiService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (success) {
        if (!mounted) return;

        // ✅ Redireciona para a tela de seleção após login
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const SelectionScreen()),
        );
      } else {
        setState(() {
          _errorMessage =
              'Credenciais inválidas. Verifique seu nome de usuário e senha.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'Erro de conexão com o servidor. Tente novamente mais tarde.';
      });
      debugPrint('Exception during login: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Corretor de Simulados',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _usernameController,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      labelText: 'Nome de usuário',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, insira seu nome de usuário';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, insira sua senha';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  if (_errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      backgroundColor: Colors.blue,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Entrar',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      _showServerConfigDialog();
                    },
                    child: const Text(
                      'Problemas de conexão? Configurar servidor',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showServerConfigDialog() {
    final serverController = TextEditingController(text: _apiService.baseUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurar Servidor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Insira o endereço completo do servidor (com http:// ou https://)'),
            const SizedBox(height: 16),
            TextField(
              controller: serverController,
              decoration: const InputDecoration(
                labelText: 'Endereço do servidor',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final newUrl = serverController.text.trim();
              if (newUrl.isNotEmpty) {
                _apiService.setBaseUrl(newUrl);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('server_url', newUrl);

                if (mounted) {
                  // ignore: use_build_context_synchronously
                  Navigator.pop(context);
                  await _checkConnection();
                }
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
