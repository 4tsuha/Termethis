# VBTerminal

完全日本語対応のAndroid向けSSH・FTPクライアントです。

[![Android CI](https://github.com/hgzt23678/VBTerminal/actions/workflows/android.yml/badge.svg)](https://github.com/hgzt23678/VBTerminal/actions/workflows/android.yml)

## 主な機能

- 日本語IME、UTF-8、CJK文字幅に対応したSSHターミナル
- Cascadia MonoとNoto Sans JPによるWindows Terminal寄りの表示
- Noto Sans JP、Koruri、Mejiroから選べる日本語フォント
- DriftとSQLiteによるSSH接続先とknown_hostsの永続保存
- Android KeystoreとAES-256-GCMによる秘密鍵保管、OpenSSH秘密鍵認証
- SSH接続準備の並列化とPTY・Shell要求のパイプライン化
- 接続先ごとのWake on LAN設定とMagic Packet送信
- SSH、FTP、設定を切り替えるボトムナビゲーション
- FTP、FTPES、FTPS接続と複数タブ
- パンくずによる階層移動、フォルダー優先の一覧表示
- フォルダー作成、名前変更、ファイルと空フォルダーの削除
- Androidネイティブの可変リフレッシュレート要求

平文FTPでは認証情報と通信内容が暗号化されません。可能な接続先ではFTPESまたはFTPSを使用してください。

## 開発

Flutter 3.44.9とDart 3.12.2を使用します。

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

設計、安全性、性能、実機試験の詳細は[ARCHITECTURE.md](ARCHITECTURE.md)を参照してください。

## 高リフレッシュレートの検証状況

ネイティブ層は端末の最高対応リフレッシュレートをAndroidへ希望値として通知し、FlutterのアニメーションはVSyncに追従します。

SO-41Aは60Hzモードのみを公開するため、可変リフレッシュレート、120fps、144fpsの動作は未テストです。
