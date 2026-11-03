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
