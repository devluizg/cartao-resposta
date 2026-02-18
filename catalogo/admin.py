"""
Configuração do Django Admin para o app Catálogo
"""
from django.contrib import admin
from django.utils.html import format_html
from .models import Categoria, ItemCatalogo, ConsumoInsumo


@admin.register(Categoria)
class CategoriaAdmin(admin.ModelAdmin):
    list_display = ('nome', 'ativa', 'total_itens', 'criado_em')
    list_filter = ('ativa', 'criado_em')
    search_fields = ('nome', 'descricao')
    readonly_fields = ('criado_em',)
    
    def total_itens(self, obj):
        return obj.itens.filter(ativo=True).count()
    total_itens.short_description = 'Total de Itens'


class ConsumoInsumoInline(admin.TabularInline):
    """
    Permite adicionar insumos direto na tela de edição do serviço
    """
    model = ConsumoInsumo
    fk_name = 'servico_pai'
    extra = 1
    autocomplete_fields = ['produto_filho']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        return qs.select_related('produto_filho')


@admin.register(ItemCatalogo)
class ItemCatalogoAdmin(admin.ModelAdmin):
    list_display = (
        'nome',
        'tipo_badge',
        'categoria',
        'preco_venda_formatado',
        'estoque_atual',
        'estoque_baixo',
        'visivel_site',
        'visivel_zap',
        'ativo'
    )
    list_filter = ('tipo', 'categoria', 'ativo', 'visivel_no_site', 'visivel_no_zap', 'destaque')
    search_fields = ('nome', 'descricao')
    readonly_fields = ('criado_em', 'atualizado_em', 'margem_lucro_display')
    autocomplete_fields = ['categoria']
    list_editable = ('ativo',)
    
    fieldsets = (
        ('Informações Básicas', {
            'fields': ('tipo', 'categoria', 'nome', 'descricao', 'imagem')
        }),
        ('Precificação', {
            'fields': ('preco_venda', 'custo_base', 'margem_lucro_display')
        }),
        ('Estoque (Apenas Produtos)', {
            'fields': ('estoque_atual', 'estoque_minimo', 'unidade_medida'),
            'classes': ('collapse',)
        }),
        ('Visibilidade', {
            'fields': ('ativo', 'destaque', 'visivel_no_site', 'visivel_no_zap')
        }),
        ('Controle', {
            'fields': ('criado_em', 'atualizado_em'),
            'classes': ('collapse',)
        }),
    )
    
    # Adicionar inline apenas para serviços
    def get_inlines(self, request, obj=None):
        if obj and obj.tipo == 'SERVICO':
            return [ConsumoInsumoInline]
        return []
    
    def tipo_badge(self, obj):
        color = 'green' if obj.tipo == 'SERVICO' else 'blue'
        return format_html(
            '<span style="background-color: {}; color: white; padding: 3px 10px; border-radius: 3px;">{}</span>',
            color,
            obj.get_tipo_display()
        )
    tipo_badge.short_description = 'Tipo'
    
    def preco_venda_formatado(self, obj):
        return f"R$ {obj.preco_venda:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')
    preco_venda_formatado.short_description = 'Preço'
    preco_venda_formatado.admin_order_field = 'preco_venda'
    
    def margem_lucro_display(self, obj):
        margem = obj.margem_lucro()
        color = 'green' if margem > 50 else 'orange' if margem > 20 else 'red'
        return format_html(
            '<span style="color: {}; font-weight: bold;">{:.1f}%</span>',
            color,
            margem
        )
    margem_lucro_display.short_description = 'Margem de Lucro'
    
    def visivel_site(self, obj):
        return obj.visivel_no_site
    visivel_site.boolean = True
    visivel_site.short_description = 'Site'
    
    def visivel_zap(self, obj):
        return obj.visivel_no_zap
    visivel_zap.boolean = True
    visivel_zap.short_description = 'WhatsApp'
    
    # Ações em lote
    actions = ['marcar_destaque', 'desmarcar_destaque', 'ativar_no_site']
    
    def marcar_destaque(self, request, queryset):
        count = queryset.update(destaque=True)
        self.message_user(request, f'{count} item(ns) marcado(s) como destaque.')
    marcar_destaque.short_description = "Marcar como destaque"
    
    def desmarcar_destaque(self, request, queryset):
        count = queryset.update(destaque=False)
        self.message_user(request, f'{count} item(ns) desmarcado(s) de destaque.')
    desmarcar_destaque.short_description = "Desmarcar destaque"
    
    def ativar_no_site(self, request, queryset):
        count = queryset.update(visivel_no_site=True)
        self.message_user(request, f'{count} item(ns) agora visível(is) no site.')
    ativar_no_site.short_description = "Ativar no site"


@admin.register(ConsumoInsumo)
class ConsumoInsumoAdmin(admin.ModelAdmin):
    list_display = ('servico_pai', 'produto_filho', 'quantidade', 'custo_total_display', 'criado_em')
    list_filter = ('servico_pai__categoria', 'criado_em')
    search_fields = ('servico_pai__nome', 'produto_filho__nome')
    autocomplete_fields = ['servico_pai', 'produto_filho']
    
    def custo_total_display(self, obj):
        return f"R$ {obj.custo_total():,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')
    custo_total_display.short_description = 'Custo Total'