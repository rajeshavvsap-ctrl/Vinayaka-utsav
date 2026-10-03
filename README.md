# Vinayaka Chaturthi Committee App

This is a Flutter + Firebase mobile app for running the festival. Only committee members who have been approved can use it.

| Tile | What it does |
|---|---|
| **Activities** | Day-wise schedule (pooja timings, aarti, programs, visarjan). Any member can add an activity; the creator or an admin can edit or delete it. |
| **Pooja Seva** | Pick a festival day and add your name (or your family's) under a pooja slot, such as Morning Pooja or Evening Aarti. Slots are set by admins. |
| **Expenses** | Add an expense with the amount, category, who paid and a photo of the bill or payment screenshot. Shows totals and lets you filter by category. |
| **Contributions** | A member pays the committee by UPI/cash/bank, taps **I have paid** and attaches the screenshot. An admin verifies the payment, and only then does it count in **Collected**. |
| **Members** | New people register, and an admin approves or rejects them. Admins can grant or remove admin rights and remove access. |
| **Settings** (admin) | Festival title, start date, number of days, pooja slots and the committee UPI ID. |

The home screen shows **Collected / Spent / Balance**, the next activity today, and a **Copy summary for WhatsApp** button.

## How access is restricted to committee members

1. Everyone signs in with email + password (Firebase Authentication).
2. A new registration is saved as `status: pending`. The app shows "Waiting for approval" and nothing else.
3. An admin approves the person in **Members**, and the app opens for them automatically.
4. The same check is enforced on the server by `firestore.rules`. Even a modified app or a direct API call cannot read or write festival data without an approved profile. Only admins can approve members, verify contributions or change settings.

## Cost

Everything runs on Firebase's free **Spark** plan, so no credit card is needed. The free plan includes 1 GiB of Firestore storage, 50,000 reads/day and 20,000 writes/day. That is far more than a committee needs.

Screenshots are compressed to about 100–300 KB JPEGs and stored inside Firestore. This avoids Cloud Storage, which needs the paid Blaze plan for new projects.

---

## Step-by-step: build and run

### 1. Install the tools (one time)

1. **Flutter SDK**: https://docs.flutter.dev/get-started/install (choose your OS → Android).
2. **Android Studio** (for the Android SDK and an emulator). Open it once and install the Android SDK and command-line tools.
3. **Node.js** (LTS): https://nodejs.org. It is needed for the Firebase CLI.
4. In a terminal:
   ```bash
   flutter doctor            # fix anything marked ✗ (accept Android licenses: flutter doctor --android-licenses)
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   ```
   Add `~/.pub-cache/bin` (Windows: `%LOCALAPPDATA%\Pub\Cache\bin`) to your PATH so the `flutterfire` command works.

### 2. Create the Flutter project and copy this code in

```bash
flutter create --org com.yourcommittee vinayaka_utsav
cd vinayaka_utsav
```

Copy these files from this package into that folder, replacing any that already exist:

```
pubspec.yaml
analysis_options.yaml
firebase.json
firestore.rules
lib/            (whole folder)
test/widget_test.dart
```

Then run:
```bash
flutter pub get
```
If `pub get` reports a version conflict, run `flutter pub upgrade --major-versions` and it will pick compatible versions.

### 3. Create the Firebase project

1. Go to https://console.firebase.google.com, click **Create a project**, name it (e.g. `vinayaka-utsav`) and leave Google Analytics off.
2. **Build → Authentication → Get started → Sign-in method → Email/Password → Enable → Save.**
3. **Build → Firestore Database → Create database.** Choose location **asia-south1 (Mumbai)** and start in **production mode**.

### 4. Connect the app to Firebase

From inside the project folder:
```bash
firebase login
flutterfire configure
```
Select your project and tick **android** (and **ios** if you will build for iPhone). This generates `lib/firebase_options.dart` and `android/app/google-services.json`. The app will not compile without them.

### 5. Publish the security rules

```bash
firebase use --add          # pick your project
firebase deploy --only firestore:rules
```
Alternatively, open Firestore → **Rules** in the console, paste the contents of `firestore.rules` and click **Publish**.

### 6. Android settings

Open `android/app/build.gradle` (or `build.gradle.kts`) and make sure the minimum SDK is at least 23:
```
defaultConfig {
    minSdk = 23        // Groovy file: minSdkVersion 23
}
```

### 7. Run it

Connect an Android phone with USB debugging on, or start an emulator, then:
```bash
flutter run
```

### 8. Make yourself the first admin (one time)

1. In the app, tap **New member? Register here** and register yourself.
2. In the Firebase console, open **Firestore → users → (your document)**.
3. Change `role` to `admin` and `status` to `approved`.
4. The app opens immediately. Go to **Settings** and set the festival start date, number of days, pooja slots and UPI ID.

From now on you approve everyone else from the **Members** tile. You can make a co-organiser or treasurer an admin there too.

### 9. Share the app with the committee

**Quickest (APK over WhatsApp/Drive):**
```bash
flutter build apk --release
```
Share `build/app/outputs/flutter-apk/app-release.apk`. Members install it (Android will ask them to allow "install unknown apps"), register, and wait for your approval.

**Google Play Store (optional):**
1. Create an upload keystore and configure signing: https://docs.flutter.dev/deployment/android#signing-the-app
2. Build the bundle with `flutter build appbundle --release`.
3. In Google Play Console (one-time US$25 fee), create the app and upload the `.aab` to **Internal testing**. Add committee members' emails as testers. This avoids a full public review.

**iPhone users:** building for iOS needs a Mac with Xcode and an Apple Developer account (US$99/year). Add these keys to `ios/Runner/Info.plist`:
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Attach payment screenshots and bills.</string>
<key>NSCameraUsageDescription</key>
<string>Take a photo of a bill or receipt.</string>
```
Then run `flutterfire configure` with ios ticked, `flutter build ipa`, and distribute via TestFlight.

---

## Project structure

```
lib/
  main.dart                     app start, Firebase init
  theme.dart                    colours (saffron / maroon), fonts
  models.dart                   Member, Festival, Session, formatting helpers
  services/db.dart              Firestore collections, screenshot save/load
  services/proof_picker.dart    pick + compress screenshots
  widgets/common.dart           cards, day strip, status pills, proof image
  screens/
    auth_gate.dart              login → approval → app
    login_screen.dart           sign in / register / forgot password
    pending_screen.dart         waiting-for-approval + profile setup
    home_screen.dart            tiles, totals, WhatsApp summary
    activities_screen.dart      day-wise schedule
    pooja_screen.dart           pooja seva sign-up by date and slot
    expenses_screen.dart        expense list + add expense
    contributions_screen.dart   contributions, screenshot, admin verify
    members_screen.dart         approve members, admin roles
    settings_screen.dart        festival settings (admin)
firestore.rules                 server-side access control
```

## Firestore data

| Collection | Fields |
|---|---|
| `users/{uid}` | name, phone, email, role (`member`/`admin`), status (`pending`/`approved`/`rejected`) |
| `settings/festival` | title, startDate, days, poojaSlots[], upiId |
| `activities` | date (`yyyy-MM-dd`), time (`HH:mm`), title, place, coordinator, notes, createdBy |
| `poojaSignups` | date, slot, name, note, createdBy |
| `expenses` | date, item, amount, category, mode, paidBy, note, proofId, createdBy |
| `contributions` | date, name, amount, mode, txnRef, note, proofId, status (`pending`/`verified`/`rejected`), verifiedBy |
| `proofs` | image (base64 JPEG), uploadedBy |

## Ideas for version 2

- Push notifications before each aarti (Firebase Cloud Messaging)
- Export expenses and contributions to Excel/PDF for the final audit
- Photo gallery of the celebrations
- Telugu / Hindi language option
- Samagri (pooja items) checklist with "bought / pending"
