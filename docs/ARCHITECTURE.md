# Architecture (Flutter app)

The big picture of the NextBrain app and the services it talks to, for a developer on day one. The illustrated
version, with videos, is `documents/01_Platform_Overview.docx` / `.pptx` (regenerate with
`documents/_build/build_platform.py`; see `documents/README.md`). The backend's own view, with every container and
schema, is `../back/docs/ARCHITECTURE.md`. Conventions and commands: `CLAUDE.md`.

## 1. System context

```mermaid
flowchart LR
    people["People<br/>students · teachers · parents<br/>org admins · super admin"]
    app["Flutter app (flutter_education_app)<br/>Android · iOS · Web"]
    nginx["nginx · https://nextbrain.site"]
    core["Core API :8000"]
    exam["Exam Engine :8001"]
    rag["RAG service :8002"]
    lk["LiveKit (live rooms)"]
    fb["Firebase project elfaheem<br/>Messaging · Crashlytics · Remote Config<br/>Auth (Google) · Hosting (web)"]
    pay["Moyasar / Paymob"]

    people --> app
    app -->|"HTTPS, AppConfig.baseUrl"| nginx
    nginx --> core & exam & rag
    app -->|WebRTC| lk
    app --> fb
    pay -->|webhooks| core
```

## 2. Inside the app (containers and layers)

```mermaid
flowchart TB
    main["lib/main.dart<br/>_bootstrap → _initCore (each step with a timeout)<br/>onGenerateRoute: _router"]
    providers["lib/core/providers.dart<br/>appProviders (ChangeNotifiers)"]
    features["lib/features/&lt;role&gt;/<br/>student · teacher · parent · admin · org · shared · auth"]
    kit["lib/design/app_kit.dart + BasePage<br/>(kill switch, upload footer)"]
    base["BaseProvider.run(() => …)<br/>idle / loading / success / error"]
    api["lib/core/api_client.dart<br/>ApiClient singleton on Dio"]
    enc["_EncryptionInterceptor<br/>X25519 → HKDF → AES-256-GCM"]
    auth["auth interceptor<br/>Bearer · device headers · X-View-As · 401 refresh"]
    pin["certificate pinning (mobile)"]
    store["TokenStorage (secure storage / web prefs)<br/>StorageService (cached user, UI prefs)"]
    offline["lib/core/offline/<br/>connectivity · encrypted offline videos"]
    theme["ThemeConfigProvider<br/>GET /api/v1/theme/{platform}<br/>colors + AppConfig.disableList"]

    main --> providers --> features
    features --> kit
    features --> base --> api
    api --> enc --> auth --> pin
    auth --> store
    features --> offline
    providers --> theme --> api
```

Ports and services behind nginx: core `api` 8000 (everything under `/api/v1/…` except the two below), Exam Engine
8001 (`/api/v1/exam/…`, client `lib/features/shared/exam_engine/exam_engine_api.dart`), RAG 8002 (`/api/v1/rag/…`,
`lib/features/shared/rag/`). The app sends every path in full on top of `AppConfig.baseUrl`
(`https://nextbrain.site/api`); nginx strips that prefix and routes by path.

## 3. Data stores

```mermaid
flowchart LR
    subgraph device["On the device"]
        ts["TokenStorage<br/>access + refresh token<br/>(secure storage; SharedPreferences on web)"]
        ss["StorageService<br/>cached user · language · UI prefs"]
        ov["Offline videos<br/>AES-CTR encrypted files + captions"]
        tr["assets/translation.json<br/>en + ar strings"]
    end
    subgraph server["On the server (../back)"]
        pg[("PostgreSQL<br/>public (core) · exam · rag<br/>Row Level Security per organization tree")]
        redis[("Redis<br/>queues · events · encryption session keys")]
        minio[("MinIO<br/>videos · PDFs · documents · recordings")]
    end
    ts -.->|Bearer on every call| pg
    ov -.->|downloaded from| minio
```

The server stores naive UTC; the app shows every time through `AppTime` (platform or organization timezone,
12h/24h). Refresh tokens rotate: `POST /api/v1/auth/refresh` returns a new pair and the old one is dead.

## 4. A request, end to end

```mermaid
sequenceDiagram
    autonumber
    participant UI as Screen
    participant P as Provider (BaseProvider)
    participant C as ApiClient
    participant N as nginx
    participant S as Core API
    participant DB as PostgreSQL
    UI->>P: user action
    P->>C: run(() => ApiClient().post('/api/v1/…', body))
    C->>C: encrypt body {"n","ct"} + X-Enc-Session, then Bearer + device headers
    C->>N: HTTPS (Android/iOS accept only the pinned certificate)
    N->>S: strip /api, forward
    S->>S: decrypt · rate limit · device / subscription / orgs guards · org_ctx permission
    S->>DB: SQL as nextbrain_app, RLS limited to the organization tree
    DB-->>S: rows
    S-->>C: encrypted envelope
    C->>C: decrypt; 401 → refresh once and retry; encryption_session_expired → new handshake and retry
    C-->>P: data, or ApiException (message safe to show, code e.g. DEVICE_MISMATCH)
    P-->>UI: notifyListeners()
```

## 5. Deployment

```mermaid
flowchart LR
    dev["Developer"] -->|push| ci["GitHub Actions .github/workflows/ci.yml<br/>flutter analyze (no warnings)<br/>test/org · test/export · test/ui<br/>flutter build web"]
    dev --> web["flutter build web<br/>build/web"] -->|firebase deploy --only hosting| fbh["Firebase Hosting"]
    dev --> rel["scripts/build_release.sh apk | appbundle | ipa | web<br/>--obfuscate, symbols in build/debug-info/"] --> stores["Google Play · App Store"]
    pipe["../back/scripts/pipeline<br/>3-both-test / 4-both-test-deploy"] -->|"after green CI"| server["server: flutter build web on the host"]
```

## Rules that keep the architecture intact

- Every API call goes through `ApiClient` (never a second `Dio` to the API host: pinning and encryption live there).
- New global state is registered in `lib/core/providers.dart`; feature providers extend `BaseProvider`.
- New screens use `lib/design/app_kit.dart` and `BasePage`; strings go to `assets/translation.json` (en + ar) or
  `t(ar, en)` in org screens; layouts pass `test/ui/layout_harness.dart`.
- Exam Engine and RAG paths are checked against the server's route snapshot by `test/contract/api_paths_test.dart`
  (`../back/scripts/contract/export_api_paths.py --front ../nextbrain-front` refreshes it).
- Code that is not web-safe sits behind `kIsWeb` or conditional imports.

## Coming in Phase 10 (in progress, not available yet)

MFA for admins, data-subject export, metrics, backups, quotas, dedicated service credentials, seed data and a
one-command local setup. This file will be updated when they land.
