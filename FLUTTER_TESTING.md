# Guia de Teste - Login com Google OAuth (Flutter)

## 📱 Mudanças Implementadas no App Flutter

### Arquivos Modificados:
- ✅ `pubspec.yaml` - Adicionada dependência `flutter_web_auth: ^0.5.0`
- ✅ `android/app/src/main/AndroidManifest.xml` - Configurado deep link `simuladoapp://oauth/callback`
- ✅ `ios/Runner/Info.plist` - Configurado URL scheme `simuladoapp`
- ✅ `lib/screens/login_screen.dart` - Novo método OAuth usando navegador do sistema
- ✅ `lib/screens/google_auth_webview.dart` - DELETADO (não usado mais)

### Como Funciona Agora:

**ANTES (com WebView - BLOQUEADO pelo Google):**
```
App → WebView embutido → Google bloqueia (403 error)
```

**AGORA (com flutter_web_auth - FUNCIONA):**
```
1. App → Navegador do sistema (Chrome/Safari)
2. Google OAuth → Usuário faz login
3. Django → Gera JWT tokens
4. Redirect → simuladoapp://oauth/callback?access=XXX&refresh=YYY
5. App → Captura deep link, salva tokens, navega para SelectionScreen
```

---

## 🔧 Comandos de Setup

### 1. Instalar Dependências

```bash
cd /home/luiz/cartao-resposta/leitor_cartao
flutter pub get
```

**Output esperado:**
```
Running "flutter pub get" in leitor_cartao...
Resolving dependencies...
+ flutter_web_auth 0.5.0
...
Got dependencies!
```

### 2. Limpar Build Anterior

```bash
flutter clean
```

### 3. Verificar Configuração do Projeto

```bash
flutter doctor -v
```

Verificar:
- ✅ Flutter SDK instalado
- ✅ Android toolchain configurado
- ✅ Dispositivo/emulador conectado

---

## 📱 Teste em Android

### 1. Compilar e Instalar

```bash
# Modo debug (mais rápido, com hot reload)
flutter run

# Ou modo release (mais próximo da versão final)
flutter build apk --release
flutter install
```

### 2. Testar Deep Link Manualmente (Antes de testar OAuth)

```bash
# Com app aberto, executar:
adb shell am start -a android.intent.action.VIEW \
  -d "simuladoapp://oauth/callback?access=TEST_ACCESS&refresh=TEST_REFRESH&email=test@example.com"
```

**Resultado esperado:**
- App deve receber o deep link
- Logs devem mostrar:
  ```
  ✅ Callback recebido: simuladoapp://oauth/callback?access=TEST_ACCESS...
  Access Token: TEST_ACCESS
  Refresh Token: TEST_REFRESH
  Email: test@example.com
  ```

### 3. Testar Fluxo Completo de OAuth

**Pré-requisito:** Backend Django deve estar com as mudanças implementadas (ver BACKEND_DJANGO_CHANGES.md)

**Passos:**
1. Abrir app
2. Clicar em "Entrar com Google"
3. **VERIFICAR:** Navegador do sistema (Chrome) deve abrir (NÃO WebView)
4. Fazer login com conta Google
5. **VERIFICAR:** Após login, deve voltar ao app automaticamente
6. **VERIFICAR:** App deve navegar para SelectionScreen

**Logs esperados no Flutter:**
```
=== INICIANDO LOGIN COM GOOGLE (via Sistema) ===
🌐 Abrindo navegador do sistema...
Auth URL: https://simuladoapp.com.br/accounts/google/login/?process=login
Callback URL Scheme: simuladoapp
✅ Callback recebido: simuladoapp://oauth/callback?access=eyJ...&refresh=eyJ...&email=user@example.com
Access Token: eyJ0eXAiOiJKV1QiLCJh...
Refresh Token: eyJ0eXAiOiJKV1QiLCJh...
Email: user@example.com
✅ Tokens salvos com sucesso!
✅ Navegando para SelectionScreen...
```

### 4. Verificar Tokens Salvos

```bash
# No Android Studio > Device File Explorer:
# /data/data/com.example.leitor_cartao/shared_prefs/

# Ou via adb:
adb shell run-as com.example.leitor_cartao cat shared_prefs/FlutterSecureStorage.xml
```

Deve conter:
- `access_token`: JWT access token
- `refresh_token`: JWT refresh token

---

## 🍎 Teste em iOS

### 1. Abrir no Xcode

```bash
cd /home/luiz/cartao-resposta/leitor_cartao
open ios/Runner.xcworkspace
```

### 2. Verificar URL Scheme Configurado

No Xcode:
1. Selecionar projeto "Runner"
2. Aba "Info"
3. Expandir "URL Types"
4. **VERIFICAR:** Deve ter entry com:
   - Identifier: `com.example.leitor_cartao`
   - URL Schemes: `simuladoapp`

### 3. Compilar e Executar

```bash
flutter run -d ios
```

Ou pelo Xcode: Product → Run (Cmd+R)

### 4. Testar Deep Link no iOS

```bash
# Com simulador aberto:
xcrun simctl openurl booted "simuladoapp://oauth/callback?access=TEST_ACCESS&refresh=TEST_REFRESH&email=test@example.com"
```

### 5. Testar Fluxo Completo

Mesmos passos do Android (seção anterior).

**IMPORTANTE iOS:** Na primeira vez que usar o deep link, iOS pode pedir permissão para abrir o app. Clicar em "Abrir".

---

## 🐛 Troubleshooting

### Problema 1: "Package flutter_web_auth not found"

**Solução:**
```bash
flutter clean
flutter pub get
flutter pub upgrade
```

### Problema 2: Deep link não funciona no Android

**Causa possível:** AndroidManifest.xml não foi atualizado corretamente.

**Verificar:**
```bash
cat leitor_cartao/android/app/src/main/AndroidManifest.xml | grep -A 10 "simuladoapp"
```

**Output esperado:**
```xml
<data
    android:scheme="simuladoapp"
    android:host="oauth"
    android:pathPrefix="/callback" />
```

**Solução:** Se não aparecer, o arquivo não foi atualizado. Verificar BACKEND_DJANGO_CHANGES.md e reaplicar mudanças.

### Problema 3: Deep link não funciona no iOS

**Causa possível:** Info.plist não foi atualizado.

**Verificar:**
```bash
cat leitor_cartao/ios/Runner/Info.plist | grep -A 10 "CFBundleURLTypes"
```

**Output esperado:**
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>simuladoapp</string>
        </array>
    </dict>
</array>
```

### Problema 4: App abre navegador mas não volta ao app

**Causas possíveis:**
1. Backend Django não está redirecionando corretamente
2. Deep link URL está incorreta
3. Tokens não estão sendo gerados

**Debug:**

1. Verificar URL no navegador após login:
   - Deve redirecionar para: `simuladoapp://oauth/callback?access=...`
   - Se ficar em página branca ou erro 404, problema é no backend

2. Verificar logs do Django:
   ```bash
   # No servidor
   tail -f /var/log/gunicorn/error.log
   ```

3. Verificar endpoint Django manualmente:
   ```bash
   # Fazer login manual no Django admin primeiro
   # Depois acessar: https://simuladoapp.com.br/api/auth/google/complete/
   ```

### Problema 5: "Error: not_authenticated" no callback

**Causa:** Sessão Django não foi criada após OAuth.

**Debug:**
1. Verificar configuração `SOCIALACCOUNT_LOGIN_REDIRECT_URL` no Django
2. Verificar se middleware de sessão está ativo
3. Verificar logs do django-allauth

**Solução temporária:** Fazer login manual no site primeiro, depois testar OAuth.

### Problema 6: Google ainda bloqueia com "disallowed_useragent"

**Causa:** App ainda está usando WebView em algum lugar.

**Verificar:**
```bash
# Verificar se google_auth_webview.dart foi deletado
ls leitor_cartao/lib/screens/google_auth_webview.dart
```

**Output esperado:**
```
ls: cannot access 'leitor_cartao/lib/screens/google_auth_webview.dart': No such file or directory
```

**Verificar se login_screen.dart foi atualizado:**
```bash
grep "flutter_web_auth" leitor_cartao/lib/screens/login_screen.dart
```

**Output esperado:**
```dart
import 'package:flutter_web_auth/flutter_web_auth.dart';
final result = await FlutterWebAuth.authenticate(
```

### Problema 7: Build falha com erro de dependência

**Erro comum:**
```
Error: The plugin flutter_web_auth requires a higher Android SDK version
```

**Solução:**
Editar `android/app/build.gradle`:
```gradle
android {
    defaultConfig {
        minSdkVersion 21  // Ou maior
        targetSdkVersion 33
    }
}
```

### Problema 8: Hot reload não funciona após mudanças

**Causa:** Mudanças no AndroidManifest.xml e Info.plist requerem rebuild completo.

**Solução:**
```bash
flutter clean
flutter run
```

---

## ✅ Checklist de Teste Completo

### Pré-requisitos:
- [ ] Backend Django com mudanças implementadas
- [ ] `flutter pub get` executado com sucesso
- [ ] App compilado sem erros
- [ ] Dispositivo/emulador conectado

### Testes Funcionais:

#### Android:
- [ ] Deep link manual funciona (`adb shell am start...`)
- [ ] Botão "Entrar com Google" abre navegador Chrome (não WebView)
- [ ] Login com Google funciona
- [ ] App volta automaticamente após login
- [ ] Tokens são salvos (verificar logs)
- [ ] Navegação para SelectionScreen funciona
- [ ] Usuário consegue acessar funcionalidades do app

#### iOS:
- [ ] Deep link manual funciona (`xcrun simctl openurl...`)
- [ ] Botão "Entrar com Google" abre Safari (não WebView)
- [ ] Login com Google funciona
- [ ] App volta automaticamente após login
- [ ] Tokens são salvos (verificar logs)
- [ ] Navegação para SelectionScreen funciona
- [ ] Usuário consegue acessar funcionalidades do app

#### Casos de Erro:
- [ ] Cancelar login no Google (voltar ao app sem autenticar)
- [ ] Sem internet durante OAuth (mensagem de erro apropriada)
- [ ] Backend offline (mensagem de erro apropriada)
- [ ] Token inválido/expirado (refresh token funciona)

---

## 📊 Métricas de Sucesso

Para considerar a implementação bem-sucedida:

1. **Taxa de sucesso OAuth:** > 95%
   - Medido por: número de logins completos / número de tentativas

2. **Tempo médio de login:** < 10 segundos
   - Do clique em "Entrar com Google" até SelectionScreen

3. **Taxa de erro 403:** 0%
   - Nenhum erro "disallowed_useragent" deve aparecer

4. **Taxa de volta ao app:** 100%
   - Todos os logins bem-sucedidos devem voltar ao app

---

## 🔍 Logs Importantes

### Onde verificar logs:

**Flutter (console):**
```bash
flutter run
# Ou
flutter logs
```

**Android (logcat):**
```bash
adb logcat -s flutter
```

**iOS (Xcode):**
View → Debug Area → Activate Console (Cmd+Shift+Y)

### Logs de sucesso esperados:

```
I/flutter ( 1234): === INICIANDO LOGIN COM GOOGLE (via Sistema) ===
I/flutter ( 1234): 🌐 Abrindo navegador do sistema...
I/flutter ( 1234): Auth URL: https://simuladoapp.com.br/accounts/google/login/?process=login
I/flutter ( 1234): Callback URL Scheme: simuladoapp
I/flutter ( 1234): ✅ Callback recebido: simuladoapp://oauth/callback?access=eyJ0eXAi...
I/flutter ( 1234): Access Token: eyJ0eXAiOiJKV1QiLCJh...
I/flutter ( 1234): Refresh Token: eyJ0eXAiOiJKV1QiLCJh...
I/flutter ( 1234): Email: user@example.com
I/flutter ( 1234): ✅ Tokens salvos com sucesso!
I/flutter ( 1234): ✅ Navegando para SelectionScreen...
```

### Logs de erro para investigar:

```
❌ Erro no login com Google: PlatformException(CANCELED, User cancelled login, null, null)
→ Usuário cancelou login (comportamento esperado)

❌ Erro no login com Google: Error: redirect_uri_mismatch
→ Google OAuth Client não tem redirect URI configurado corretamente

❌ Tokens não recebidos no callback
→ Backend não gerou/retornou tokens corretamente

❌ Erro ao fazer login com Google. Tente novamente.
→ Erro genérico (verificar stack trace completo)
```

---

## 📝 Próximos Passos

Após testes bem-sucedidos:

1. [ ] Testar em dispositivos físicos (não apenas emuladores)
2. [ ] Testar com diferentes contas Google
3. [ ] Testar em diferentes versões do Android (21+)
4. [ ] Testar em diferentes versões do iOS (12+)
5. [ ] Adicionar analytics para rastrear uso
6. [ ] Adicionar testes automatizados (integration tests)
7. [ ] Preparar para release (assinar APK/IPA)
8. [ ] Submeter para lojas (Google Play / App Store)

---

**Data de criação:** 2026-02-16
**Versão:** 1.0
