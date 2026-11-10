# AI-Assisted Workflow Documentation

## 1. Overview
Workshop 4 focuses on creating a complete, production-grade real-time "Waiting Room" application built with **Flutter (Dart)** and **Supabase** as the backend database and real-time engine. State management is handled with **Provider** (`ChangeNotifier`). The scope is strictly a single shared waiting room where clients can be added to the queue, served in FIFO order ("Next Client"), or removed individually, with immediate synchronization across multiple browser tabs and mobile devices.

---

## 2. Tools Used
- **Antigravity IDE Agent**: The autonomous agentic AI programming environment developed by Google DeepMind.
- **Model: Gemini 3.8 Flash**: Employed for end-to-end codebase scaffolding, architecture design, code generation, error correction, static analysis resolution, and test authoring.
- **Flutter & Dart Tooling**: `flutter create`, `flutter pub`, `flutter analyze`, and `flutter test` executed via terminal commands inside the workspace.
- **Supabase Cloud Dashboard**: Used for project configuration, Postgres table creation, Row Level Security (RLS) policies, and Realtime publications.

---

## 3. Workflow
The implementation followed a structured, collaborative workflow:

1. **Requirements & PDF Analysis**: Reviewed the workshop guidelines, scope, target platforms (Web and Android), and technical stack requirements.
2. **Manual Backend Setup (Developer)**:
   - Created the Supabase project.
   - Executed SQL to create the `public.clients` table (`id` uuid PK, `name` text, `created_at` timestamptz).
   - Configured RLS policies for `select`, `insert`, and `delete`.
   - Enabled Supabase Realtime replication on `public.clients`.
   - Configured anonymous sign-in in Supabase Auth.
   - Populated the local `.env` file with environment secrets.
3. **AI Agent Code Generation**:
   - Initialized the Flutter project in the root directory (`waiting_room_app`).
   - Configured `pubspec.yaml` dependencies and assets (`.env`).
   - Implemented the immutable `Client` model.
   - Implemented `ClientsRepository` and `SupabaseClientsRepository` adhering to Supabase v2 APIs.
   - Built `QueueProvider` managing subscription streams, queue operations, and error states.
   - Designed Material 3 UI widgets (`AddClientBar`, `ClientTile`, `EmptyStateWidget`, `WaitingRoomScreen`) and design system tokens (`AppTheme`).
   - Wrote comprehensive unit tests, fake repository mocks, widget tests, and integration test verifications.
   - Generated documentation and manual test scripts in `README.md`.
4. **Verification & Testing**:
   - Ran `flutter analyze` and resolved static analysis warnings.
   - Ran `flutter test` passing 100% of test cases.
   - Built and validated the web target (`flutter build web`).
   - Performed cross-tab and cross-device real-time sync tests.

---

## 4. Prompts Summary
The prompt provided to the AI agent specified:
- Initialize the Flutter application in-place within the current working folder.
- Use `supabase_flutter` v2 and `provider` (`ChangeNotifier`).
- Implement an immutable `Client` model, an abstract `ClientsRepository`, a `SupabaseClientsRepository`, and `QueueProvider`.
- Build a responsive Material 3 UI with cohesive typography, spacing, rounded corners, empty/loading/error states, queue numbering, and "Now Serving" accent chips.
- Ensure strict environment secret isolation: `.env` loaded via `flutter_dotenv`, declared in `pubspec.yaml` assets, added to `.gitignore`, and templated in `.env.example`.
- Write thorough tests (`Client` round-trip, `QueueProvider` unit tests with an in-memory `FakeClientsRepository`, and empty state widget tests).
- Run analysis and tests to ensure clean execution.

*(Note: In accordance with security practices, no credentials or project URLs were exposed in documentation or source files).*

---

## 5. Issues Identified in the Workshop PDF and Corrected

During the development process, several legacy, incomplete, or broken patterns from the workshop tutorial were identified and corrected:

1. **`supabase_flutter` v1 vs. v2 API Discrepancies**:
   - *Issue*: The PDF referenced deprecated v1 paradigms such as checking `response.error`, accessing `response.data`, attaching listeners with `.on(RealtimeEvent...)`, and inspecting `authResponse.error`.
   - *Fix*: In `supabase_flutter` v2, queries return unwrapped data directly and throw standard Dart exceptions upon failure. All operations were wrapped in `try/catch` blocks, and streams were queried via `supabase.from('clients').stream(primaryKey: ['id'])`.
2. **RLS Role Mismatch with Anonymous Sign-In**:
   - *Issue*: Defining RLS policies restricted `TO anon` prevents anonymously signed-in users from querying or mutating data, because Supabase assigns the `authenticated` role to anonymous sessions.
   - *Fix*: Configured RLS policies to permit both `anon` and `authenticated` roles (`TO anon, authenticated`).
3. **Missing `SELECT` RLS Policy**:
   - *Issue*: Default RLS blocks all queries if an explicit `SELECT` policy is not present, resulting in empty stream results without errors.
   - *Fix*: Ensured an explicit permissive `SELECT` policy exists for clients.
4. **Realtime Replication Disabled by Default**:
   - *Issue*: The table was not automatically added to the `supabase_realtime` publication.
   - *Fix*: Added `clients` to the Realtime publication so Postgres changes stream to connected clients.
5. **Broken "Add" Button UI Implementation**:
   - *Issue*: Code samples lacked stateful controller management, causing text field values to remain after submission or leak memory.
   - *Fix*: Implemented `AddClientBar` as a dedicated `StatefulWidget` with properly managed and disposed `TextEditingController` and `FocusNode`, submitting on both <kbd>Enter</kbd> and button tap.
6. **Asset Declaration for `.env`**:
   - *Issue*: The `.env` file must be declared in `pubspec.yaml` under `flutter: assets: - .env` for `dotenv.load()` to locate it at runtime.
   - *Fix*: Explicitly declared `.env` in `pubspec.yaml` assets and created a clean `.env.example`.
7. **Flutter Engine Binding Order**:
   - *Issue*: Calling `dotenv.load()` before engine initialization causes runtime assertion crashes.
   - *Fix*: Placed `WidgetsFlutterBinding.ensureInitialized()` at the very beginning of `main()`.
8. **Incompatible Mocking and Nonexistent `Response` Class in Tests**:
   - *Issue*: The PDF suggested mocking v1 `PostgrestResponse` objects that do not exist in v2.
   - *Fix*: Created a clean, robust, in-memory `FakeClientsRepository` backed by a `StreamController<List<Client>>` to test all queue states, stream errors, and mutations deterministically without third-party mocking friction.

---

## 6. Architecture & Data Flow

```
┌────────────────────────────────────────────────────────┐
│                   Supabase Cloud                      │
│     (PostgreSQL `clients` table + Realtime stream)     │
└──────────────────────────▲─────────────────────────────┘
                           │ Stream & Mutations
┌──────────────────────────▼─────────────────────────────┐
│               ClientsRepository (v2)                  │
│       watchClients() | insert(name) | delete(id)       │
└──────────────────────────▲─────────────────────────────┘
                           │ List<Client> events
┌──────────────────────────▼─────────────────────────────┐
│                   QueueProvider                        │
│          ChangeNotifier / Reactive State              │
└──────────────────────────▲─────────────────────────────┘
                           │ notifyListeners()
┌──────────────────────────▼─────────────────────────────┐
│                 WaitingRoomScreen                      │
│     (AddClientBar, ClientTile list, EmptyState)        │
└────────────────────────────────────────────────────────┘
```

- **`Client` Model**: Immutable data class holding `id` (uuid), `name` (String), and `createdAt` (DateTime converted to local time).
- **`ClientsRepository`**: Decoupled interface with a Supabase implementation using reactive streams (`stream(primaryKey: ['id']).order('created_at')`).
- **`QueueProvider`**: Listens to the repository stream, handles loading and connection errors, and exposes actions (`addClient`, `removeClient`, `nextClient`).
- **Presentation Layer**: Built with responsive constraints (`BoxConstraints(maxWidth: 720)`), Material 3 styling tokens from `AppTheme`, and accessible action controls.

---

## 7. What Was Done Manually vs. By AI

| Task / Responsibility | Performed By | Notes |
|---|---|---|
| Supabase Project Creation & Database Setup | **Developer (Manual)** | Project created in Supabase dashboard. |
| Table Schema, RLS Policies, Realtime Publication | **Developer (Manual)** | Table `public.clients` created with RLS. |
| Anonymous Authentication Configuration | **Developer (Manual)** | Enabled in Supabase Auth provider settings. |
| Project Scaffolding (`flutter create`) | **AI Agent** | Initialized directly in the workspace directory. |
| Package Dependencies Configuration | **AI Agent** | Configured `pubspec.yaml` and resolved packages. |
| Core Architecture & Code Generation | **AI Agent** | Generated model, repository, provider, and UI. |
| Design Tokens & Theme Creation | **AI Agent** | Material 3 light/dark palette in `app_theme.dart`. |
| Automated Test Suite Authoring | **AI Agent** | Unit, widget, and live integration tests. |
| Static Analysis & Linter Resolution | **AI Agent** | Zero errors/warnings under `flutter analyze`. |
| Two-Device Realtime Verification | **Developer (Manual)** | Verified live sync between Chrome and mobile/second tab. |
| Git Repository Publishing & Documentation | **AI Agent** | Initialized git, configured remotes, and created AI.md. |

---

## 8. Verification and Testing
1. **Model Tests (`test/client_test.dart`)**:
   - `fromMap` and `toMap` serialization round-trips.
   - Robust parsing of ISO-8601 strings and `DateTime` objects.
   - Fallbacks for missing/null fields and value equality verification.
2. **Provider Tests (`test/queue_provider_test.dart`)**:
   - Verified that empty and whitespace-only inputs are ignored.
   - Verified that client names are automatically trimmed.
   - Verified that `removeClient` removes targeted entries.
   - Verified that `nextClient` dequeues the oldest client and safely handles empty lists.
   - Verified that stream and operation failures set `errorMessage` and clear loading states.
   - Verified that `clients` is an unmodifiable view.
3. **Widget Tests (`test/widget_test.dart`)**:
   - Verified proper rendering of the `EmptyStateWidget` when the queue is clear.
4. **Integration Test (`test/supabase_connection_test.dart`)**:
   - Validated live connection and query execution against the remote database.
5. **Manual Cross-Client Sync**:
   - Added a client on Device A; verified instant appearance at position `#1` on Device B without refreshing.
   - Added a client on Device B; verified position `#2` updated immediately on Device A.
   - Clicked "Next Client" on Device B; confirmed client was dequeued synchronously on both screens.

---

## 9. Reflection & Production Hardening
- **Current Limitation**: In this demo workshop configuration, RLS policies grant open `INSERT` and `DELETE` access to any client holding the anon key or an anonymous session. In an open environment, any user could potentially delete arbitrary records.
- **Production Hardening Recommendations**:
  1. **Role-Based Access Control**: Restrict `DELETE` and `nextClient` operations to authenticated staff or admin roles (e.g. `service_role` or a custom claim `app_metadata.role = 'staff'`).
  2. **Audit Logging**: Maintain an `events` or `audit_log` table recording who was served and timestamping transitions (`served_at`).
  3. **Row-Level User Ownership**: In multi-room applications, partition tables by `room_id` and enforce membership checks via `auth.uid()`.

---

## 10. Workshop 5 — Offline-First SQLite Queue & Geolocation

### Overview & Agent Handoff History
Workshop 5 upgraded the Workshop 4 real-time waiting room into an **offline-first** Android/iOS application backed by local **SQLite (`sqflite`)**, **device geolocation (`geolocator`)**, and **connectivity monitoring (`connectivity_plus`)**.

In full transparency regarding the AI workflow:
1. A **first AI agent** (in VS Code) began the Workshop 5 upgrade—adding packages, updating `Client`, creating the service interfaces, and modifying parts of `QueueProvider` and the UI—but left the work incomplete (with a failing test in `queue_provider_test.dart`, async/race bugs in geolocation and offline deletion handling, missing offline/geolocation/widget tests, and outdated Workshop 4 docs).
2. A **second AI agent** (Antigravity / Gemini 3.8 Flash) audited all 12 requirements read-only, identified the remaining bugs and gaps, wrote the missing TDD tests first to reproduce the failures, fixed the provider/service/UI defects, and updated `README.md` and `AI.md`.

### What the AI Generated / Updated for Workshop 5
- **Packages (`pubspec.yaml`)**: Added `sqflite`, `path`, `path_provider`, `geolocator`, `uuid`, `connectivity_plus`, and dev dependency `sqflite_common_ffi`.
- **`Client` Model (`lib/models/client.dart`)**: Added `lat`, `lng`, `isSynced`, `pendingDelete`, `fromLocalMap`/`toLocalMap`, and `copyWith` with sentinel null-clearing while keeping `toMap()` restricted to remote Supabase columns (`id`, `name`, `created_at`, `lat`, `lng`).
- **Services (`lib/services/`)**:
  - `LocalQueueService`: Instance-scoped SQLite helper managing `local_clients` with `inMemory` (`singleInstance: false`) support for isolated tests, a pure-Dart `useMemoryFallback` mode when `kIsWeb` is true (so Chrome runs without `MissingPluginException`), `getClientById`, `getClients`, `getUnsyncedClients`, `getPendingDeletes`, `markClientAsSynced`, `markPendingDelete`, `deleteLocally`, `upsertSyncedFromRemote`, and `removeSyncedNotIn`.
  - `GeolocationService` / `GeolocatorService`: Injectable wrapper checking location services and permissions with a 10-second `LocationSettings` timeout that always returns `null` on failure instead of throwing.
  - `ConnectivityService` / `DeviceConnectivityService`: Injectable wrapper around `connectivity_plus` exposing `onlineChanges` and `isOnline`.
- **`ClientsRepository` (`lib/repositories/clients_repository.dart`)**: Added `upsert(Client)` (`onConflict: 'id'`) to both `SupabaseClientsRepository` and test fakes.
- **`QueueProvider` (`lib/queue_provider.dart`)**: Implemented local-first startup (`initialized` future), `addClient` capturing UUID v4 + geolocation locally first before `unawaited(sync())`, offline-safe `removeClient`/`nextClient`, guarded `sync()`, safe remote stream merge, automatic sync & resubscription on reconnect, and proper `dispose()` cleanup.
- **UI & Platform Permissions**: Updated `ClientTile` (`📍 lat, lng` to 4 decimals / `📍 Location not captured` and **"Waiting to sync"** badge), `WaitingRoomScreen` (offline banner and accurate `Offline` / `Syncing...` / `Realtime` status pill), `AndroidManifest.xml`, and `Info.plist`.
- **Tests**: Fixed `queue_provider_test.dart`, expanded `client_test.dart`, `local_queue_service_test.dart`, and `widget_test.dart`, and created `queue_provider_offline_test.dart` and `queue_provider_geolocation_test.dart`.

### Issues Identified in the Workshop 5 PDF and How They Were Fixed
1. **Offline Deletes Not Covered**:
   - *Issue*: The workshop guide focused on offline inserts without handling deletions performed while offline, which would either throw on Supabase `delete()` or be overwritten on reconnect.
   - *Fix*: Added `pending_delete` tracking in SQLite (`markPendingDelete`, `getPendingDeletes`). Unsynced rows are deleted locally immediately; synced rows are marked `pending_delete = 1`, hidden from `getClients()`, and deleted remotely during `sync()`.
2. **Empty Realtime Handler Causing Local/Remote Drift**:
   - *Issue*: Leaving the realtime stream merge incomplete allowed remote snapshots to overwrite local unsynced edits or resurrect rows deleted locally while offline.
   - *Fix*: Implemented `upsertSyncedFromRemote` and `removeSyncedNotIn` so incoming remote data skips rows where `is_synced = 0` or `pending_delete = 1`, and pruning only removes synced non-pending rows absent from the server.
3. **`sqflite` Not Supporting Web**:
   - *Issue*: `sqflite` and `path_provider` throw `MissingPluginException` on Flutter Web (`flutter run -d chrome`).
   - *Fix*: Targeted Android/iOS for persistent SQLite storage (`flutter run -d android`), used `sqflite_common_ffi` for desktop unit tests, and later added a `kIsWeb` in-memory fallback (`useMemoryFallback`) in `LocalQueueService` so the app also runs cleanly on Google Chrome.
4. **Uncompilable Test Code (`final` Private Field Assignment & `void _onCreate ... async`)**:
   - *Issue*: Sample code attempted to assign to a `final` private field and declared `void _onCreate(...) async` where `sqflite` expects `Future<void> Function(Database, int)` (so table creation wasn't awaited).
   - *Fix*: Used constructor-injected dependencies for testing and typed `_onCreate` as `Future<void> _onCreate(Database db, int version) async` with `await db.execute(...)`.
5. **Shared Static Database Singleton Leaking Between Tests**:
   - *Issue*: A static `_database` singleton (and `openDatabase(inMemoryDatabasePath)` without `singleInstance: false`) leaked rows between unit tests.
   - *Fix*: Stored `_database` per `LocalQueueService` instance, supported `providedDatabase` and `inMemory: true` with `singleInstance: false`, and closed databases cleanly in `tearDown`.
6. **Deprecated `desiredAccuracy` Parameter in `geolocator`**:
   - *Issue*: Workshop snippets used the deprecated `desiredAccuracy` argument in `Geolocator.getCurrentPosition`.
   - *Fix*: Used `locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10))`.
7. **`MockQueueProvider` Never Generated**:
   - *Issue*: Test samples referenced a `MockQueueProvider` from `build_runner`/`mockito` without generating it.
   - *Fix*: Used real `QueueProvider` instances wired with lightweight fake implementations of `ClientsRepository`, `ConnectivityService`, `GeolocationService`, and in-memory `LocalQueueService` (and direct `ClientTile` / `WaitingRoomScreen` widget tests).
8. **Missing `UPDATE` RLS Policy Needed by `upsert`**:
   - *Issue*: `upsert(onConflict: 'id')` requires both `INSERT` and `UPDATE` Row Level Security policies on `public.clients`, whereas Workshop 4 only created `SELECT`, `INSERT`, and `DELETE`.
   - *Fix*: Added an `UPDATE` RLS policy on `public.clients` in Supabase so `upsert` succeeds cleanly.
9. **Outdated Package Versions**:
   - *Issue*: Older `connectivity_plus` (returning a single `ConnectivityResult` instead of `List<ConnectivityResult>`), older `geolocator`, and older `sqflite` versions in the PDF caused API mismatches.
   - *Fix*: Upgraded to current stable versions (`connectivity_plus: ^7.3.2`, `geolocator: ^14.0.1`, `sqflite: ^2.4.5`, `sqflite_common_ffi: ^2.4.5`, `uuid: ^4.6.0`, `path_provider: ^2.1.6`) and updated `DeviceConnectivityService` for `List<ConnectivityResult>`.
10. **No Automatic Sync on Reconnect**:
    - *Issue*: Sync was only invoked manually or on `addClient`, leaving offline changes unsynced after network recovery.
    - *Fix*: Subscribed to `ConnectivityService.onlineChanges` in `QueueProvider.initialize()` to automatically call `sync()` and resubscribe to the realtime stream when connectivity returns.

### Manual Tasks Performed by the Developer
- Updated `public.clients` in Supabase (added nullable `lat` and `lng` `double precision` columns and added the `UPDATE` RLS policy for `upsert`).
- Verified emulator testing on Android (toggling Wi-Fi/mobile data, configuring mock coordinates in Extended controls -> Location, and checking two-device realtime sync).

---

## 11. Workshop 6 — Resilient Single-Room Waiting Queue

### Overview
Workshop 6 extended the Workshop 5 offline-first architecture with:
- **Rich Sync & Queue State Models**: `SyncStatus` (`pending`, `syncing`, `synced`, `failed`), `AppConnectivity` (`checking`, `online`, `offline`, `backendUnavailable`), `QueueState` (`initial`, `loading`, `loaded`, `empty`, `refreshing`, `loadingMore`, `error`), plus `locationAccuracy` (`location_accuracy_m`) and `locationCapturedAt` (`location_captured_at`) on `Client`.
- **Network vs. Backend Reachability (`ConnectivityService` & `ConnectivityProvider`)**: Distinguishes device network offline (`offline`) from Supabase unreachable (`backendUnavailable`) with 700ms debounced backend health checks and re-entrant check guards.
- **Dedicated Synchronization Engine (`SyncService`) & SQLite v2 Migration**: Migrated `local_clients` (`schemaVersion = 2`) via `onUpgrade`, fetching both `pending` and `failed` records for automatic retry, transitioning records through `syncing` -> `synced` / `failed`, and processing pending offline deletes.
- **RPC Registration & Graceful Schema Fallback (`ClientsRepository`)**: Added `registerOnServer(Client)` (calling `register_queue_client` RPC with automatic `PostgrestException` fallback to `upsert` if the Workshop 6 SQL migration/RPC is not yet applied in Supabase) and `fetchPage(offset, limit)` for pagination.
- **Pagination & Realtime Deduplication (`QueueProvider`)**: Added `fetchInitialQueue()`, `loadMore()`, and `handleRealtimeInsert()` deduplication.
- **Advanced UI Widgets**: Added `OfflineBanner` (all 4 `AppConnectivity` states), `LoadingWidget`, `SyncStatus` badges + optional location accuracy (`±Xm`) on `ClientTile`, and a pagination `"Load More"` footer on `WaitingRoomScreen`.

### Issues Identified in the Workshop 6 PDF and How They Were Fixed
1. **Static `_database` Singleton in `LocalQueueStorage`**:
   - *Issue*: The Workshop 6 PDF repeated `static Database? _database;` in `LocalQueueStorage`, which leaks database handles across unit tests.
   - *Fix*: Kept the instance-scoped `_database` pattern in `LocalQueueService` with `inMemory: true` (`singleInstance: false`) and the `kIsWeb` `useMemoryFallback`.
2. **FIFO vs. `DESC` Ordering Contradiction**:
   - *Issue*: `LocalQueueStorage.getClients()` and `handleRealtimeInsert` in the PDF ordered newest clients first (`created_at DESC` / `insert(0, client)`), which conflicts with the single shared FIFO waiting queue where `#1 Now Serving` is the oldest client.
   - *Fix*: Maintained `created_at ASC` ordering across SQLite queries, `fetchPage`, realtime stream, and `handleRealtimeInsert` while preserving deduplication.
3. **Syncing Engine Missing Offline Deletes & `SyncStatus.failed` Handling**:
   - *Issue*: `SyncService` in the PDF only handled inserts, omitting offline deletions (`pending_delete`), and did not gracefully handle Supabase projects missing the optional `location_accuracy_m` column or `register_queue_client` RPC.
   - *Fix*: Integrated `pending_delete` cleanup in `SyncService.synchronize()`, added `onUpgrade` SQLite migration from v1 to v2, and implemented automatic fallback from `register_queue_client` RPC / extended columns to core `upsert`.
4. **`dart:async` Timer Leak Risk in `ConnectivityProvider`**:
   - *Issue*: Needed deterministic testability for the 700ms debounce and safe cancellation on `dispose()`.
   - *Fix*: Made `debounceDuration` injectable in `ConnectivityProvider` and cancelled both `_debounceTimer` and `_subscription` in `dispose()`.
5. **Duplicate `LocalQueueService` Instance in Default `QueueProvider` Constructor**:
   - *Issue*: Calling `QueueProvider()` without an explicit `localQueueService` evaluated `localQueueService ?? LocalQueueService()` twice—creating separate instances for `_local` and `_syncService`, which left newly added items stuck in `Waiting to sync` during live Chrome testing.
   - *Fix*: Initialized `_syncService` in the constructor body from the already-assigned `_local` and `_repository` instances, and broadened `PostgrestException` fallback in `SupabaseClientsRepository.registerOnServer`.
