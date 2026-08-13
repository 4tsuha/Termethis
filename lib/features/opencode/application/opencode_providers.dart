import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/opencode_gateway.dart';
import '../../../infrastructure/opencode/http_opencode_gateway.dart';

final openCodeGatewayProvider = Provider<OpenCodeGateway>(
  (ref) => const HttpOpenCodeGateway(),
);
