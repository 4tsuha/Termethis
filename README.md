<div align="center">

<img src="assets/branding/termethis-icon-source.png" alt="Termethis アイコン" width="160">

# Termethis

**スマホから、開発機のターミナルへ。**

完全日本語対応のAndroid向けSSH・RDP・VNC・SFTP・FTP・OpenCodeクライアントです。

[![Latest Release](https://img.shields.io/github/v/release/4tsuha/Termethis?label=Release&color=00d1b2)](https://github.com/4tsuha/Termethis/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform: Android](https://img.shields.io/badge/Platform-Android-3ddc84.svg?logo=android)](https://www.android.com/)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569b.svg?logo=flutter)](https://flutter.dev/)
[![Rust](https://img.shields.io/badge/Rust-1.96-dea584.svg?logo=rust)](https://www.rust-lang.org/)
[![CI](https://img.shields.io/github/actions/workflow/status/4tsuha/Termethis/android.yml?label=CI&logo=github)](.github/workflows/android.yml)

</div>

---

## これは何？

出先のスマホ・タブレットから、自宅や会社のPC・サーバーに接続して操作できるアプリです。

- 🇯🇵 **日本語完全対応** — IME(かな漢字変換)・日本語フォント・CJK表示にバッチリ対応
- 🖥️ **本格的な SSH ターミナル** — vimやtmuxなどの定番ツールも快適に動きます
- 📁 **ファイル転送** — スマホとPCの間でファイルを送受信
- 🖱️ **リモートデスクトップ** — RDP・VNCでPCの画面をそのまま操作

無料・オープンソース(GPL v3)です。インターネットを経由しないLAN内利用や、VPN・SSHトンネル経由で安全にお使いいただけます。

---

## ✨ 主な機能

| | 機能 | 説明 |
|---|---|---|
| ⌨️ | **日本語完全対応** | 日本語IME・UTF-8・CJK文字幅対応。Noto Sans JPほか和文フォントも選べます |
| 🖥️ | **高品質ターミナル** | vim・neovim・tmux・htopなど、マウス操作にも対応した本格派SSHターミナル |
| 🔒 | **安心の認証** | Android Keystore + AES-256-GCMで秘密鍵を保管。パスワード・鍵認証どちらも対応 |
| 📁 | **ファイル管理** | SFTP・FTP/FTPES/FTPSでファイル転送。進捗表示・キャンセル・再試行つき |
| 🖱️ | **リモートデスクトップ** | RDP(IronRDP+Vulkan)とVNC(内蔵クライアント)をアプリ内で直接表示 |
| 📑 | **マルチタブ** | 同じ接続先も並行利用できる複数タブ・複数セッション |
| 🌐 | **ネットワーク** | ProxyJump・ローカルポート転送・SOCKS5動的転送・Wake on LAN |
| 🤖 | **OpenCode連携** | OpenCode Serveをスマホから操作できるMaterial 3チャット |
| 🔔 | **バックグラウンド通知** | 明示設定時のみ、接続中でも通知で状態を確認 |
| 🎨 | **描画エンジン切替** | 標準Compose / Termux / xterm.js WebGL / xterm.dart から選択可能 |

### 接続タイプ

| 接続 | 説明 | 暗号化 |
|---|---|---|
| **SSH / Mosh** | ターミナル接続の定番 | ✅ 暗号化 |
| **SFTP** | 暗号化されたファイル転送 | ✅ 暗号化 |
| **RDP** | Windowsリモートデスクトップ | ✅ 暗号化 |
| **VNC** | 汎用リモートデスクトップ | 🔶 接続先依存 |
| **FTP / FTPES / FTPS** | 従来のファイル転送 | ⚠️ 平文FTPは非推奨 |
| **Shizuku Shell** | ローカル端末シェル | ➖ ローカル |
| **OpenCode Serve** | AIエージェント操作 | 🔶 SSHトンネル等で保護 |

> ⚠️ 平文FTPでは認証情報と通信内容が暗号化されません。可能な限りSFTP・FTPES・FTPSをご利用ください。

---

## 📱 対応環境

- **OS**: Android(推奨: 最新バージョン、600dp以上のタブレットではレスポンシブUIに自動切替)
- **言語**: 日本語 完全対応
- **フォント**: Noto Sans JP / Koruri / Mejiro / Roboto / Moralerspace ほか選択可

### セキュリティとプライバシー

- パスワード・秘密鍵・接続情報は**端末認証で保護できるCredential Vault**で保管
- SSHセッションの内容や端末の表示は**保存されません**。アプリ再起動後は切断状態から再接続
- バックアップには資格情報は含まれず、診断情報は匿名化して書き出せます
- OpenCode接続はインターネットへ直接公開せず、**信頼できるネットワーク・VPN・SSHトンネル経由**でご利用ください

---

## 🚀 はじめに

1. [Releases](https://github.com/4tsuha/Termethis/releases/latest) から最新版のAPKをダウンロード
2. インストールして起動、ホーム画面で「新規接続」をタップ
3. 接続先(ホスト・ポート・認証情報)を入力
4. ターミナル・ファイル・デスクトップ、お好みのモードで接続開始

---

## 🔧 開発者向け

### 必要環境

- Flutter 3.44.9 / Dart 3.12.2
- Rust 1.96.0(SSH・SFTPコア、`flutter_rust_bridge`経由で接続)
- Android SDK(CMake 3.31.6 / NDK 29.0.14206865)

### ビルド

```powershell
git submodule update --init --recursive
flutter pub get
cargo check --manifest-path rust/Cargo.toml
flutter analyze
flutter test
flutter build apk --debug
```

> xterm.jsアセットを変更した場合は、`Set-Location tool/web_terminal` で `npm install && npm run build` を実行してからAPKをビルドしてください。

### 詳細ドキュメント

- [設計と安全性](ARCHITECTURE.md)
- [評価環境と実測結果](TESTING.md)

---

## 📄 ライセンス

[GNU General Public License v3.0](LICENSE)

---

## 🙏 クレジット

Termethisは以下の優れたオープンソースソフトウェアに支えられています。

### ターミナルエミュレータ

| エンジン | 用途 | ライセンス |
|---|---|---|
| [ConnectBot termlib](https://github.com/connectbot/connectbot) + libvterm | 既定のネイティブ端末描画(Compose) | Apache-2.0 / MIT |
| [Termux terminal-emulator](https://github.com/termux/termux-app) | 代替端末エンジン | Apache-2.0 |
| [xterm.js](https://github.com/xtermjs/xterm.js) | WebGL高速描画(ブラウザ由来) | MIT |
| [xterm.dart](https://github.com/TerminalStudio/xterm.dart) | Flutter製端末エンジン | MIT |

### 通信ライブラリ

| ライブラリ | 用途 | ライセンス |
|---|---|---|
| [russh](https://github.com/warp-tech/russh) | Rust製SSH実装(パケット処理・鍵交換・認証・PTY) | Apache-2.0 / MIT |
| [russh-sftp](https://github.com/warp-tech/russh-sftp) | SSH上でのSFTPファイル転送 | Apache-2.0 / MIT |
| [IronRDP](https://github.com/Devolutions/IronRDP) | RDPクライアント実装 | Apache-2.0 / MIT |
| [vnc-rs](https://github.com/White-Oak/vnc-rs) | Rust製RFB(VNC)プロトコル実装 | MIT |

その他の依存ライブラリのライセンスは[assets/licenses](assets/licenses/)に掲載しています。
