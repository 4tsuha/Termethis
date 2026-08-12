# Termethis 0.8.0-alpha 検証記録

## 自動検証

- `flutter analyze`: 成功
- 対象Flutterテスト: 24件成功
- `cargo fmt`: 成功
- `cargo check`: 成功
- Android Kotlinコンパイル: 成功
- Debug APKビルド: 成功
- `git diff --check`: 成功

## 実装済み範囲

- ホーム、接続、ファイル、設定の4ナビゲーション
- SSH、Mosh、RDP、VNC、Shizuku Shellの共通タブモデル
- Android Keystoreと端末認証によるVault解錠ゲート
- 複数段ProxyJump
- ローカルポートフォワーディングとSOCKS5
- SSHコマンドパレット
- CPU機能の実行時検出とportable鍵デコード診断

## 未確認・制約

- 生体認証、端末認証、Keystore鍵無効化は実機未確認
- ProxyJumpとトンネルは実SSHサーバーで未確認
- リモートポートフォワーディングは未実装
- Moshは安全に統合できる保守可能なRust実装を確定できず、接続方式と制限表示まで
- SVE/SVE2最適化は実測と採用基準を満たしていないため、portable経路のみ
- VNCは既存の外部連携を維持し、アプリ内描画は未実装
- 実回線切り替え、120Hz、混在セッション時の150MB目標は実機未確認

エミュレーターでの成功は、実機性能目標の達成として扱わない。
