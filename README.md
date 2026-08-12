# Termethis

<img src="assets/branding/termethis-icon-source.png" alt="Termethis app icon" width="128">

完全日本語対応のAndroid向けSSH・RDP・VNC・FTPクライアントです。

[Android CI](.github/workflows/android.yml)

## 主な機能

- xterm.js WebGLを既定にした、vim・neovim・tmux・htop・ncurses向けSSHターミナル
- libvtermを使うAndroidネイティブ省メモリ描画へ切り替え可能
- releaseビルドのネイティブ描画で接続中150MiB以下を目標とするメモリ設計
- 日本語IME、UTF-8、CJK文字幅に対応した入出力
- 非表示タブの描画ビューを解放し、ANSIスナップショットと受信差分から画面を復元
- Cascadia Mono／JetBrains Mono、CJK、絵文字、Nerd Fonts Symbolsによる等幅表示
- Noto Sans JP、Koruri、Mejiro、Roboto、Moralerspace、Source Code Pro、JetBrains Monoから選べる画面フォント
- Cascadia MonoとJetBrains Monoから選べるターミナルフォント
- DriftとSQLiteによるSSH接続先とknown_hostsの永続保存
- 同じ接続先も並行利用できるSSH複数タブ・複数セッション
- SSH・Mosh・RDP・VNC・Shizuku Shellを同じ接続タブで管理
- アプリ再起動後に切断状態で復元する接続タブ
- シェル／tmux／zellij／screen向け検索ボタンとOSC 133対応の出力コピー
- TUIマウス、長押し右クリック、対応プロンプト内のタップ移動
- タブバー、画面スリープ抑止、IME表示時リサイズの個別設定
- Android KeystoreとAES-256-GCMによる秘密鍵保管、OpenSSH秘密鍵認証
- 端末認証で保護できるCredential Vaultと、独立したSSHパスワード保存設定
- 複数段ProxyJump、ローカルポート転送、SOCKS5動的転送
- 変数・秘密変数・送信前確認に対応したコマンドパレット
- RustによるSSHパケット処理、鍵交換、認証、PTY、複数セッション管理
- RustによるSFTPファイル操作と上限付き受信バッファ・バックプレッシャー
- ホームの接続先としてSSH・RDP・VNCを一元管理
- IronRDPとネイティブVulkan Surfaceによるアプリ内RDP、対応アプリへVNC URIを渡すリモートデスクトップ連携
- 接続先ごとのWake on LAN設定とMagic Packet送信
- ホーム、接続、ファイル、設定を切り替えるボトムナビゲーション
- FTP、FTPES、FTPS、SFTP接続と複数タブ
- パンくずによる階層移動、フォルダー優先の一覧表示
- フォルダー作成、名前変更、ファイルと空フォルダーの削除
- 適応・バランス・最大から選べるAndroidネイティブのリフレッシュレート制御
- 2,000〜100,000行から選べるスクロールバック
- 600dp以上でNavigationRailへ切り替わるレスポンシブUI
- 明示設定時だけ接続中に動くバックグラウンドSSH通知

平文FTPでは認証情報と通信内容が暗号化されません。可能な接続先ではSFTP、FTPES、FTPSのいずれかを使用してください。

SSHセッションの保存対象はタブID、接続先ID、表示名だけです。SSH通信、端末の表示内容、パスワード、秘密鍵は保存せず、アプリのプロセス再生成後は切断状態から利用者が再接続します。

Moshは接続プロフィールと統合タブUIを準備済みですが、Mosh/SSPクライアントは未実装です。公式Mosh実装のライセンスとAndroid向け保守方法が確定するまで、不完全な独自プロトコル実装は同梱しません。SSHリモートポートフォワーディングも未実装です。秘密鍵デコードはCPU機能を実行時診断しますが、SVE/SVE2の採用基準を満たす実測がないため現在はportable経路を使用します。

RDPはIronRDPでアプリ内接続し、デコード画面を中間フレームへ複製したりDartへ渡したりせず、AndroidのネイティブVulkan Surfaceへ提示します。接続時に入力したパスワードは保存しません。VNCはAndroidの対応クライアントを起動し、接続先とユーザー名だけを渡します。

## 開発

Flutter 3.44.9とDart 3.12.2を使用します。
SSH・SFTPコアにはRust 1.96.0を使用し、`flutter_rust_bridge`でFlutterへ接続します。
ネイティブ端末はConnectBot termlib＋libvtermと、Termux terminal-emulator＋terminal-viewを選択できます。ConnectBot側はsubmoduleで固定しているため、初回取得はsubmoduleを含めて行ってください。Termux側はJitPackの`0.118.0`へ固定しています。
AndroidビルドにはSDK版CMake 3.31.6とNDK 29.0.14206865が必要です。CIではSDK Managerから導入します。

```powershell
git submodule update --init --recursive
flutter pub get
cargo check --manifest-path rust/Cargo.toml
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

ネイティブ暗号のローカルビルドにはCMake、C/C++コンパイラー、NASMが必要です。GitHub Actionsではこれらをワークフロー内で導入します。

通常のWSL環境と分離したテスト用sshdを起動し、エミュレータだけを接続します。パスワードはテストのたびに指定し、アプリには保存しません。

```powershell
.\tool\wsl\setup_test_ssh.ps1 -Distro Ubuntu -Password '<一時テスト用パスワード>'
adb -s emulator-5554 reverse tcp:22222 tcp:22222
```

Termethisの接続先は`termethis-test@127.0.0.1:22222`にします。終了時は`.\tool\wsl\stop_test_ssh.ps1`を実行します。

ヘッドレスAVDでWebGLを検証する場合は`-gpu host`を使用してください。環境別の既知事項は[TESTING.md](TESTING.md)にまとめています。

WebGLの初期化やWebView通信に失敗した場合は、そのセッション画面だけネイティブ描画へ切り替わります。ネイティブ端末を初期化できない場合はWebGLへ切り替えます。設定値は変更しないため、次に端末画面を開いたときは選択した描画方式を再試行します。

設計と安全性は[ARCHITECTURE.md](ARCHITECTURE.md)、評価環境と実測結果は[TESTING.md](TESTING.md)を参照してください。

## 高リフレッシュレートの検証状況

既定の「適応」は固定Hzを要求せずOSに評価を任せます。「バランス」は通常60Hz相当で、タッチ、スクロール、端末出力中だけ高Hzを要求し、停止から約750ms後に戻します。「最大」だけが最高Hzを継続要求します。

省電力、熱制限、分割画面ではOSの判断を優先します。可変リフレッシュレート、高Hz、各種IME、デスクトップ表示、画面消灯中の接続維持は環境別に検証します。
