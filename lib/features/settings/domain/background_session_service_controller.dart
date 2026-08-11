abstract interface class BackgroundSessionServiceController {
  Future<void> setRunning(bool running);
}

class NoopBackgroundSessionServiceController
    implements BackgroundSessionServiceController {
  const NoopBackgroundSessionServiceController();

  @override
  Future<void> setRunning(bool running) async {}
}
