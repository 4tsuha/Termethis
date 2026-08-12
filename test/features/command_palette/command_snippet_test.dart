import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/command_palette/domain/command_snippet.dart';

void main() {
  test('既定値と秘密変数を展開する', () {
    const source =
        'curl -p \${port:8080} -H "Token: \${secret:token}" \${path}';
    final variables = commandVariables(source);

    expect(variables, hasLength(3));
    expect(
      variables.singleWhere((item) => item.name == 'token').isSecret,
      isTrue,
    );
    expect(
      expandCommand(source, {'path': '/health', 'secret:token': 'sensitive'}),
      'curl -p 8080 -H "Token: sensitive" /health',
    );
  });

  test('保存JSONは秘密変数の入力値を持たない', () {
    const snippet = CommandSnippet(
      id: 'health',
      title: 'Health',
      command: 'curl -H "Token: \${secret:token}" localhost',
    );

    expect(snippet.toJson().toString(), isNot(contains('sensitive')));
    expect(CommandSnippet.fromJson(snippet.toJson()), isNotNull);
  });
}
