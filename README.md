# VBTerminal

完全日本語対応のAndroid向けSSH・FTPクライアントです。

[![Android CI](https://github.com/hgzt23678/VBTerminal/actions/workflows/android.yml/badge.svg)](https://github.com/hgzt23678/VBTerminal/actions/workflows/android.yml)

## 主な機能

- xterm.js WebGLを既定にし、DOMとFlutter描画へ切り替えられるSSHターミナル
- 日本語IME、UTF-8、CJK文字幅に対応した入出力
- 非表示タブのWebViewを解放し、ANSIスナップショットと受信差分から画面を復元
- Cascadia MonoとNoto Sans JPによるWindows Terminal寄りの表示
- Noto Sans JP、Koruri、Mejiroから選べる日本語フォント
- DriftとSQLiteによるSSH接続先とknown_hostsの永続保存
- 同じ接続先も並行利用できるSSH複数タブ・複数セッション
- アプリ再起動後に切断状態で復元するSSHセッションタブ
- Android KeystoreとAES-256-GCMによる秘密鍵保管、OpenSSH秘密鍵認証
- SSH接続準備の並列化とPTY・Shell要求のパイプライン化
- 接続先ごとのWake on LAN設定とMagic Packet送信
- SSH、FTP、設定を切り替えるボトムナビゲーション
- FTP、FTPES、FTPS、SFTP接続と複数タブ
- パンくずによる階層移動、フォルダー優先の一覧表示
- フォルダー作成、名前変更、ファイルと空フォルダーの削除
- 適応・バランス・最大から選べるAndroidネイティブのリフレッシュレート制御
- 2,000・5,000・10,000行から選べるスクロールバック
- 600dp以上でNavigationRailへ切り替わるレスポンシブUI
- 明示設定時だけ接続中に動くバックグラウンドSSH通知

平文FTPでは認証情報と通信内容が暗号化されません。可能な接続先ではSFTP、FTPES、FTPSのいずれかを使用してください。

SSHセッションの保存対象はタブID、接続先ID、表示名だけです。SSH通信、端末の表示内容、パスワード、秘密鍵は保存せず、アプリのプロセス再生成後は切断状態から利用者が再接続します。

## 開発

Flutter 3.44.9とDart 3.12.2を使用します。

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

xterm.jsアセットを変更した場合は、APKビルド前に次を実行します。

```powershell
Set-Location tool/web_terminal
npm install
npm run build
```

### WSLを使うAndroid SSH試験

通常のWSL環境と分離したテスト用sshdを起動し、エミュレータだけを接続します。パスワードはテストのたびに指定し、アプリには保存しません。

```powershell
.\tool\wsl\setup_test_ssh.ps1 -Distro Ubuntu -Password '<一時テスト用パスワード>'
adb -s emulator-5554 reverse tcp:22222 tcp:22222
```

VBTerminalの接続先は`vbterminal-test@127.0.0.1:22222`にします。終了時は`.\tool\wsl\stop_test_ssh.ps1`を実行します。

ヘッドレスAVDでWebGLを検証する場合は`-gpu host`を使用してください。API 35のSwiftShaderではxterm.jsの文字テクスチャが欠けることを確認しています。

WebGLの初期化やWebView通信に失敗した場合は、そのセッション画面だけFlutter互換描画へ自動的に切り替わります。設定値は変更しないため、次に端末画面を開いたときはWebGLを再試行します。

設計、安全性、性能、実機試験の詳細は[ARCHITECTURE.md](ARCHITECTURE.md)を参照してください。

## 高リフレッシュレートの検証状況

既定の「適応」は固定Hzを要求せずOne UIへ選択を任せます。「バランス」は通常60Hz相当で、タッチ、スクロール、端末出力中だけ高Hzを要求し、停止から約750ms後に戻します。「最大」だけが最高Hzを継続要求します。

省電力、熱制限、分割画面ではAndroidの判断を優先します。SO-41Aの可変リフレッシュレートと、SCG26の120Hz、Samsung Keyboard、DeX、画面消灯中の接続維持は未テストです。
