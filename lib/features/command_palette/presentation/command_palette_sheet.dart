import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/command_palette_controller.dart';
import '../domain/command_snippet.dart';

Future<String?> showCommandPalette(
  BuildContext context, {
  required String profileId,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => _CommandPaletteSheet(profileId: profileId),
);

class _CommandPaletteSheet extends ConsumerStatefulWidget {
  const _CommandPaletteSheet({required this.profileId});

  final String profileId;

  @override
  ConsumerState<_CommandPaletteSheet> createState() =>
      _CommandPaletteSheetState();
}

class _CommandPaletteSheetState extends ConsumerState<_CommandPaletteSheet> {
  final _queryController = TextEditingController();
  CommandSnippet? _selected;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snippets = ref.watch(commandSnippetsProvider).value ?? const [];
    final query = _queryController.text.trim().toLowerCase();
    final visible =
        snippets.where((item) {
          final applies =
              item.profileId == null || item.profileId == widget.profileId;
          final matches =
              query.isEmpty ||
              item.title.toLowerCase().contains(query) ||
              item.command.toLowerCase().contains(query) ||
              item.tags.any((tag) => tag.toLowerCase().contains(query));
          return applies && matches;
        }).toList()..sort((left, right) {
          if (left.favorite != right.favorite) return left.favorite ? -1 : 1;
          return left.title.compareTo(right.title);
        });
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'コマンドパレット',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'スニペットを追加',
                  onPressed: _addSnippet,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '選択後に変数を入力し、送信内容を確認します。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'スニペット、タグを検索',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('一致するスニペットがありません。'))
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final snippet = visible[index];
                        return ListTile(
                          selected: _selected?.id == snippet.id,
                          leading: Icon(
                            snippet.favorite ? Icons.star : Icons.code,
                          ),
                          title: Text(snippet.title),
                          subtitle: Text(
                            snippet.command,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => setState(() => _selected = snippet),
                          onLongPress: () => _removeSnippet(snippet),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _selected == null ? null : _preparePreview,
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('プレビュー'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSnippet() async {
    final snippet = await showDialog<CommandSnippet>(
      context: context,
      builder: (context) => _SnippetEditor(profileId: widget.profileId),
    );
    if (snippet == null) return;
    await ref.read(commandSnippetsProvider.notifier).save(snippet);
  }

  Future<void> _removeSnippet(CommandSnippet snippet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('スニペットを削除しますか'),
        content: Text(snippet.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(commandSnippetsProvider.notifier).remove(snippet.id);
      if (mounted) setState(() => _selected = null);
    }
  }

  Future<void> _preparePreview() async {
    final snippet = _selected;
    if (snippet == null) return;
    final variables = commandVariables(snippet.command);
    final values = <String, String>{};
    if (variables.isNotEmpty) {
      final entered = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => _VariableDialog(variables: variables),
      );
      if (entered == null || !mounted) return;
      values.addAll(entered);
    }
    final expanded = expandCommand(snippet.command, values);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('送信前の確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('次の文字列を現在のセッションへそのまま送信します。'),
            const SizedBox(height: 12),
            SelectableText(expanded),
            if (expanded.contains('\n')) ...[
              const SizedBox(height: 12),
              const Text('複数行のコマンドです。各改行も送信されます。'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('送信'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.pop(context, expanded);
  }
}

class _SnippetEditor extends StatefulWidget {
  const _SnippetEditor({required this.profileId});

  final String profileId;

  @override
  State<_SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends State<_SnippetEditor> {
  final _title = TextEditingController();
  final _command = TextEditingController();
  final _tags = TextEditingController();
  bool _allProfiles = true;
  bool _favorite = false;

  @override
  void dispose() {
    _title.dispose();
    _command.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('スニペットを追加'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: '名前'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _command,
            minLines: 2,
            maxLines: 6,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'コマンド',
              helperText: r'変数: ${name} / ${port:8080} / ${secret:token}',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(labelText: 'タグ（カンマ区切り）'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('すべての接続先で使用'),
            value: _allProfiles,
            onChanged: (value) => setState(() => _allProfiles = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('お気に入り'),
            value: _favorite,
            onChanged: (value) => setState(() => _favorite = value),
          ),
          const Text('秘密情報そのものは入力せず、secret変数を使用してください。'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        onPressed: () {
          final title = _title.text.trim();
          final command = _command.text;
          if (title.isEmpty || command.trim().isEmpty) return;
          Navigator.pop(
            context,
            CommandSnippet(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              title: title,
              command: command,
              profileId: _allProfiles ? null : widget.profileId,
              tags: _tags.text
                  .split(',')
                  .map((tag) => tag.trim())
                  .where((tag) => tag.isNotEmpty)
                  .toList(),
              favorite: _favorite,
            ),
          );
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _VariableDialog extends StatefulWidget {
  const _VariableDialog({required this.variables});

  final List<CommandVariable> variables;

  @override
  State<_VariableDialog> createState() => _VariableDialogState();
}

class _VariableDialogState extends State<_VariableDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final variable in widget.variables)
      '${variable.isSecret ? 'secret:' : ''}${variable.name}':
          TextEditingController(text: variable.defaultValue),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('変数を入力'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final variable in widget.variables)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller:
                    _controllers['${variable.isSecret ? 'secret:' : ''}${variable.name}'],
                obscureText: variable.isSecret,
                enableSuggestions: !variable.isSecret,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: variable.name,
                  helperText: variable.isSecret
                      ? 'この値は保存せず、履歴やログにも残しません。'
                      : null,
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          for (final entry in _controllers.entries) entry.key: entry.value.text,
        }),
        child: const Text('確認へ'),
      ),
    ],
  );
}
