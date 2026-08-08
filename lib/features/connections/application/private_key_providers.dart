import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/ssh/android_private_key_importer.dart';
import '../domain/private_key_importer.dart';

final privateKeyImporterProvider = Provider<PrivateKeyImporter>(
  (ref) => const AndroidPrivateKeyImporter(),
);

final privateKeyValidatorProvider = Provider<PrivateKeyValidator>(
  (ref) => DartSshPrivateKeyValidator(),
);
