import 'package:flutter/material.dart';
import 'api_service.dart';
import 'dart:developer' as developer;
import 'compras_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'models/produto_credito.dart';

class CreditManager {
  static final CreditManager _instance = CreditManager._internal();
  factory CreditManager() => _instance;
  CreditManager._internal();

  final ApiService _apiService = ApiService();
  final ComprasService _comprasService = ComprasService();

  // Cache local dos créditos
  int? _availableCredits;
  int? _totalCredits;
  int? _usedCredits;
  DateTime? _lastCheck;

  // Planos de créditos disponíveis (sincronizados com o Google Play)
  static const List<Map<String, dynamic>> creditPlans = [
    {
      'id': 'starter_300_creditos', // ID do Google Play
      'localId': 'starter',
      'name': 'Starter',
      'credits': 300,
      'price': 14.90,
      'description': 'Ideal para professores iniciantes',
      'color': Colors.blue,
      'popular': false,
    },
    {
      'id': 'professor_ativo_800_creditos', // ID do Google Play
      'localId': 'professor_ativo',
      'name': 'Professor Ativo',
      'credits': 800,
      'price': 29.90,
      'description': 'Para uso regular em sala de aula',
      'color': Colors.green,
      'popular': true,
    },
    {
      'id': 'escola_pequena_2000_creditos', // ID do Google Play
      'localId': 'escola_pequena',
      'name': 'Escola Pequena',
      'credits': 2000,
      'price': 59.90,
      'description': 'Para escolas com até 200 alunos',
      'color': Colors.orange,
      'popular': false,
    },
    {
      'id': 'escola_profissional_5000_creditos', // ID do Google Play
      'localId': 'escola_profissional',
      'name': 'Escola Profissional',
      'credits': 5000,
      'price': 99.90,
      'description': 'Para instituições de ensino grandes',
      'color': Colors.purple,
      'popular': false,
    },
  ];

  /// Inicializar o sistema de compras
  Future<void> initializePurchases() async {
    try {
      // Configurar callbacks do sistema de compras
      _comprasService.onCompraSucesso = (creditos) async {
        developer.log('💰 Compra realizada com sucesso! $creditos créditos');
        // Forçar atualização do cache após compra
        await getAvailableCredits(forceRefresh: true);
      };

      _comprasService.onCompraErro = (erro) {
        developer.log('❌ Erro na compra: $erro');
      };

      _comprasService.onCompraStatus = (status) {
        developer.log('📱 Status da compra: $status');
      };

      // Carregar produtos do Google Play
      await _comprasService.carregarProdutos();
      developer.log('🛒 Produtos carregados do Google Play');
    } catch (e) {
      developer.log('❌ Erro ao inicializar compras: $e');
    }
  }

  /// Verificar créditos com cache inteligente (válido por 30 segundos)
  Future<int> getAvailableCredits({bool forceRefresh = false}) async {
    final now = DateTime.now();

    // Se tem cache válido e não é refresh forçado
    if (!forceRefresh &&
        _availableCredits != null &&
        _lastCheck != null &&
        now.difference(_lastCheck!).inSeconds < 30) {
      developer.log(
          '💰 Cache: ${_availableCredits!} créditos (idade: ${now.difference(_lastCheck!).inSeconds}s)');
      return _availableCredits!;
    }

    try {
      // ✅ Verificar conectividade
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        developer
            .log('💰 Sem conexão, usando cache: ${_availableCredits ?? 0}');
        return _availableCredits ?? 0;
      }

      // Buscar do servidor
      developer.log('💰 Buscando créditos do servidor...');
      final credits = await _apiService.getUserCredits();

      // ✅ Processar resposta dentro do try
      if (credits != null) {
        _availableCredits = credits['available_credits'] ?? 0;
        _totalCredits = credits['total_credits'] ?? 0;
        _usedCredits = credits['used_credits'] ?? 0;
        _lastCheck = now;

        developer
            .log('💰 Servidor: ${_availableCredits!} créditos disponíveis');
        return _availableCredits!;
      }

      // Se credits for null, retornar cache ou 0
      developer.log(
          '💰 Resposta nula do servidor, usando cache: ${_availableCredits ?? 0}');
      return _availableCredits ?? 0;
    } catch (e) {
      developer.log('💰 Erro de conectividade: $e');
      return _availableCredits ?? 0;
    }
  }

  /// Obter informações completas dos créditos
  Future<Map<String, int>> getCreditsInfo({bool forceRefresh = false}) async {
    await getAvailableCredits(forceRefresh: forceRefresh);

    return {
      'available': _availableCredits ?? 0,
      'total': _totalCredits ?? 0,
      'used': _usedCredits ?? 0,
    };
  }

  /// Consumir crédito e atualizar cache
  Future<bool> consumeCredit({
    required int studentId,
    required int simuladoId,
    String action = 'simulado_correction',
  }) async {
    developer.log('💳 Tentando consumir crédito...');

    // Verificar se tem créditos antes de consumir
    final available = await getAvailableCredits(forceRefresh: true);
    if (available <= 0) {
      developer.log('💳 Sem créditos disponíveis para consumir');
      return false;
    }

    final success = await _apiService.consumeCredit(
      studentId: studentId,
      simuladoId: simuladoId,
      action: action,
    );

    // Atualizar cache se foi bem-sucedido
    if (success && _availableCredits != null) {
      _availableCredits = _availableCredits! - 1;
      if (_usedCredits != null) {
        _usedCredits = _usedCredits! + 1;
      }
      _lastCheck = DateTime.now();

      developer
          .log('💳 Cache atualizado: ${_availableCredits!} créditos restantes');
    }

    return success;
  }

  /// Comprar créditos via Google Play
  Future<bool> buyCredits(String planId) async {
    try {
      developer.log('🛒 Iniciando compra do plano: $planId');

      // Encontrar o produto no Google Play
      final produto = _comprasService.produtos.firstWhere(
        (p) => p.id == planId,
        orElse: () => throw Exception('Produto não encontrado: $planId'),
      );

      // Iniciar a compra
      await _comprasService.comprarProduto(produto);
      return true;
    } catch (e) {
      developer.log('❌ Erro ao comprar créditos: $e');
      return false;
    }
  }

  /// Obter produtos disponíveis do Google Play
  List<Map<String, dynamic>> getAvailableProducts() {
    final produtos = _comprasService.produtosCredito;

    return creditPlans.map((plan) {
      // Encontrar o produto correspondente do Google Play
      // Corrigido: tipagem explícita e verificação de tipo
      final produto = produtos.whereType<ProdutoCredito>().firstWhere(
            (p) => p.id == plan['id'],
            orElse: () => ProdutoCredito(
              id: '',
              nome: '',
              creditos: 0,
            ),
          );

      return {
        ...plan,
        'googlePlayPrice': produto.preco,
        'available': produto.id.isNotEmpty,
      };
    }).toList();
  }

  /// Limpar cache (usar quando logout ou erro)
  void clearCache() {
    developer.log('🗑️ Limpando cache de créditos');
    _availableCredits = null;
    _totalCredits = null;
    _usedCredits = null;
    _lastCheck = null;
  }

  /// Calcular custo-benefício de um plano
  static double getCostPerCredit(Map<String, dynamic> plan) {
    final credits = plan['credits'] as int;
    final price = plan['price'] as double;
    return price / credits;
  }

  /// Obter plano recomendado baseado no uso
  static Map<String, dynamic> getRecommendedPlan(int monthlyUsage) {
    if (monthlyUsage <= 200) {
      return creditPlans[0]; // Starter
    } else if (monthlyUsage <= 600) {
      return creditPlans[1]; // Professor Ativo
    } else if (monthlyUsage <= 1500) {
      return creditPlans[2]; // Escola Pequena
    } else {
      return creditPlans[3]; // Escola Profissional
    }
  }

  /// Mostrar dialog de créditos insuficientes com opções de compra
  static Future<void> showInsufficientCreditsDialog(
    BuildContext context, {
    VoidCallback? onBuyCredits,
    int currentCredits = 0,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade400, Colors.orange.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Créditos Insuficientes',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Você possui $currentCredits créditos',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text(
                        'Para realizar esta correção, você precisa de pelo menos 1 crédito.',
                        style: TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),

                      // Info box
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.blue.withOpacity(0.3)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.blue[700], size: 20),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Como funciona?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '• 1 crédito = 1 correção de simulado\n'
                              '• Créditos não expiram\n'
                              '• Use quando precisar\n'
                              '• Ideal para escolas e professores',
                              style:
                                  TextStyle(fontSize: 14, color: Colors.blue),
                            ),
                          ],
                        ),
                      ),

                      // Plano em destaque (mais popular)
                      const SizedBox(height: 20),
                      _buildPlanHighlight(),
                    ],
                  ),
                ),

                // Actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      // Botão principal
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            if (onBuyCredits != null) {
                              onBuyCredits();
                            }
                          },
                          icon: const Icon(Icons.shopping_cart, size: 20),
                          label: const Text(
                            'Ver Todos os Planos',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Botão secundário
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'Agora Não',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildPlanHighlight() {
    final popularPlan =
        creditPlans.firstWhere((plan) => plan['popular'] == true);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade50, Colors.green.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'MAIS POPULAR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    popularPlan['name'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${popularPlan['credits']} correções',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'R\$ ${popularPlan['price'].toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  Text(
                    'R\$ ${getCostPerCredit(popularPlan).toStringAsFixed(3)} por correção',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Mostrar dialog com informações dos créditos atuais
  static Future<void> showCreditsInfoDialog(
    BuildContext context, {
    required int available,
    required int total,
    required int used,
    VoidCallback? onBuyCredits,
  }) async {
    final percentage = total > 0 ? (used / total * 100) : 0.0;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 350),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: Colors.blue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Seus Créditos',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Indicador circular
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: percentage / 100,
                          strokeWidth: 8,
                          backgroundColor: Colors.grey.withOpacity(0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            available > 50
                                ? Colors.green
                                : available > 20
                                    ? Colors.orange
                                    : Colors.red,
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$available',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'disponíveis',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Estatísticas
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        Text(
                          '$total',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '$used',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Usados',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Usado',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Botões
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Fechar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          if (onBuyCredits != null) {
                            onBuyCredits();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Comprar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Abrir a tela de loja de créditos
  static Future<void> openCreditStore(BuildContext context) async {
    try {
      // ✅ Usar named route ao invés de import direto
      if (context.mounted) {
        Navigator.pushNamed(context, '/loja-creditos');
      }
    } catch (e) {
      developer.log('❌ Erro ao abrir loja de créditos: $e');

      // Fallback: mostrar um dialog simples
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Loja de Créditos'),
            content: const Text(
                'A loja de créditos está temporariamente indisponível.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Método para facilitar a compra rápida de um plano específico
  Future<bool> quickPurchase(String planId, BuildContext context) async {
    try {
      // Mostrar loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Realizar a compra
      final success = await buyCredits(planId);

      // Fechar loading
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      return success;
    } catch (e) {
      developer.log('❌ Erro na compra rápida: $e');

      // Fechar loading se estiver aberto
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      return false;
    }
  }

  /// Verificar se há produtos pendentes para processar
  Future<void> checkPendingPurchases() async {
    try {
      await _comprasService.carregarProdutos();
      developer.log('✅ Verificação de compras pendentes concluída');
    } catch (e) {
      developer.log('❌ Erro ao verificar compras pendentes: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _comprasService.dispose();
  }
}
