import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyALzSCpgK2e0u2nBUXbLMPcw0BG6UwRhY0',
    appId: '1:35493200393:web:abc123def456',
    messagingSenderId: '35493200393',
    projectId: 'thanks-everyday',
    authDomain: 'thanks-everyday.firebaseapp.com',
    storageBucket: 'thanks-everyday.firebasestorage.app',
    measurementId: 'G-ABCDEFGHIJ',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyALzSCpgK2e0u2nBUXbLMPcw0BG6UwRhY0',
    appId: '1:35493200393:android:love_everyday_child_app',
    messagingSenderId: '35493200393',
    projectId: 'thanks-everyday',
    storageBucket: 'thanks-everyday.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyALzSCpgK2e0u2nBUXbLMPcw0BG6UwRhY0',
    appId: '1:35493200393:ios:abc123def456',
    messagingSenderId: '35493200393',
    projectId: 'thanks-everyday',
    storageBucket: 'thanks-everyday.firebasestorage.app',
    iosBundleId: 'com.thousandemfla.love_everyday',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyALzSCpgK2e0u2nBUXbLMPcw0BG6UwRhY0',
    appId: '1:35493200393:macos:abc123def456',
    messagingSenderId: '35493200393',
    projectId: 'thanks-everyday',
    storageBucket: 'thanks-everyday.firebasestorage.app',
    iosBundleId: 'com.thousandemfla.love_everyday',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyALzSCpgK2e0u2nBUXbLMPcw0BG6UwRhY0',
    appId: '1:35493200393:windows:abc123def456',
    messagingSenderId: '35493200393',
    projectId: 'thanks-everyday',
    storageBucket: 'thanks-everyday.firebasestorage.app',
  );
}