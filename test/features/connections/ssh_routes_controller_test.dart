import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/application/ssh_routes_controller.dart';
import 'package:termethis/features/connections/domain/ssh_route_configuration.dart';

void main() {
  test('複数段の踏み台順序を保存する', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(sshRoutesProvider.future);

    await container
        .read(sshRoutesProvider.notifier)
        .saveRoute(
          const SshRouteConfiguration(
            profileId: 'target',
            jumpProfileIds: ['jump-a', 'jump-b'],
          ),
        );

    expect(
      container
          .read(sshRoutesProvider.notifier)
          .routeFor('target')
          ?.jumpProfileIds,
      ['jump-a', 'jump-b'],
    );
  });

  test('間接的なProxyJump循環を拒否する', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(sshRoutesProvider.future);
    final notifier = container.read(sshRoutesProvider.notifier);
    await notifier.saveRoute(
      const SshRouteConfiguration(profileId: 'a', jumpProfileIds: ['b']),
    );
    await notifier.saveRoute(
      const SshRouteConfiguration(profileId: 'b', jumpProfileIds: ['c']),
    );

    expect(
      () => notifier.saveRoute(
        const SshRouteConfiguration(profileId: 'c', jumpProfileIds: ['a']),
      ),
      throwsA(isA<SshRouteCycleException>()),
    );
  });
}
