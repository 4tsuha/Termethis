# Termethis 0.8.0-alpha7 検証記録

## 0.8.0-alpha7

- Flutter対象テスト: 39件成功、QEMU Mosh実接続1件は環境変数未設定のためスキップ
- UI回帰: 320dp／450dp／800dpの可変幅タブ、320dp設定一覧、接続先追加フォームを確認
- AVD: 縦画面と横画面で設定、接続一覧、接続タブ、接続先追加フォームにRenderFlex例外なし
- 静的解析: `flutter analyze`成功
- Rust: `cargo fmt --check`、`cargo check --manifest-path rust/Cargo.toml`成功
- APK: `versionName=0.8.0-alpha7`、`versionCode=2014`、arm64-v8a、署名v2検証済み
- APK SHA-256: `E19F0AD16A9DB4D76498C3CD605627176805CE31B789A0C541E774A2C680C67F`
- 未確認: Mosh実サーバー接続、RDP実接続性能、生体認証、SVE/SVE2実機経路

## 自動検証

- `flutter analyze`: 成功
- termlib Release難読化回帰テスト: 成功
- 対象Flutterテスト: 24件成功
- `cargo fmt`: 成功
- `cargo check`: 成功
- Android Kotlinコンパイル: 成功
- arm64 Release APKビルド: 成功
- `git diff --check`: 成功

## 0.8.0-alpha4

- ReleaseビルドでtermlibのJNI境界がR8により難読化されないよう修正
- AVDからQEMU DebianへED25519公開鍵認証で接続し、xterm.js WebGL、xterm.dart、termlib、Termuxの4方式でPTY表示とコマンド往復を確認
- termlib選択時の`NoSuchFieldError`が再発しないことと、アプリプロセスの生存を確認
- APK: `versionName=0.8.0-alpha4`、`versionCode=11`、arm64-v8a、署名v2検証済み

## 0.8.0-alpha5

- OpenSSH形式のRSA 2048-bit／4096-bit秘密鍵認証へ正式対応
- RSA 2048-bit未満をインポート検証と接続時の共通デコーダーで拒否
- RSA-SHA2-512とRSA-SHA2-256を使用し、SHA-1方式の`ssh-rsa`へ自動降格しない
- QEMU DebianへTermethisのRust `ssh_execute`からRSA 2048-bit／4096-bitで実接続し、コマンド往復を確認
- APK: `versionName=0.8.0-alpha5`、`versionCode=2012`（ABI分割後のarm64配布値）、署名v2検証済み
- APK SHA-256: `E85BBF9520B4048F36B2A3F9E196DC6A89856CCDA93F4A755845FCE020371122`

## 実装済み範囲

- ホーム、接続、ファイル、設定の4ナビゲーション
- SSH、Mosh、RDP、VNC、Shizuku Shellの共通タブモデル
- Android Keystoreと端末認証によるVault解錠ゲート
- 複数段ProxyJump
- ローカルポートフォワーディングとSOCKS5
- リモートポートフォワーディング
- SSH bootstrapとUDP SSP transportによるMosh通信
- Rust RFBクライアントによる内蔵VNC
- SSHコマンドパレット
- CPU機能の実行時検出とportable鍵デコード診断
- termlib／libvtermの標準Compose描画
- 同一スタイルのASCII連続セルと背景色の描画バッチ化

## termlib描画確認

- AVD上で公式Compose `Terminal`の生成を確認
- Termethisプロセスの`dumpsys meminfo`で`WebViews: 0`を確認
- 接続画面の生成とタブ切り替えでクラッシュなし
- 120Hz AVDからWSLの実PTYへ10万行を出力した比較では、GPU P95が13msから12ms、Slow issue draw commandsが32件から24件へ減少。総合P95は24msのままで、物理端末の性能達成値としては扱わない

## 未確認・制約

- 生体認証、端末認証、Keystore鍵無効化は実機未確認
- ProxyJumpとトンネルは実SSHサーバーで未確認
- リモートポートフォワーディングは実SSHサーバーで未確認。alphaでは1セッション1件
- WSLに`mosh-server`がないためMoshの実サーバー接続は未確認。暗号互換性とbootstrap解析は自動試験済み
- SVE/SVE2最適化は実測と採用基準を満たしていないため、portable経路のみ
- VNCのRFB接続、フレーム更新、ポインター入力は実VNCサーバーで未確認
- 実回線切り替え、120Hz、混在セッション時の150MB目標は実機未確認

エミュレーターでの成功は、実機性能目標の達成として扱わない。
