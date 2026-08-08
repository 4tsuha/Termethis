// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'SSHターミナル';

  @override
  String get connectionsTitle => '接続先';

  @override
  String get addConnection => '接続先を追加';

  @override
  String get emptyConnectionsTitle => '接続先がありません';

  @override
  String get emptyConnectionsMessage => '右下の追加ボタンからSSHサーバーを登録してください。';

  @override
  String get edit => '編集';

  @override
  String get delete => '削除';

  @override
  String get cancel => 'キャンセル';

  @override
  String get save => '保存';

  @override
  String get connect => '接続';

  @override
  String get connectionName => '表示名';

  @override
  String get connectionNameHint => '自宅サーバー';

  @override
  String get host => 'ホスト名またはIPアドレス';

  @override
  String get hostHint => '192.168.1.10';

  @override
  String get port => 'ポート';

  @override
  String get username => 'ユーザー名';

  @override
  String get authentication => '認証';

  @override
  String get passwordAuthentication => 'パスワードまたは対話形式';

  @override
  String get requiredField => '入力してください。';

  @override
  String get invalidPort => '1から65535までの数値を入力してください。';

  @override
  String get deleteConnectionTitle => '接続先を削除しますか';

  @override
  String deleteConnectionMessage(String name) {
    return '$nameを一覧から削除します。';
  }

  @override
  String get passwordDialogTitle => '認証情報';

  @override
  String passwordDialogMessage(String target) {
    return '$targetへ接続するパスワードを入力してください。端末には保存しません。';
  }

  @override
  String get password => 'パスワード';

  @override
  String get hostKeyDialogTitle => 'ホスト鍵の確認';

  @override
  String get hostKeyDialogMessage =>
      'このサーバーは初めて接続する相手です。管理者から案内されたフィンガープリントと一致することを確認してください。';

  @override
  String get hostKeyAlgorithm => 'アルゴリズム';

  @override
  String get hostKeyFingerprint => 'SHA-256フィンガープリント';

  @override
  String get trustAndConnect => '登録して接続';

  @override
  String get reject => '接続しない';

  @override
  String get interactiveAuthenticationTitle => '追加認証';

  @override
  String get interactiveAuthenticationMessage => 'サーバーから追加の入力が求められています。';

  @override
  String get submit => '送信';

  @override
  String get statusIdle => '未接続';

  @override
  String get statusConnecting => '接続中';

  @override
  String get statusVerifyingHost => 'ホスト鍵を確認中';

  @override
  String get statusAuthenticating => '認証中';

  @override
  String get statusOpeningPty => 'ターミナルを準備中';

  @override
  String get statusConnected => '接続済み';

  @override
  String get statusClosing => '切断中';

  @override
  String get statusClosed => '切断済み';

  @override
  String get statusFailed => '接続できませんでした';

  @override
  String get statusReconnectPrompt => '接続が失われました';

  @override
  String get disconnect => '切断';

  @override
  String get retry => '再試行';

  @override
  String get closeSessionTitle => 'SSH接続を切断しますか';

  @override
  String get closeSessionMessage => '実行中のシェルは終了します。';

  @override
  String get failureDnsLookup => 'ホスト名を解決できませんでした。ホスト名とネットワークを確認してください。';

  @override
  String get failureConnectionRefused =>
      'サーバーに接続を拒否されました。ホスト名、ポート、SSHサービスを確認してください。';

  @override
  String get failureConnectionTimeout => '接続がタイムアウトしました。ネットワークと接続先を確認してください。';

  @override
  String get failureHostKeyRejected => 'ホスト鍵が承認されなかったため接続を中止しました。';

  @override
  String get failureHostKeyMismatch => '登録済みのホスト鍵と一致しません。安全を確認するまで接続できません。';

  @override
  String get failureAuthentication => '認証に失敗しました。ユーザー名または認証情報を確認してください。';

  @override
  String get failurePty => 'サーバーが対話型ターミナルを開始できませんでした。';

  @override
  String get failureRemoteClosed => 'サーバーが接続を終了しました。';

  @override
  String get failureNetwork => 'ネットワーク接続が失われました。';

  @override
  String get failureUnexpected => 'SSH接続で予期しないエラーが発生しました。';

  @override
  String get profileNotFound => '接続先が見つかりません。';

  @override
  String get paste => '貼り付け';

  @override
  String get pasteConfirmationTitle => 'この内容を貼り付けますか';

  @override
  String get pasteConfirmationMessage =>
      '複数行または長い文字列が含まれています。意図しないコマンド実行を防ぐため、内容を確認してください。';

  @override
  String get nothingToPaste => '貼り付ける文字列がありません。';

  @override
  String get stageOneNotice => '接続先とホスト鍵は、現在の起動中だけ保持されます。永続保存は次の実装段階で追加します。';

  @override
  String get navSsh => 'SSH';

  @override
  String get navFtp => 'FTP';

  @override
  String get navSettings => '設定';

  @override
  String get ftpTitle => 'FTPマネージャー';

  @override
  String get ftpAddTab => 'FTP接続';

  @override
  String get ftpEmptyTitle => 'FTPタブがありません';

  @override
  String get ftpEmptyMessage => '接続先を追加すると、サーバー内のフォルダーを階層表示できます。';

  @override
  String get ftpConnectionTitle => 'FTP接続を追加';

  @override
  String get ftpTabName => 'タブ名';

  @override
  String get ftpTabNameHint => 'Webサーバー';

  @override
  String get ftpSecurity => '接続方式';

  @override
  String get ftpPlain => 'FTP（暗号化なし）';

  @override
  String get ftpExplicitTls => 'FTPES（明示的TLS）';

  @override
  String get ftpImplicitTls => 'FTPS（暗黙的TLS）';

  @override
  String get ftpPlainWarning =>
      'FTPではパスワードと通信内容が暗号化されません。信頼できるネットワークでのみ使用してください。';

  @override
  String get ftpPasswordNotSaved => 'パスワードは端末に保存せず、このタブを閉じるまでだけ保持します。';

  @override
  String get ftpConnecting => '接続しています…';

  @override
  String get ftpLoading => '一覧を読み込んでいます…';

  @override
  String get ftpConnected => '接続済み';

  @override
  String get ftpConnectionFailed => 'FTPサーバーに接続できませんでした。接続情報とネットワークを確認してください。';

  @override
  String get ftpOperationFailed => 'FTP操作を完了できませんでした。権限と接続状態を確認してください。';

  @override
  String get ftpEmptyDirectory => 'このフォルダーは空です';

  @override
  String get ftpRefresh => '再読み込み';

  @override
  String get ftpNewFolder => '新しいフォルダー';

  @override
  String get ftpNewFolderTitle => 'フォルダーを作成';

  @override
  String get ftpFolderName => 'フォルダー名';

  @override
  String get ftpRename => '名前を変更';

  @override
  String get ftpRenameTitle => '名前を変更';

  @override
  String get ftpNewName => '新しい名前';

  @override
  String get ftpDeleteTitle => '削除しますか';

  @override
  String ftpDeleteMessage(String name) {
    return '$nameをFTPサーバーから削除します。この操作は取り消せません。';
  }

  @override
  String get ftpCloseTab => 'タブを閉じる';

  @override
  String get ftpCloseTabTitle => 'FTPタブを閉じますか';

  @override
  String get ftpCloseTabMessage => 'FTP接続を切断してタブを閉じます。';

  @override
  String get ftpRoot => 'ルート';

  @override
  String get ftpDirectory => 'フォルダー';

  @override
  String get ftpFile => 'ファイル';

  @override
  String get ftpUnknownSize => 'サイズ不明';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsTerminalSection => 'ターミナル';

  @override
  String get settingsTerminalFont => 'ターミナルフォント';

  @override
  String get settingsTerminalFontValue => 'Cascadia Mono（日本語: Noto Sans JP）';

  @override
  String get settingsFtpSection => 'FTP';

  @override
  String get settingsFtpSecurity => '安全な接続を推奨';

  @override
  String get settingsFtpSecurityMessage => '可能な接続先ではFTPESまたはFTPSを選んでください。';

  @override
  String get settingsAboutSection => 'アプリについて';

  @override
  String get settingsVersion => 'バージョン';

  @override
  String get settingsVersionValue => '0.1.0';
}
