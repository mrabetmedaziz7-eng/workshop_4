# 🕒 Real-Time Waiting Room App

A modern, responsive, real-time Waiting Room Flutter application powered by **Supabase Realtime** and **Provider** (`ChangeNotifier`).

---

## 📖 Features

- **Live Realtime Synchronization**: Seamless updates across all open devices, browser tabs, and mobile clients using Supabase Realtime Postgres Changes.
- **Queue Management**:
  - **Add to Queue**: Input client names with instant auto-trimming and keyboard submit.
  - **Now Serving Highlight**: The oldest client (first in line) is highlighted with an active badge and status styling.
  - **Next Client**: Serves and removes the first client in line with a single click (disabled when queue is empty).
  - **Individual Removal**: Remove any client from the queue at any time.
- **Modern Material 3 Design**:
  - Curated Indigo & Emerald palette with responsive constraints (scales seamlessly from phone screens to wide desktop browsers).
  - Dedicated empty state, loading indicator, and connection error handling with retry support.
  - Localized creation time formatting (`HH:mm`).
- **Clean Architecture & Full Test Coverage**:
  - Null-safe code adhering strictly to `supabase_flutter` v2 API paradigms (no deprecated v1 error patterns).
  - Unit tests for models and providers with a `FakeClientsRepository`, widget tests, and live Supabase connection verification.

---

## 📁 Project Structure

```
lib/
├── main.dart                          # App initialization (.env, Supabase, anon auth, Provider)
├── queue_provider.dart                # State management (ChangeNotifier, stream subscription, queue actions)
├── models/
│   └── client.dart                    # Immutable Client model (fromMap, toMap, copyWith, equals)
├── repositories/
│   └── clients_repository.dart        # Abstract ClientsRepository & SupabaseClientsRepository v2
├── screens/
│   └── waiting_room_screen.dart       # Main UI with responsive container, queue list & actions
├── theme/
│   └── app_theme.dart                 # Design tokens (colors, spacing, radius, Material 3 ThemeData)
└── widgets/
    ├── add_client_bar.dart            # Input text field with controller & add button
    ├── client_tile.dart               # Individual queue card (#1 Now Serving, time, delete)
    └── empty_state.dart               # Visual illustration and message when queue is empty

test/
├── client_test.dart                   # Unit tests for Client model serialization and equality
├── queue_provider_test.dart           # Unit tests with FakeClientsRepository (trim, remove, next, errors)
├── supabase_connection_test.dart      # Live database integration test against Supabase
└── widget_test.dart                   # Widget tests for UI components
```

---

## 🚀 Setup & Installation

### 1. Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart 3.x)
- Google Chrome (for web) and/or Android Studio / device (for Android)

### 2. Configure Environment Secrets
Create a `.env` file in the project root based on `.env.example`:

```bash
cp .env.example .env
```

Populate `.env` with your Supabase credentials:
```env
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-supabase-publishable-anon-key
```

### 3. Install Dependencies
```bash
flutter pub get
```

### 4. Run Analysis & Tests
```bash
# Static analysis
flutter analyze

# Run unit and widget tests
flutter test
```

---

## 💻 Running the Application

### Run on Chrome (Web)
```bash
flutter run -d chrome
```

### Run on Android
```bash
flutter run -d android
```

### Build for Production Web
```bash
flutter build web
```

---

## 🧪 Manual Two-Device Realtime Test Script

To verify real-time cross-client synchronization:

1. **Open Instance A**:
   - Run the app in Google Chrome (`flutter run -d chrome`) or open a new browser window.
2. **Open Instance B**:
   - Open a second browser tab (or Incognito window) to the same local URL, or launch the app on an Android emulator / physical device.
3. **Step 1 - Add Client on Device A**:
   - In **Device A**, type `John Doe` into the text box and press Enter or tap **Add to Queue**.
   - Notice that `John Doe` instantly appears at position `#1` on **Device A**.
   - Look at **Device B**: `John Doe` automatically appears as `#1` (**Now Serving**) with zero refresh needed.
4. **Step 2 - Add Second Client on Device B**:
   - In **Device B**, type `Alice Smith` and tap **Add to Queue**.
   - `Alice Smith` appears at position `#2` on both **Device B** and **Device A**.
5. **Step 3 - Next Client Action on Device B**:
   - On **Device B**, click the **Next Client** button.
   - `John Doe` is removed from the queue on **Device B**.
   - Observe **Device A**: `John Doe` disappears instantaneously, and `Alice Smith` moves up to `#1` (**Now Serving**) across both screens.
6. **Step 4 - Individual Deletion on Device A**:
   - On **Device A**, tap the trash can icon on `Alice Smith`.
   - The queue becomes empty on both devices, displaying the empty state (`"No one in queue yet..."`).
