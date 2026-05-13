## RFID Management Module (Flutter)

Flutter web/desktop UI for the **RFID Management Dashboard**: student registration, RFID number capture (keyboard wedge scanner), and an in-memory **Student Records** table (ready to be wired to Supabase).

### Getting started

1. **Install dependencies**

   ```bash
   flutter pub get
   ```

2. **Configure Supabase (frontend)**

   Supabase is initialized in `lib/main.dart` when you replace the placeholders with your project values:

   - `supabaseUrl`
   - `supabaseAnonKey`

   Use the **anon/public** key only (never commit a **service role** key in a client app).

3. **Run the app**

   Web (recommended for this layout):

   ```bash
   flutter run -d chrome
   ```

   Windows desktop (if enabled in your Flutter SDK):

   ```bash
   flutter run -d windows
   ```

### Project structure

- `lib/main.dart` – App entry point, theme, browser title, and Supabase initialization.
- `lib/ui/dashboard_page.dart` – RFID dashboard UI: registration form, RFID field, student records table (search, edit inline, delete), and temporary in-memory persistence until backend integration is added.

### Backend integration notes

- Student data is currently stored in a local list for UI prototyping; replace with `Supabase.instance.client` CRUD once your tables/policies are ready.
