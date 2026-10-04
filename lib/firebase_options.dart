import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

/// Firebase connection settings for project `vinayaka-utsav-2340e`.
/// These identify the project; they are not passwords - data is protected by
/// firestore.rules.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ? ios : android;

  /// From google-services.json (Android app com.vinayakautsav.vinayaka_utsav).
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyABTpTEPm3M-nH8Nl2IrFDsnLN-wWtfmB0',
    appId: '1:277745479815:android:a43ecc47d8c997fcab0822',
    messagingSenderId: '277745479815',
    projectId: 'vinayaka-utsav-2340e',
    storageBucket: 'vinayaka-utsav-2340e.firebasestorage.app',
  );

  /// From GoogleService-Info.plist (iOS app com.vinayakautsav.vinayakaUtsav).
  /// TODO: replace API_KEY and GOOGLE_APP_ID after registering the iOS app in Firebase.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'IOS_API_KEY_PENDING',
    appId: '1:277745479815:ios:pending',
    messagingSenderId: '277745479815',
    projectId: 'vinayaka-utsav-2340e',
    storageBucket: 'vinayaka-utsav-2340e.firebasestorage.app',
    iosBundleId: 'com.vinayakautsav.vinayakaUtsav',
  );
}
