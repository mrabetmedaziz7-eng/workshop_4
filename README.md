# 🕒 Offline-First Waiting Room App

A modern, offline-first Waiting Room Flutter application powered by **SQLite (`sqflite`)**, **Geolocator**, **Connectivity Plus**, **Supabase Realtime**, and **Provider** (`ChangeNotifier`).

> **Platform Note (SQLite on Android / iOS; In-Memory Fallback on Chrome):** Because `sqflite` and `path_provider` do not support Flutter Web, persistent SQLite offline storage targets **Android** (and iOS). On **Chrome (Web)**, `LocalQueueService` automatically uses a pure-Dart in-memory store (`kIsWeb`) so the app runs cleanly for live Supabase Realtime and browser testing (data resets on page refresh). Unit tests run on desktop via `sqflite_common_ffi`.

---

## 📖 Features

- **Offline-First Local Queue (`sqflite`)**:
  - Clients are persisted locally first in `local_clients` with a client-generated UUID v4, so adding and removing clients works immediately with zero network dependency.
  - Unsynced rows display a **"Waiting to sync"** badge until uploaded to Supabase.
  - Offline banner (`Offline · changes will sync when connected`) and AppBar status pill (`Offline` / `Syncing...` / `Realtime`) keep connection state clear.
- **Automatic Bidirectional Sync & Realtime**:
  - Loads cached local rows immediately on startup, syncs pending changes, and subscribes to Supabase Realtime (`stream(primaryKey: ['id'])`).
  - Automatically syncs pending inserts (`upsert`) and pending deletes (`delete`) when connectivity returns.
  - Concurrent sync runs are guarded, and individual item failures are logged without blocking remaining items.
- **Geolocation Tagging (`geolocator`)**:
  - Captures device coordinates (`lat`, `lng`) with a 10-second timeout and `LocationAccuracy.low`.
  - Displays `📍 lat, lng` formatted to 4 decimal places on each tile, or `📍 Location not captured` if permissions/services are unavailable (rejects invalid `(0, 0)` coordinates).
- **Queue Management & Material 3 UI**:
  - Add clients with auto-trimming, highlight `#1` **Now Serving**, advance with **Next Client**, or remove any client (online or offline).
  - Clean empty, loading, and error states with pull-to-refresh / retry support.

---

## 🏗️ Offline-First Architecture & How Sync Works

```
┌───────────────────────────────────────────────────────────────────┐
│                         WaitingRoomScreen                         │
│   (Offline Banner · AddClientBar · ClientTile · Next Client)      │
└───────────────────────────────▲───────────────────────────────────┘
                                │ notifyListeners()
┌───────────────────────────────┴───────────────────────────────────┐
│                           QueueProvider                           │
│  1. Load local SQLite -> 2. Sync pending -> 3. Subscribe Realtime │
│  Listens to ConnectivityService.onlineChanges for auto-reconnect  │
└──────▲──────────────────────────▲──────────────────────────▲──────┘
       │                          │                          │
┌──────┴───────────┐   ┌──────────┴───────────┐   ┌──────────┴──────────┐
│ LocalQueueService│   │  GeolocationService  │   │ ClientsRepository   │
│ (sqflite local   │   │ (permission/service  │   │ (Supabase v2 upsert │
│  `local_clients`)│   │  check, 10s timeout) │   │  stream & delete)   │
└──────────────────┘   └──────────────────────┘   └──────────▲──────────┘
                                                             │
                                                  ┌──────────┴──────────┐
                                                  │   Supabase Cloud    │
                                                  │  (`public.clients`) │
                                                  └─────────────────────┘
```

### How Synchronization Works
1. **Startup**: `QueueProvider` loads `local_clients` (excluding `pending_delete = 1`) immediately so cached clients appear without waiting for the network.
2. **Adding a Client (`addClient`)**: Generates a UUID v4 locally, attempts geolocation capture (falling back to `null` on failure/denial), inserts into `local_clients` with `is_synced = 0`, refreshes the UI immediately, and triggers `unawaited(sync())` if online.
3. **Removing a Client (`removeClient` / `nextClient`)**:
   - If the client has never been synced (`is_synced = 0`), it is deleted directly from SQLite.
   - If the client is already synced (`is_synced = 1`), it is marked `pending_delete = 1` (immediately hidden from the queue) and deleted remotely either right away (if online) or during the next `sync()` once reconnected.
4. **Sync Loop (`sync()`)**: Guarded against concurrent execution. Pushes unsynced rows one by one via `upsert(client, onConflict: 'id')` and marks each `is_synced = 1` on success, then processes `pending_delete = 1` rows via `delete(id)` and removes them locally.
5. **Realtime Merge**: Incoming Supabase stream snapshots update synced rows via `upsertSyncedFromRemote` and prune remotely deleted rows via `removeSyncedNotIn`—while **never** overwriting unsynced local inserts or resurrecting rows marked `pending_delete = 1`.

---

## 📁 Project Structure

```
lib/
├── main.dart                          # Bootstrap (.env, Supabase, anon auth, Provider)
├── queue_provider.dart                # Offline-first ChangeNotifier state & sync orchestration
├── models/
│   └── client.dart                    # Immutable Client model (remote & local maps, copyWith)
├── repositories/
│   └── clients_repository.dart        # ClientsRepository interface & SupabaseClientsRepository v2
├── services/
│   ├── local_queue_service.dart       # SQLite persistence (`local_clients` table)
│   ├── geolocation_service.dart       # Injectable Geolocator wrapper (10s timeout, never throws)
│   └── connectivity_service.dart      # Injectable connectivity_plus stream & check
├── screens/
│   └── waiting_room_screen.dart       # Main UI with offline banner, queue header & list
├── theme/
│   └── app_theme.dart                 # Material 3 light/dark design tokens
└── widgets/
    ├── add_client_bar.dart            # Input field & Add to Queue button
    ├── client_tile.dart               # Queue card (position, time, 📍 coords, Waiting to sync)
    └── empty_state.dart               # Empty queue state

test/
├── client_test.dart                   # Client model & local/remote map tests
├── local_queue_service_test.dart      # In-memory sqflite_common_ffi tests
├── queue_provider_test.dart           # Core QueueProvider unit tests
├── queue_provider_offline_test.dart   # Offline-first, pending delete & reconnect sync tests
├── queue_provider_geolocation_test.dart # Geolocation capture, null & (0,0) handling tests
├── supabase_connection_test.dart      # Live Supabase query smoke test
└── widget_test.dart                   # Widget tests (ClientTile coords, unsynced badge, offline UI)
```

---

## 🚀 Setup & Running on an Android Emulator

### 1. Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart 3.x)
- Android Studio with an Android Emulator (API 24+ recommended)

### 2. Configure Environment Secrets
Create a `.env` file in the project root based on `.env.example` (`.env` is gitignored and must never be committed):

```bash
cp .env.example .env
```

Populate `.env` with your Supabase credentials:
```env
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-supabase-publishable-anon-key
```

### 3. Install Dependencies, Analyze & Test
```bash
flutter pub get
flutter analyze
flutter test
```

### 4. Run on an Android Emulator
1. Start an Android emulator from Android Studio or CLI (`flutter emulators --launch <emulator_id>`).
2. Set a mock GPS location in the emulator (**Extended controls (`...`) -> Location -> Set Location**).
3. Launch the app:
   ```bash
   flutter run -d android
   ```
   *(Note: If you change location permissions in `AndroidManifest.xml` or grant/revoke OS permissions, perform a full app restart rather than hot reload.)*

### 5. Run on Google Chrome (Web)
```bash
flutter run -d chrome
```
*(Chrome uses the in-memory queue fallback and browser geolocation API instead of SQLite.)*

---

## ✅ Demo Checklist

1. **Add a client online** -> appears in Supabase immediately.
2. **Turn off Wi-Fi/data on the emulator. Add 2 clients** -> they appear instantly with the **"Waiting to sync"** indicator.
3. **Turn internet back on** -> they upload automatically and the indicator disappears.
4. **Open the app on another device** -> all clients visible through realtime.
5. **Location is shown on each tile**, or **"Location not captured"** if permission was denied.
6. **Remove a client while offline** -> it disappears locally and is deleted remotely after reconnecting.
