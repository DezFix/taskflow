# TaskFlow

TaskFlow client — an app for IT department staff: tasks, photo reports, and a
chat that transcribes voice messages. A single codebase builds both as an
Android mobile app and as a web app.

The server side is a separate project:
[DezFix/taskflow-server](https://github.com/DezFix/taskflow-server).

---

## How it works

The app starts **without a server**: a staff member enters the address of their
own office — `192.168.1.50:8080`, `https://taskflow.company.ru`, or a VPN
address. The app checks the address and remembers it. After that it works like
an ordinary messenger: sign in with a login and password, tasks, chat, reports.

Three connection methods are supported:

| Where the server runs | Address | What you need |
|---|---|---|
| Domain behind Cloudflare or nginx | `https://taskflow.company.ru` | Nothing, the certificate is genuine |
| VPN into the office | `https://10.0.0.5:8443` | Enable certificate trust in settings |
| Local network | `http://192.168.1.50:8080` | Nothing, it is a trusted network |

## What the app can do

**Department head**
- Staff: creation, positions, roles, enabling and disabling accounts
- Tasks: creation, assignment, deadlines, priorities, labels
- Accepting and returning work: the "In review" status and a comment
- Reports: task summary, staff workload, Excel export
- Roles with a permission matrix: 32 permissions, assembled per role

**Staff member**
- Own tasks: filters by status, priority, deadline and assignee
- Work report: a comment with photos, the task moves to review
- Chat: direct dialogs and groups, files, voice messages
- Profile: name, phone, password change

**Voice messages**
Recording happens on the phone, the server does the transcription. A staff
member does not dictate tasks into a text field, they just speak — the text
appears in the chat. If the model got it wrong, the sender edits the
transcription by hand.

**Realtime**
A WebSocket channel: new tasks, messages and transcription statuses arrive
instantly. If the connection drops, the app reconnects on its own with
increasing delays, so it does not hammer the server.

## Workspace tabs

The set of tabs depends on what a staff member is allowed to do, not on who
they are:

| Tab | Available to |
|---|---|
| Tasks | Everyone |
| Chats | Everyone |
| Department | Those who manage staff |
| Reports | Those granted the reports permission |
| Profile | Everyone |

## Build

### Requirements

- Flutter 3.47 or newer (verified on 3.47.5)
- For Android: Android SDK 36, JDK 17
- For the web: nothing extra

### Android

```bash
flutter pub get
flutter build apk --release
```

Result: `build/app/outputs/flutter-apk/app-release.apk`.

The build is signed with the key from `android/key.properties`. To create it:

```bash
powershell -ExecutionPolicy Bypass -File tool/generate_keystore.ps1
```

Without `key.properties` the build is signed with the debug key — such an APK
is fine for testing, but not for handing out to staff: when the signature
changes, the app will not update over an installed copy.

### Web

```bash
flutter build web --release
```

The TaskFlow server serves the result if you put it in `data/web`:

```bash
cp -r build/web/* ../taskflow-server/data/web/
```

### Installing on a device

```bash
flutter install
# or manually
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Development

```bash
flutter pub get
flutter run              # on a connected device
flutter run -d chrome    # in a browser
flutter test             # tests
flutter analyze          # static analysis
```

### Structure

```
lib/
├── main.dart               entry point, routes, theme
├── data/
│   ├── models.dart         parsing of server responses
│   ├── api_client.dart     HTTP, token refresh, certificates
│   ├── realtime.dart       WebSocket with reconnection
│   ├── repositories.dart   API calls grouped by screen
│   └── storage.dart        server addresses, tokens, certificate trust
├── state/
│   ├── app_state.dart      session, user, realtime
│   └── controllers.dart    list state: tasks, chats, department, reports
└── ui/
    ├── theme.dart          colours, themes, date formatting
    ├── widgets.dart        avatars, labels, empty states
    ├── voice_recorder.dart voice recording
    ├── file_picking.dart   file selection and upload
    └── screens/            app screens
```

Layers: `ui` (screens) → `state` (state) → `data` (network and models).
Screens know nothing about HTTP, and `data` knows nothing about the interface.

## Tests

```bash
flutter test
```

Covered: parsing of server responses, address normalisation, task filters,
date formatting, and tab availability by permission. The tests need no server.

## Permissions

The app requests only the permissions it needs:

| Permission | Why |
|---|---|
| Internet | Talking to the office server |
| Microphone | Voice messages |
| Camera | Photo reports |
| Notifications | New tasks and messages (Android 13+) |

Microphone and camera are optional: the app installs and works without them,
and the unavailable features are simply disabled.

## Data handling

- The app sends nothing to the internet or to third parties
- Voice recordings and photos stay on your own office server
- Speech recognition runs on your own server, no cloud is used
- Communication with the server is over HTTPS when it is reachable by domain

## Licence

MIT. See [LICENSE](LICENSE).
