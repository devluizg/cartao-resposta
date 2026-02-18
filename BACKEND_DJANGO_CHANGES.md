# Mudanças Necessárias no Backend Django

## ⚠️ IMPORTANTE: Estas mudanças devem ser feitas no servidor de produção (simuladoapp.com.br)

---

## 1. Criar Endpoint para Completar OAuth e Retornar JWT

**Arquivo:** `simuladoapp_v2/api/views.py`

Adicionar no final do arquivo:

```python
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework import status
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import get_user_model
from django.shortcuts import redirect

User = get_user_model()

@api_view(['GET', 'POST'])
@permission_classes([AllowAny])
def google_auth_complete(request):
    """
    Endpoint para completar autenticação Google OAuth.

    GET: Chamado pelo Django após OAuth bem-sucedido (via redirect)
         - Verifica se usuário está autenticado via sessão Django
         - Gera JWT tokens
         - Redireciona para deep link do app com tokens na URL

    POST: Chamado pelo app para obter tokens (backup method)
          - Valida sessão Django
          - Retorna JWT tokens em JSON
    """
    print("\n=== GOOGLE AUTH COMPLETE ===")
    print(f"Method: {request.method}")
    print(f"User authenticated: {request.user.is_authenticated}")

    # Método GET - Redirecionado pelo Django após OAuth
    if request.method == 'GET':
        if request.user.is_authenticated:
            user = request.user
            print(f"✅ Usuário autenticado via sessão: {user.email}")

            # Gerar JWT tokens
            refresh = RefreshToken.for_user(user)
            access_token = str(refresh.access_token)
            refresh_token = str(refresh)

            # Redirecionar para deep link com tokens
            redirect_url = (
                f"simuladoapp://oauth/callback?"
                f"access={access_token}&"
                f"refresh={refresh_token}&"
                f"email={user.email}"
            )

            print(f"✅ Redirecionando para: {redirect_url[:80]}...")
            return redirect(redirect_url)
        else:
            # Usuário não autenticado
            print("❌ Usuário não autenticado")
            return redirect("simuladoapp://oauth/callback?error=not_authenticated")

    # Método POST - App enviando requisição direta
    if request.method == 'POST':
        if request.user.is_authenticated:
            user = request.user
            print(f"✅ Usuário autenticado: {user.email}")

            # Gerar JWT tokens
            refresh = RefreshToken.for_user(user)

            return Response({
                'access': str(refresh.access_token),
                'refresh': str(refresh),
                'user': {
                    'id': user.id,
                    'email': user.email,
                    'name': user.get_full_name() or user.username,
                }
            }, status=status.HTTP_200_OK)

        print("❌ POST sem autenticação")
        return Response({
            'error': 'Usuário não autenticado'
        }, status=status.HTTP_401_UNAUTHORIZED)
```

---

## 2. Adicionar Rota para o Novo Endpoint

**Arquivo:** `simuladoapp_v2/api/urls.py`

Adicionar o import no topo do arquivo:

```python
from .views import google_auth_complete
```

Adicionar na lista `urlpatterns`:

```python
urlpatterns = [
    # ... rotas existentes ...

    # Google OAuth completion endpoint
    path('auth/google/complete/', google_auth_complete, name='google_auth_complete'),
]
```

---

## 3. Configurar Redirect após OAuth no django-allauth

**Arquivo:** `simuladoapp_v2/simuladoapp/settings.py`

Procurar por `LOGIN_REDIRECT_URL` e modificar/adicionar:

```python
# Redirecionar para endpoint que gera JWT após login social
LOGIN_REDIRECT_URL = '/api/auth/google/complete/'
SOCIALACCOUNT_LOGIN_REDIRECT_URL = '/api/auth/google/complete/'

# Permitir que allauth processe login mesmo sem next parameter
SOCIALACCOUNT_STORE_TOKENS = True
```

---

## 4. Atualizar CORS para Permitir Deep Link Redirect

**Arquivo:** `simuladoapp_v2/simuladoapp/settings.py`

Procurar por `CORS_ALLOWED_ORIGINS` e adicionar:

```python
CORS_ALLOWED_ORIGINS = [
    'https://simuladoapp.com.br',
    'https://www.simuladoapp.com.br',
    # Outros origins existentes...
]

# Adicionar configuração para permitir custom schemes
CORS_ALLOW_ALL_ORIGINS = False  # Manter False por segurança

# Permitir credentials para sessões Django
CORS_ALLOW_CREDENTIALS = True
```

**IMPORTANTE:** Não adicione `simuladoapp://oauth` no `CORS_ALLOWED_ORIGINS` pois CORS não se aplica a custom URL schemes (deep links). O redirect funcionará normalmente.

---

## 5. Verificar Configuração do Google OAuth Client

**Arquivo:** Google Cloud Console

1. Acessar https://console.cloud.google.com/
2. Ir em "APIs & Services" → "Credentials"
3. Editar o OAuth 2.0 Client ID usado pelo app
4. Em "Authorized redirect URIs", adicionar:
   ```
   https://simuladoapp.com.br/accounts/google/login/callback/
   ```

**NOTA:** Não adicione o deep link `simuladoapp://oauth/callback` aqui. O Google só permite HTTPS URIs. O deep link é usado internamente pelo Django para redirecionar de volta ao app.

---

## 6. Testar o Endpoint

### Teste 1: Via Browser (simulando o fluxo)

```bash
# 1. Fazer login manual no Django admin
# Abrir: https://simuladoapp.com.br/admin/
# Fazer login com credenciais de superuser

# 2. Com sessão ativa, acessar o endpoint diretamente
# Abrir: https://simuladoapp.com.br/api/auth/google/complete/
# Deve tentar redirecionar para: simuladoapp://oauth/callback?access=...
```

### Teste 2: Via cURL (método POST)

```bash
# Primeiro fazer login e obter sessionid
curl -X POST https://simuladoapp.com.br/api/token/ \
  -H "Content-Type: application/json" \
  -d '{"email": "seu@email.com", "password": "suasenha"}' \
  -c cookies.txt

# Depois chamar o endpoint com a sessão
curl -X POST https://simuladoapp.com.br/api/auth/google/complete/ \
  -H "Content-Type: application/json" \
  -b cookies.txt
```

**Resposta esperada:**
```json
{
  "access": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "user": {
    "id": 1,
    "email": "user@example.com",
    "name": "User Name"
  }
}
```

### Teste 3: Logs do Django

Adicionar no `settings.py` para debug:

```python
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
        },
    },
    'loggers': {
        'api': {
            'handlers': ['console'],
            'level': 'DEBUG',
        },
    },
}
```

Verificar logs com:
```bash
# No servidor
tail -f /var/log/gunicorn/error.log
# ou
journalctl -u gunicorn -f
```

---

## 7. Deploy

Após fazer as mudanças:

```bash
# 1. Commit das mudanças
git add .
git commit -m "Add Google OAuth JWT endpoint for mobile app"

# 2. Push para repositório
git push origin main

# 3. No servidor (via SSH)
cd /path/to/simuladoapp_v2
git pull origin main

# 4. Reiniciar Gunicorn
sudo systemctl restart gunicorn

# 5. Verificar status
sudo systemctl status gunicorn

# 6. Verificar logs
sudo journalctl -u gunicorn -n 50
```

---

## Checklist de Verificação

- [ ] Endpoint `google_auth_complete` criado em `api/views.py`
- [ ] Rota adicionada em `api/urls.py`
- [ ] `LOGIN_REDIRECT_URL` configurado em `settings.py`
- [ ] `SOCIALACCOUNT_LOGIN_REDIRECT_URL` configurado em `settings.py`
- [ ] CORS configurado corretamente
- [ ] Google OAuth redirect URI atualizado no Google Cloud Console
- [ ] Código commitado e pushed
- [ ] Servidor reiniciado
- [ ] Teste manual via browser bem-sucedido
- [ ] Logs mostrando funcionamento correto

---

## Troubleshooting

### Problema: Redirect não funciona

**Solução:** Verificar se `SOCIALACCOUNT_LOGIN_REDIRECT_URL` está configurado corretamente.

```bash
# No Django shell
python manage.py shell
>>> from django.conf import settings
>>> print(settings.SOCIALACCOUNT_LOGIN_REDIRECT_URL)
```

### Problema: CORS error

**Solução:** CORS não afeta redirects HTTP. Se aparecer erro de CORS, pode ser em outro lugar (API calls). Verificar configuração do CORS.

### Problema: Tokens não são gerados

**Solução:** Verificar se `rest_framework_simplejwt` está instalado:

```bash
pip list | grep simplejwt
```

Se não estiver:
```bash
pip install djangorestframework-simplejwt
```

### Problema: Usuário não autenticado no GET

**Solução:** Verificar se a sessão Django está ativa. O OAuth do Google deve criar uma sessão automaticamente. Verificar `MIDDLEWARE` em `settings.py`:

```python
MIDDLEWARE = [
    # ...
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    # ...
]
```

---

## Próximos Passos Após Implementação

1. Testar fluxo completo no app Flutter (ver FLUTTER_TESTING.md)
2. Monitorar logs para verificar taxa de sucesso
3. Adicionar analytics/métricas para login com Google
4. Implementar tratamento de erros mais robusto
5. Adicionar testes automatizados

---

## Notas de Segurança

- ✅ JWT tokens são gerados server-side (seguro)
- ✅ Tokens são transmitidos via HTTPS redirect (seguro)
- ✅ Deep link usa custom scheme (não interceptável por outros apps se configurado corretamente)
- ⚠️ Tokens aparecem na URL do deep link (temporariamente). O app deve limpar o histórico de navegação
- ✅ CORS configurado para permitir apenas origins confiáveis

---

**Data de criação:** 2026-02-16
**Versão:** 1.0
