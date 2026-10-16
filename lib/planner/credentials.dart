import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const secureStore = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
