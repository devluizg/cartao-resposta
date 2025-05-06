import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // URL base da API - substitua pelo seu domínio
  static const String baseUrl = 'http://192.168.1.8:8001';

  // Chaves para armazenamento dos tokens e informações do usuário
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userNameKey = 'user_name';
  static const String userEmailKey = 'user_email';

  // Verifica se o usuário está logado
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(accessTokenKey);
    return accessToken != null;
  }

  // Obtem o token de acesso atual
  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(accessTokenKey);
  }

  // Faz login no sistema
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    try {
      final requestBody = {
        'username': username,
        'password': password,
      };

      debugPrint('Enviando requisição de login com body: $requestBody');

      final response = await http.post(
        Uri.parse('$baseUrl/api/token/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      debugPrint('Status da resposta: ${response.statusCode}');
      debugPrint('Corpo da resposta: ${response.body}');

      if (response.statusCode == 200) {
        final tokenData = jsonDecode(response.body);
        debugPrint('Token data recebido: $tokenData');

        final prefs = await SharedPreferences.getInstance();

        // Verifica se recebeu os tokens esperados
        if (tokenData.containsKey('access') &&
            tokenData.containsKey('refresh')) {
          await prefs.setString(accessTokenKey, tokenData['access']);
          await prefs.setString(refreshTokenKey, tokenData['refresh']);

          // Busca informações do usuário
          final userInfo = await getUserInfo();
          debugPrint('Informações do usuário: $userInfo');

          return {'success': true};
        } else {
          debugPrint(
              'Tokens esperados não encontrados na resposta: $tokenData');
          return {
            'success': false,
            'message': 'Formato de resposta inválido do servidor'
          };
        }
      } else {
        debugPrint('Login falhou: ${response.statusCode} - ${response.body}');

        // Tentar extrair mensagem de erro se estiver em formato JSON
        try {
          final errorData = jsonDecode(response.body);
          final errorMessage = errorData['detail'] ?? 'Credenciais inválidas';
          return {'success': false, 'message': errorMessage};
        } catch (e) {
          return {
            'success': false,
            'message':
                'Credenciais inválidas. Verifique seu nome de usuário e senha.'
          };
        }
      }
    } catch (e) {
      debugPrint('Exceção durante login: $e');
      return {
        'success': false,
        'message': 'Erro de conexão com o servidor. Tente novamente mais tarde.'
      };
    }
  }

  // Obtem informações do usuário
  static Future<Map<String, dynamic>?> getUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(accessTokenKey);

    if (accessToken == null) {
      debugPrint(
          'Tentativa de obter informações do usuário sem token de acesso');
      return null;
    }

    try {
      debugPrint(
          'Obtendo informações do usuário com token: ${accessToken.substring(0, min(10, accessToken.length))}...');

      final response = await http.get(
        Uri.parse('$baseUrl/api/user-info/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      debugPrint('Status da resposta getUserInfo: ${response.statusCode}');
      debugPrint('Corpo da resposta getUserInfo: ${response.body}');

      if (response.statusCode == 200) {
        final userData = jsonDecode(response.body);

        // Salva os dados do usuário
        await prefs.setString(userNameKey, userData['name']);
        await prefs.setString(userEmailKey, userData['email']);

        return userData;
      }
      debugPrint(
          'Falha ao obter informações do usuário: ${response.statusCode} - ${response.body}');

      // Se token expirou, tenta atualizar automaticamente
      if (response.statusCode == 401) {
        debugPrint('Token expirado, tentando atualizar...');
        final refreshed = await refreshToken();
        if (refreshed) {
          debugPrint(
              'Token atualizado com sucesso, tentando obter informações novamente');
          return getUserInfo();
        }
      }

      return null;
    } catch (e) {
      debugPrint('Exceção ao obter informações do usuário: $e');
      return null;
    }
  }

  // Atualiza o token de acesso usando o refresh token
  static Future<bool> refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(refreshTokenKey);

    if (refreshToken == null) {
      debugPrint('Tentativa de atualizar token sem refresh token');
      return false;
    }

    try {
      debugPrint(
          'Tentando atualizar token com refresh token: ${refreshToken.substring(0, min(10, refreshToken.length))}...');

      final response = await http.post(
        Uri.parse('$baseUrl/api/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refresh': refreshToken,
        }),
      );

      debugPrint('Status da resposta refreshToken: ${response.statusCode}');
      debugPrint('Corpo da resposta refreshToken: ${response.body}');

      if (response.statusCode == 200) {
        final tokenData = jsonDecode(response.body);
        if (tokenData.containsKey('access')) {
          await prefs.setString(accessTokenKey, tokenData['access']);
          debugPrint('Token de acesso atualizado com sucesso');
          return true;
        } else {
          debugPrint(
              'Formato de resposta inválido na atualização do token: $tokenData');
          return false;
        }
      }
      debugPrint(
          'Falha ao atualizar token: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Exceção ao atualizar token: $e');
      return false;
    }
  }

  // Faz logout do sistema
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(accessTokenKey);
    await prefs.remove(refreshTokenKey);
    await prefs.remove(userNameKey);
    await prefs.remove(userEmailKey);

    debugPrint('Usuário deslogado e tokens removidos');
  }

  // Realiza uma requisição HTTP com autorização
  static Future<http.Response> authorizedRequest(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    dynamic body,
    bool autoRefresh = true,
  }) async {
    final token = await getAccessToken();

    if (token == null) {
      debugPrint('Tentativa de requisição autorizada sem token de acesso');
      throw Exception('Usuário não autenticado');
    }

    headers = headers ?? {};
    headers['Authorization'] = 'Bearer $token';
    headers['Content-Type'] = 'application/json';

    debugPrint('Realizando requisição $method para $url');

    http.Response response;

    switch (method) {
      case 'GET':
        response = await http.get(Uri.parse(url), headers: headers);
        break;
      case 'POST':
        final encodedBody = body != null ? jsonEncode(body) : null;
        debugPrint('Body da requisição POST: $encodedBody');
        response = await http.post(
          Uri.parse(url),
          headers: headers,
          body: encodedBody,
        );
        break;
      case 'PUT':
        response = await http.put(
          Uri.parse(url),
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
        break;
      case 'DELETE':
        response = await http.delete(Uri.parse(url), headers: headers);
        break;
      default:
        throw Exception('Método HTTP não suportado');
    }

    debugPrint(
        'Resposta da requisição $method para $url: ${response.statusCode}');
    debugPrint('Corpo da resposta: ${response.body}');

    // Se token expirou, tenta atualizar e refazer a requisição
    if (response.statusCode == 401 && autoRefresh) {
      debugPrint('Token expirado, tentando atualizar e refazer a requisição');
      final refreshed = await refreshToken();
      if (refreshed) {
        debugPrint('Token atualizado com sucesso, refazendo requisição');
        return authorizedRequest(
          url,
          method: method,
          headers: headers,
          body: body,
          autoRefresh: false,
        );
      }
    }

    return response;
  }

  // Função auxiliar para limitar o tamanho da string
  static int min(int a, int b) {
    return (a < b) ? a : b;
  }
}
