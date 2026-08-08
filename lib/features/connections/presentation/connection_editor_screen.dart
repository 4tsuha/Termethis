import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../application/connection_profiles_controller.dart';
import '../domain/connection_profile.dart';

class ConnectionEditorScreen extends ConsumerStatefulWidget {
  const ConnectionEditorScreen({super.key, this.profileId});

  final String? profileId;

  @override
  ConsumerState<ConnectionEditorScreen> createState() =>
      _ConnectionEditorScreenState();
}

class _ConnectionEditorScreenState
    extends ConsumerState<ConnectionEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  ConnectionProfile? _existing;

  @override
  void initState() {
    super.initState();
    final profiles = ref.read(connectionProfilesProvider);
    for (final profile in profiles) {
      if (profile.id == widget.profileId) {
        _existing = profile;
        break;
      }
    }
    _nameController = TextEditingController(text: _existing?.name ?? '');
    _hostController = TextEditingController(text: _existing?.host ?? '');
    _portController = TextEditingController(
      text: (_existing?.port ?? 22).toString(),
    );
    _usernameController = TextEditingController(
      text: _existing?.username ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? l10n.addConnection : l10n.edit),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.connectionName,
                  hintText: l10n.connectionNameHint,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) => _required(value, l10n),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _hostController,
                decoration: InputDecoration(
                  labelText: l10n.host,
                  hintText: l10n.hostHint,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                validator: (value) => _required(value, l10n),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: l10n.port,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  final port = int.tryParse(value ?? '');
                  if (port == null || port < 1 || port > 65535) {
                    return l10n.invalidPort;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: l10n.username,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                autocorrect: false,
                validator: (value) => _required(value, l10n),
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AuthenticationType>(
                initialValue: AuthenticationType.passwordOrInteractive,
                decoration: InputDecoration(
                  labelText: l10n.authentication,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: AuthenticationType.passwordOrInteractive,
                    child: Text(l10n.passwordAuthentication),
                  ),
                ],
                onChanged: (_) {},
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(l10n.save),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value, AppLocalizations l10n) {
    return value == null || value.trim().isEmpty ? l10n.requiredField : null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final id =
        _existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    ref
        .read(connectionProfilesProvider.notifier)
        .save(
          ConnectionProfile(
            id: id,
            name: _nameController.text.trim(),
            host: _hostController.text.trim(),
            port: int.parse(_portController.text),
            username: _usernameController.text.trim(),
          ),
        );
    context.pop();
  }
}
