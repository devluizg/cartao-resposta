# Configuração do Google Sign In - SimuladoApp Fluatenci

## Status Atual
✅ Google Sign In está integrado e funcional na página de login

## Configuração Necessária

### 1. Android Setup

#### 1.1 Adicionar Google Services Gradle
Abra `android/build.gradle` e adicione no final do arquivo:

```gradle
buildscript {
    dependencies {
        // ... outras dependências
        classpath 'com.google.gms:google-services:4.3.15'
    }
}
```

#### 1.2 Aplicar Plugin
Abra `android/app/build.gradle` e adicione no final:

```gradle
apply plugin: 'com.google.gms.google-services'
```

#### 1.3 Adicionar SHA-1 Fingerprint
Para usar Google Sign In, você precisa registrar o SHA-1 do seu app no Google Cloud Console.

Execute:
```bash
cd android && ./gradlew signingReport
```

Copie o SHA-1 debug e adicione em Google Cloud Console > Credenciais.

#### 1.4 OAuth 2.0 Client ID
O Client ID já está configurado no código:
```
272849436889-4tpr9rckevmp73mevpfbqhbgquqt91qc.apps.googleusercontent.com
```

### 2. iOS Setup

#### 2.1 Adicionar URL Scheme
Abra `ios/Runner/Info.plist` e adicione:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.272849436889-4tpr9rckevmp73mevpfbqhbgquqt91qc</string>
        </array>
    </dict>
</array>
```

#### 2.2 CocoaPods
Rode na pasta iOS:
```bash
cd ios && pod update && cd ..
```

### 3. Verificação

Execute o app com:
```bash
flutter run
```

Clique no botão "Entrar com Google" para testar. Após o login, o app abrirá https://simuladoapp.com.br/

## Comportamento do App

### Fluxo de Login com Google
1. Usuário clica "Entrar com Google"
2. Abre o seletor de conta Google
3. Após seleção, redireciona para simuladoapp.com.br
4. Você pode adicionar lógica de autenticação no backend

### Links do App
- **"Criar conta"** → https://simuladoapp.com.br/register
- **"Visitar SimuladoApp"** → https://simuladoapp.com.br/

## Personalização

Se precisar alterar o URL de redirecionamento após Google Sign In, edite em `login_screen.dart`:

```dart
Future<void> _loginWithGoogle() async {
  // ...
  // Linha 77:
  await _launchWebsite('https://simuladoapp.com.br/');
}
```

## Troubleshooting

### Google Sign In não funciona
1. Verifique se as dependências foram instaladas: `flutter pub get`
2. Limpe o build: `flutter clean && flutter pub get`
3. Verifique o SHA-1 no Google Cloud Console

### URL Launcher não abre links
1. Verifique se url_launcher está no pubspec.yaml
2. Teste com um URL simples: `https://google.com`

## Próximos Passos

1. Configurar autenticação backend para validar tokens do Google
2. Armazenar token de autenticação localmente
3. Sincronizar dados do usuário com SimuladoApp
4. Adicionar logout
