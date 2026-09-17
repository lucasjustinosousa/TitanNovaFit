# TitanNova Fit — Documento de Arquitetura e Engenharia

Este documento formaliza a arquitetura do projeto **TitanNova Fit**, definindo os papéis das implementações Web (PWA) e Mobile (Flutter), a integridade dos projetos nativos e a estratégia de evolução técnica modular.

---

## 1. Definição da Implementação Principal

| Componente | Nível | Stack Tecnológica | Finalidade |
| :--- | :--- | :--- | :--- |
| **Web / PWA** | **Principal (Fonte da Verdade & Produção)** | HTML5, CSS3 Vanilla, JavaScript Vanilla, Supabase JS v2, Service Worker | Aplicação oficial em produção servida via Vercel em `https://titannovafit.com.br`. Define a fonte da verdade para regras de negócio, UX limpa, fluxos de treino em 1 toque, segurança LGPD e offline-first com sincronização resiliente. |
| **Serverless API** | **Principal (Backend & Governança)** | Node.js Serverless Functions (`/api/*` na Vercel) | Endpoints seguros de retaguarda para gestão administrativa (`/api/users`), treinadores (`/api/trainers`), assinaturas (`/api/subscriptions`), termos legais (`/api/legal`) e catálogo de exercícios (`/api/exercises`). |
| **Flutter Mobile** | **Secundário (Paridade com PWA)** | Flutter 3.16+, Dart 3.0+, SQLite (sqflite) | Aplicativo cliente nativo complementar para empacotamento em APK/AAB (Android) e IPA (iOS). Segue a esteira de paridade com o PWA, adotando os mesmos estados de autenticação limpos, bloqueio para CREF pendente e foco dominante no próximo treino. |

> **Diretriz Arquitetural Permanente**: Qualquer nova funcionalidade, regra comercial ou ajuste de experiência deve ser primeiramente consolidado e testado no **PWA (`app.html` e `index.html`)** antes de ser transposto para o cliente nativo Flutter (`lib/`).

---

## 2. Inventário e Integridade dos Projetos Nativos (Android & iOS)

### 2.1 Android (`android/`)
* **Arquivos presentes**:
  - `android/build.gradle` (Configuração raiz do Gradle)
  - `android/gradle.properties` (Parâmetros de JVM e AndroidX)
  - `android/settings.gradle` (Inclusão do módulo `:app`)
  - `android/app/build.gradle` (Plugins, defaultConfig, compileSdk, buildTypes)
  - `android/app/src/main/AndroidManifest.xml` (Permissões de rede, áudio, vibração, boot)
  - `android/app/src/main/kotlin/com/jtech/fit/MainActivity.kt` (Ponto de entrada Kotlin)
  - `android/app/src/main/res/drawable/launch_background.xml` e `values/styles.xml`
* **Arquivos ausentes (Template padrão Flutter)**:
  - `android/gradlew` e `android/gradlew.bat` (Gradle wrapper executável)
  - `android/gradle/wrapper/gradle-wrapper.jar` e `gradle-wrapper.properties`
  - Pastas de ícones mipmap em `res/mipmap-*`
* **Procedimento para recomposição completa**:
  Em uma estação com Flutter SDK instalado, executar na raiz do repositório:
  ```bash
  flutter create . --platforms=android
  ```

### 2.2 iOS (`ios/`)
* **Arquivos presentes**:
  - `ios/Podfile` (Configuração CocoaPods de dependências)
  - `ios/Runner/AppDelegate.swift` (Ciclo de vida da aplicação iOS)
  - `ios/Runner/Info.plist` (Configurações do bundle, permissões)
  - `ios/Runner/Runner-Bridging-Header.h`
* **Arquivos ausentes (Template padrão Xcode)**:
  - `ios/Runner.xcodeproj/project.pbxproj` (Descritor do projeto Xcode)
  - `ios/Runner.xcworkspace`
  - `ios/Runner/Assets.xcassets` (AppIcon, LaunchImage)
  - `ios/Runner/Base.lproj/LaunchScreen.storyboard` e `Main.storyboard`
* **Procedimento para recomposição completa**:
  Em ambiente macOS com Flutter SDK instalado:
  ```bash
  flutter create . --platforms=ios
  cd ios && pod install
  ```

### 2.3 Gestão de Dependências Flutter (`pubspec.lock`)
O arquivo `pubspec.yaml` declara com precisão as dependências e restrições do SDK. O arquivo de trava `pubspec.lock` deve ser gerado pelo pipeline de build nativo ou desenvolvedor executando `flutter pub get`.

---

## 3. Gestão de Assets do Flutter
Os diretórios de assets registrados no `pubspec.yaml` foram formalizados na estrutura física:
- `assets/icons/` — Ícones do app e do PWA (favicon, logo, icon-192, icon-512)
- `assets/images/` — Imagens ilustrativas e banners (preservado com `.gitkeep`)
- `assets/videos/` — Vídeos demonstrativos de execução de exercícios (preservado com `.gitkeep`)
- `assets/sounds/` — Efeitos sonoros para o cronômetro de descanso (preservado com `.gitkeep`)

---

## 4. Estratégia de Modularização Progressiva do `app.html`

O arquivo `app.html` opera como uma Single Page Application (SPA) autossuficiente e offline-first. Para garantir manutenibilidade futura sem arriscar a estabilidade de produção, a modularização deve seguir a seguinte esteira planejada:

```
TitanNovaFit/
├── web/
│   ├── index.html           # Landing page pública institucional
│   └── app.html             # Shell da SPA e montagem dos componentes
├── js/                      # (Evolução Modular ES6)
│   ├── modules/
│   │   ├── auth.js          # Fluxo de login, cadastro e sessão Supabase
│   │   ├── timer.js         # Cronômetro de descanso e formatação de tempo
│   │   ├── workouts.js      # Gerenciamento de fichas e execução de séries
│   │   ├── exercises.js     # Biblioteca de exercícios e cache local
│   │   ├── admin.js         # Painel administrativo e governança
│   │   ├── sync.js          # Sincronização offline e fila de transações
│   │   └── security.js      # Sanitização centralizada de HTML / XSS
│   └── main.js              # Inicializador da aplicação
```

### Regras para refatoração:
1. **Zero regressão**: Manter compatibilidade com o Service Worker (`sw.js`).
2. **Separação lógica antes de física**: Funções puras (como `formatSecondsToMMSS`) são desacopladas e testadas unitariamente antes da separação em módulos de arquivo.
3. **CSP Estrita**: Substituição gradual de manipuladores inline (`onclick=...`) por escutadores de evento (`addEventListener`) utilizando atributos `data-*`.

---

## 5. Matriz de Segurança e Conformidade

1. **Credenciais**: Nenhuma chave `service_role` versionada no código. Operações privilegiadas utilizam estritamente `SUPABASE_SERVICE_ROLE_KEY` nas Serverless Functions na Vercel.
2. **Row Level Security (RLS)**: Isolamento estrito por `auth.uid()` em todas as tabelas privadas no Supabase.
3. **Service Worker**: Cache restrito a recursos públicos estáticos, sem interceptar rotas de autenticação, dados de usuários ou APIs com cabeçalho `Authorization`.
4. **Cronômetro**: Inicialização padronizada com `01:00` (60 segundos) e formatação robusta de minutos e segundos.
