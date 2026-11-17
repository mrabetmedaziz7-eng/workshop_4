# 🕒 Resilient Offline-First Waiting Room App

A modern, offline-first Waiting Room Flutter application powered by **SQLite (`sqflite`)**, **Geolocator**, **Connectivity Plus**, **Supabase Realtime & RPC**, and **Provider** (`ChangeNotifier`).

> **Platform Note (SQLite on Android / iOS; In-Memory Fallback on Chrome):** Because `sqflite` and `path_provider` do not support Flutter Web, persistent SQLite offline storage targets **Android** (and iOS). On **Chrome (Web)**, `LocalQueueService` automatically uses a pure-Dart in-memory store (`kIsWeb`) so the app runs cleanly for live Supabase Realtime and browser testing (data resets on page refresh). Unit tests run on desktop via `sqflite_common_ffi`.

---

## 📖 Features

- **Offline-First Local Queue (`sqflite` v2) & `SyncService`**:
  - Clients are persisted locally first in `local_clients` with a client-generated UUID v4 and explicit `SyncStatus` (`pending`, `syncing`, `synced`, `failed`).
  - Failed sync attempts are marked `failed` and automatically retried alongside `pending` entries on the next sync.
  - Unsynced rows display a status badge (`Waiting to sync`, `Syncing...`, or `Sync failed · will retry`) until uploaded to Supabase.
- **Network vs. Backend Availability Monitoring (`ConnectivityProvider`)**:
  - Distinguishes **device offline** (`No network connection`) from **backend unreachable** (`Waiting-room server unavailable`) with a 700ms debounced Supabase reachability check (`AppConnectivity`: `checking`, `online`, `offline`, `backendUnavailable`).
- **Pagination, Realtime Deduplication & Server RPC**:
  - `QueueProvider` exposes `QueueState` (`initial`, `loading`, `loaded`, `empty`, `refreshing`, `loadingMore`, `error`), `fetchInitialQueue()`, `loadMore()`, and `handleRealtimeInsert()` deduplication.
  - `ClientsRepository.registerOnServer` calls the `register_queue_client` PostgreSQL RPC (with automatic fallback to core `upsert` if optional Workshop 6 SQL columns/RPC are not yet applied in Supabase).
- **Geolocation Tagging (`geolocator`)**:
  - Captures device coordinates (`lat`, `lng`) and accuracy (`location_accuracy_m`) with a 10-second timeout (`LocationAccuracy.medium`).
  - Displays `📍 lat, lng (±Xm)` formatted to 4 decimal places on each tile, or `📍 Location not captured` if permissions/services are unavailable (rejects invalid `(0, 0)` coordinates).
- **Queue Management & Material 3 UI**:
  - Add clients with auto-trimming, highlight `#1` **Now Serving**, advance with **Next Client**, or remove any client (online or offline).
  - Dedicated `OfflineBanner`, `LoadingWidget`, `EmptyStateWidget`, error state, and pull-to-refresh / retry support.

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

### 3. Optional Supabase SQL Upgrade (Workshop 6)
If you want to store `location_accuracy_m` / `location_captured_at` and use the `register_queue_client` RPC in Supabase, run this in the Supabase SQL Editor (the app falls back automatically to core columns if omitted):
```sql
ALTER TABLE public.clients
ADD COLUMN IF NOT EXISTS location_accuracy_m DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS location_captured_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION register_queue_client(
  p_id UUID,
  p_name TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_accuracy DOUBLE PRECISION,
  p_created_at TIMESTAMPTZ
)
RETURNS SETOF public.clients AS $$
BEGIN
  RETURN QUERY
  INSERT INTO public.clients (id, name, lat, lng, location_accuracy_m, created_at)
  VALUES (p_id, p_name, p_lat, p_lng, p_accuracy, p_created_at)
  ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name
  RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 4. Install Dependencies, Analyze & Test
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
