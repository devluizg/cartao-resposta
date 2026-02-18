"""
Models do app Catálogo
Gestão de Produtos, Serviços, Categorias e Controle de Estoque
"""
from django.db import models
from django.core.validators import MinValueValidator
from decimal import Decimal


class Categoria(models.Model):
    """
    Categorias para organizar produtos e serviços
    Ex: Serviços de Estética, Produtos de Limpeza, Insumos, etc.
    """
    nome = models.CharField(
        max_length=100,
        unique=True,
        verbose_name="Nome da Categoria"
    )
    
    descricao = models.TextField(
        verbose_name="Descrição",
        blank=True
    )
    
    ativa = models.BooleanField(
        default=True,
        verbose_name="Categoria Ativa"
    )
    
    criado_em = models.DateTimeField(
        auto_now_add=True,
        verbose_name="Criado em"
    )
    
    class Meta:
        verbose_name = "Categoria"
        verbose_name_plural = "Categorias"
        ordering = ['nome']
    
    def __str__(self):
        return self.nome


class ItemCatalogo(models.Model):
    """
    Catálogo unificado de Produtos e Serviços
    """
    TIPO_CHOICES = [
        ('PRODUTO', 'Produto Físico'),
        ('SERVICO', 'Serviço/Mão de Obra'),
    ]
    
    tipo = models.CharField(
        max_length=10,
        choices=TIPO_CHOICES,
        verbose_name="Tipo"
    )
    
    categoria = models.ForeignKey(
        Categoria,
        on_delete=models.PROTECT,
        related_name='itens',
        verbose_name="Categoria"
    )
    
    nome = models.CharField(
        max_length=200,
        verbose_name="Nome do Item"
    )
    
    descricao = models.TextField(
        verbose_name="Descrição Detalhada",
        blank=True
    )
    
    # Precificação
    preco_venda = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
        verbose_name="Preço de Venda (R$)",
        help_text="Preço cobrado do cliente"
    )
    
    custo_base = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
        verbose_name="Custo Base (R$)",
        help_text="Quanto custa para você (produto) ou tempo (serviço)"
    )
    
    # Estoque (apenas para produtos)
    estoque_atual = models.IntegerField(
        default=0,
        verbose_name="Estoque Atual",
        help_text="Quantidade disponível (deixe 0 para serviços)"
    )
    
    estoque_minimo = models.IntegerField(
        default=0,
        verbose_name="Estoque Mínimo",
        help_text="Alerta quando atingir este valor"
    )
    
    unidade_medida = models.CharField(
        max_length=20,
        default='UN',
        verbose_name="Unidade de Medida",
        help_text="Ex: UN, KG, L, ML, M"
    )
    
    # Visibilidade
    visivel_no_site = models.BooleanField(
        default=False,
        verbose_name="Visível no Site",
        help_text="Aparece na vitrine pública?"
    )
    
    visivel_no_zap = models.BooleanField(
        default=True,
        verbose_name="Visível no WhatsApp",
        help_text="Aparece no catálogo do bot?"
    )
    
    # Mídia
    imagem = models.ImageField(
        upload_to='catalogo/',
        verbose_name="Imagem",
        blank=True,
        null=True
    )
    
    # Controle
    ativo = models.BooleanField(
        default=True,
        verbose_name="Item Ativo"
    )
    
    destaque = models.BooleanField(
        default=False,
        verbose_name="Item em Destaque",
        help_text="Aparece primeiro nas listagens"
    )
    
    criado_em = models.DateTimeField(
        auto_now_add=True,
        verbose_name="Criado em"
    )
    
    atualizado_em = models.DateTimeField(
        auto_now=True,
        verbose_name="Atualizado em"
    )
    
    class Meta:
        verbose_name = "Item do Catálogo"
        verbose_name_plural = "Itens do Catálogo"
        ordering = ['-destaque', 'nome']
        indexes = [
            models.Index(fields=['tipo', 'ativo']),
            models.Index(fields=['visivel_no_site', 'ativo']),
        ]
    
    def __str__(self):
        return f"[{self.get_tipo_display()}] {self.nome}"
    
    def margem_lucro(self):
        """Calcula a margem de lucro em percentual"""
        if self.custo_base > 0:
            return ((self.preco_venda - self.custo_base) / self.custo_base) * 100
        return 0
    
    def estoque_baixo(self):
        """Verifica se o estoque está abaixo do mínimo"""
        if self.tipo == 'PRODUTO':
            return self.estoque_atual <= self.estoque_minimo
        return False
    
    estoque_baixo.boolean = True
    estoque_baixo.short_description = 'Estoque Baixo?'


class ConsumoInsumo(models.Model):
    """
    Ficha Técnica: Define quais produtos um serviço consome
    Ex: O serviço "Lavagem Completa" consome:
        - 50ml de Shampoo
        - 30ml de Cera
        - 1 Pano de Microfibra
    """
    servico_pai = models.ForeignKey(
        ItemCatalogo,
        on_delete=models.CASCADE,
        related_name='insumos_necessarios',
        limit_choices_to={'tipo': 'SERVICO'},
        verbose_name="Serviço"
    )
    
    produto_filho = models.ForeignKey(
        ItemCatalogo,
        on_delete=models.PROTECT,
        related_name='usado_em_servicos',
        limit_choices_to={'tipo': 'PRODUTO'},
        verbose_name="Produto/Insumo"
    )
    
    quantidade = models.DecimalField(
        max_digits=10,
        decimal_places=3,
        validators=[MinValueValidator(Decimal('0.001'))],
        verbose_name="Quantidade Consumida",
        help_text="Ex: 50 (se a unidade for ML), 1 (se for UN)"
    )
    
    criado_em = models.DateTimeField(
        auto_now_add=True,
        verbose_name="Criado em"
    )
    
    class Meta:
        verbose_name = "Consumo de Insumo"
        verbose_name_plural = "Consumos de Insumos"
        unique_together = ['servico_pai', 'produto_filho']
    
    def __str__(self):
        return f"{self.servico_pai.nome} usa {self.quantidade} {self.produto_filho.unidade_medida} de {self.produto_filho.nome}"
    
    def custo_total(self):
        """Calcula o custo total deste insumo no serviço"""
        # Custo unitário do produto * quantidade consumida
        return self.produto_filho.custo_base * self.quantidade