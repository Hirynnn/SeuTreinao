# SeuTreinao

Aplicativo mobile em Flutter e Dart para planejar e acompanhar treinos de musculação. A interface está em português brasileiro, com identidade visual vermelha e temas escuro (preto) e claro (branco), alternáveis pelo botão na barra superior. A preferência de tema fica salva no SQLite do dispositivo; o aplicativo não tem login, backend, sincronização ou dependência de internet.

## Funcionalidades

- Rotina semanal com divisão de treino e um treino por dia; dias sem associação são descanso.
- Programação baseada no calendário: perder um dia não desloca as sessões seguintes.
- Catálogo local com mais de 80 exercícios pré-cadastrados, organizado por grupo muscular, além de exercícios personalizados.
- Criação, edição, duplicação e exclusão protegida de treinos.
- Seleção e reordenação de exercícios; séries com carga e repetições planejadas individualmente.
- Importação de exercícios por texto, com correspondência local, correção e cadastro de nomes não encontrados.
- Execução de sessões com gravação individual de carga e repetições, conclusão, pulo, retorno à série anterior e salvamento automático dos valores editados.
- Retomada de sessão ativa após reabrir o aplicativo e retomada de sessões incompletas pelo histórico.
- Histórico com filtros por período e status e consulta dos detalhes das séries.
- Estatísticas básicas derivadas dos registros locais.
- Notificação interativa de sessão no Android, incluindo ação para concluir a série atual.
- Alternância persistente entre os temas escuro e claro.

## Tecnologias e estrutura

- Flutter / Dart.
- SQLite com `sqflite`; caminhos de banco gerenciados por `path`.
- Formatação e apresentação de datas com `intl`.
- Notificações locais Android com `flutter_local_notifications`.
- `sqflite_common_ffi` para testes de persistência em um banco SQLite temporário.

Arquivos principais:

- `lib/main.dart`: navegação e telas de rotina, dashboard, treinos, exercícios, execução, histórico e estatísticas.
- `lib/core/models.dart`: modelos de exercícios, treinos, rotina e sessões.
- `lib/core/enums.dart`: estados de dia e sessão.
- `lib/services/workout_rules.dart`: regras da programação semanal e progressão de séries.
- `lib/services/database_service.dart`: esquema versionado, catálogo inicial e persistência SQLite.
- `lib/services/notification_service.dart`: notificação interativa Android.
- `lib/services/statistics_service.dart`: cálculo isolado das estatísticas.
- `test/widget_test.dart`: testes de regras, progresso e estatísticas.
- `test/database_service_test.dart`: testes SQLite, catálogo e preservação do histórico.

## Requisitos

- Flutter e Dart na faixa definida em `pubspec.yaml`.
- Para executar/buildar Android: Android Studio, Android SDK, NDK e licenças Android aceitas.
- O projeto configura `compileSdk = 36` e `ndkVersion = 30.0.16248370` em `android/app/build.gradle.kts`.

No Android 13 ou superior, conceda permissão de notificações para ver os controles na notificação. Se essa permissão for negada, a sessão e seus controles continuam disponíveis no aplicativo. A ação da notificação é suportada no Android; não há integração equivalente para iOS.

## Executar

Na raiz do repositório:

```bash
flutter pub get
flutter run
```

Para escolher um dispositivo:

```bash
flutter devices
flutter run -d <device-id>
```

Também é possível abrir a raiz do projeto no VS Code ou Android Studio, aguardar a sincronização e iniciar em um emulador ou dispositivo Android.

## Verificações

```bash
dart format lib test
flutter analyze
flutter test
```

## Gerar APK

APK de debug:

```bash
flutter build apk --debug
```

APK de release:

```bash
flutter build apk --release
```

Os arquivos são gerados em `build/app/outputs/flutter-apk/` (`app-debug.apk` e `app-release.apk`). A configuração atual assina o build release com a chave de debug do Android para facilitar testes. **Esse APK não está assinado para distribuição/publicação.** Configure uma chave de release privada antes de publicar.

## Persistência e migrações

O arquivo SQLite é criado localmente como `seu_treinao.db`; a versão do esquema é incrementada sem apagar o banco em atualizações. O catálogo pré-cadastrado é inserido também em bancos já existentes, sem recriar nomes que já estão presentes.

Como os dados são locais, não há sincronização ou cópia na nuvem. Desinstalar o aplicativo pode remover os dados armazenados pelo Android.

## Pontos a configurar antes de publicar

- Trocar `com.example.seu_treinao` em `android/app/build.gradle.kts` por um `applicationId` único e definitivo.
- Criar e configurar assinatura Android de release; não distribuir o APK assinado com a chave de debug.
- Definir política de backup/exportação e privacidade dos dados locais, se necessária para a distribuição.
- Validar o fluxo de notificações e permissões nos dispositivos Android que serão suportados.
