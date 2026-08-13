// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Termethis';

  @override
  String get connectionsTitle => '接続先';

  @override
  String get addConnection => '接続先を追加';

  @override
  String get emptyConnectionsTitle => '接続先がありません';

  @override
  String get emptyConnectionsMessage => 'SSH、RDP、VNCの接続先を、右下の追加ボタンから登録できます。';

  @override
  String get loadConnectionsFailed => '接続先を読み込めませんでした。';

  @override
  String get edit => '編集';

  @override
  String get delete => '削除';

  @override
  String get cancel => 'キャンセル';

  @override
  String get discardChangesTitle => '変更を破棄しますか？';

  @override
  String get discardChangesMessage => '保存していない入力内容は失われます。';

  @override
  String get discardChanges => '破棄して戻る';

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
  String get privateKeyAuthentication => '秘密鍵';

  @override
  String get selectPrivateKey => '秘密鍵を選択';

  @override
  String get replacePrivateKey => '秘密鍵を置き換える';

  @override
  String get privateKeyNotSelected => '秘密鍵を選択してください。';

  @override
  String privateKeySelected(String name) {
    return '選択済み: $name';
  }

  @override
  String get keyPassphrase => '鍵のパスフレーズ';

  @override
  String get saveKeyPassphrase => 'パスフレーズを暗号化して保存';

  @override
  String get keyPassphraseTitle => '秘密鍵のパスフレーズ';

  @override
  String keyPassphraseMessage(String name) {
    return '$nameを復号するパスフレーズを入力してください。';
  }

  @override
  String get privateKeyInvalid => '秘密鍵を読み込めません。形式とパスフレーズを確認してください。';

  @override
  String get privateKeyTooLarge => '秘密鍵ファイルが大きすぎます。';

  @override
  String get requiredField => '入力してください。';

  @override
  String get invalidPort => '1から65535までの数値を入力してください。';

  @override
  String get wakeOnLanTitle => 'Wake on LAN';

  @override
  String get wakeOnLanDescription => '接続前にMagic Packetで端末を起動します。';

  @override
  String get wakeOnLanMacAddress => 'MACアドレス';

  @override
  String get wakeOnLanMacHint => '00:11:22:33:44:55';

  @override
  String get wakeOnLanBroadcastAddress => 'ブロードキャストアドレス';

  @override
  String get wakeOnLanBroadcastHint => '192.168.1.255';

  @override
  String get wakeOnLanPort => 'UDPポート';

  @override
  String get invalidMacAddress => '6バイトのMACアドレスを入力してください。';

  @override
  String get invalidIpv4Address => '有効なIPv4ブロードキャストアドレスを入力してください。';

  @override
  String get wakeOnLanSend => 'Wake on LANを送信';

  @override
  String wakeOnLanSent(String name) {
    return '$nameへMagic Packetを送信しました。';
  }

  @override
  String get wakeOnLanFailed => 'Magic Packetを送信できませんでした。ネットワーク設定を確認してください。';

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
  String get closeSessionMessage => 'このタブを閉じると、実行中のシェルも終了します。';

  @override
  String get closeSessionTab => 'セッションタブを閉じる';

  @override
  String get sessionRestoredMessage => '保存されたタブです。SSHセッションは切断されています。再接続してください。';

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
  String get failurePrivateKey => '秘密鍵を使用できません。鍵とパスフレーズを確認してください。';

  @override
  String get failureKeyPassphraseRequired => '秘密鍵のパスフレーズが必要です。';

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
  String get stageOneNotice => '接続先はこの端末に保存します。SSH秘密鍵は暗号化し、パスワードは保存しません。';

  @override
  String get navHome => 'ホーム';

  @override
  String get navConnections => '接続';

  @override
  String get navFiles => 'ファイル';

  @override
  String get navTerminal => 'ターミナル';

  @override
  String get navDesktop => 'デスクトップ';

  @override
  String get navFtp => 'FTP';

  @override
  String get navSettings => '設定';

  @override
  String get terminalSessionsTitle => 'ターミナル';

  @override
  String get terminalSessionsEmptyTitle => 'ターミナルは開かれていません';

  @override
  String get terminalSessionsEmptyMessage =>
      'ホームのSSH接続先からターミナルを開くと、ここで切り替えと終了ができます。';

  @override
  String get terminalSessionsOpenConnections => 'SSH接続先を開く';

  @override
  String get desktopTitle => 'デスクトップ';

  @override
  String get desktopEmptyTitle => 'デスクトップ接続がありません';

  @override
  String get desktopEmptyMessage => 'RDPまたはVNC接続先を右下の追加ボタンから登録できます。';

  @override
  String get chooseConnectionTypeTitle => '接続方式を選択';

  @override
  String get chooseConnectionTypeMessage =>
      '接続先で利用する方式を選んでください。あとから方式を変更する場合は、新しい接続先として登録します。';

  @override
  String get connectionTypeSsh => 'SSH';

  @override
  String get connectionTypeSshDescription => 'Termethis内のターミナルで、シェルやTUIを操作します。';

  @override
  String get connectionTypeSshCompactDescription => 'ターミナル接続';

  @override
  String get connectionTypeRdp => 'RDP';

  @override
  String get connectionTypeRdpDescription => 'Windowsのリモートデスクトップへアプリ内から接続します。';

  @override
  String get connectionTypeRdpCompactDescription => 'Windowsリモート';

  @override
  String get connectionTypeVnc => 'VNC';

  @override
  String get connectionTypeVncDescription => 'VNC対応アプリでリモート画面を開きます。';

  @override
  String get connectionTypeVncCompactDescription => 'リモート画面';

  @override
  String addTypedConnection(String type) {
    return '$type接続先を追加';
  }

  @override
  String get connectionMethod => '接続方式';

  @override
  String get usernameOptional => 'ユーザー名（任意）';

  @override
  String get externalAuthenticationNotice =>
      '認証は接続先アプリで行います。Termethisからパスワードは渡しません。';

  @override
  String get internalRdpAuthenticationNotice =>
      'パスワードは接続時に入力し、リモートデスクトップ接続にのみ使用します。接続先やログには保存しません。';

  @override
  String get remoteClientUnavailableTitle => '対応アプリが見つかりません';

  @override
  String get rdpClientUnavailableMessage =>
      'RDP接続にはRDP URIを開けるリモートデスクトップアプリが必要です。対応アプリをインストールしてから再試行してください。';

  @override
  String get vncClientUnavailableMessage =>
      'VNC接続にはvnc URIを開けるVNCクライアントが必要です。対応アプリをインストールしてから再試行してください。';

  @override
  String get remoteEndpointUnavailableTitle => '接続先に到達できません';

  @override
  String get rdpEndpointUnavailableMessage =>
      'RDPサービスへ接続できませんでした。接続先、ポート、ネットワークとWindows側のリモートデスクトップ設定を確認してください。';

  @override
  String get rdpProtocolMismatchTitle => 'RDPサービスを確認できません';

  @override
  String get rdpProtocolMismatchMessage =>
      '接続先からRDPの応答を確認できませんでした。指定したポートがリモートデスクトップ用か確認してください。';

  @override
  String get close => '閉じる';

  @override
  String get ftpTitle => 'FTPマネージャー';

  @override
  String get ftpAddTab => 'ファイル接続';

  @override
  String get ftpEmptyTitle => 'ファイル接続がありません';

  @override
  String get ftpEmptyMessage => 'FTP、FTPS、SFTPの接続先を追加すると、サーバー内のファイルを管理できます。';

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
  String get sftp => 'SFTP（SSHファイル転送）';

  @override
  String get sftpSecurityNotice =>
      'SFTPはSSHの暗号化通信とknown_hosts確認を使用します。パスワードは保存しません。';

  @override
  String get sftpSavedConnection => '保存済みSSH接続先（任意）';

  @override
  String sftpUsesPrivateKey(String name) {
    return '保存済み秘密鍵を使用: $name';
  }

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
  String get settingsTerminalFontValue =>
      'ターミナルの英数字・記号・罫線に使用します。日本語は画面フォントで補います。';

  @override
  String get settingsSelectTerminalFont => 'ターミナルフォントを選択';

  @override
  String get terminalFontCascadiaMono => 'Cascadia Mono';

  @override
  String get terminalFontJetBrainsMono => 'JetBrains Mono';

  @override
  String get settingsTerminalRenderer => 'ターミナルエミュレータ';

  @override
  String get settingsSelectTerminalRenderer => 'ターミナルエミュレータを選択';

  @override
  String get terminalRendererWebgl => 'xterm.js WebGL';

  @override
  String get terminalRendererWebglDescription =>
      '複雑なTUIと高速更新を優先します。WebViewを使うためメモリ使用量は増えます。WebGLを使えない場合はDOM描画へ切り替わります。';

  @override
  String get terminalRendererAlacritty => 'Flutter Alacritty';

  @override
  String get terminalRendererAlacrittyDescription =>
      'AlacrittyベースのRust VTエンジンとGPUグリフ描画を使用します。Android対応は実験段階のため、問題が起きた場合はxterm.js WebGLへ切り替わります。';

  @override
  String get terminalRendererConnectBot => 'termlib';

  @override
  String get terminalRendererConnectBotDescription =>
      'termlibとlibvtermの標準描画を使用します。IME、文字選択、スクロール、マウス入力をAndroid上で処理し、WebViewを使用しません。';

  @override
  String get terminalRendererTermux => 'Termux';

  @override
  String get terminalRendererTermuxDescription =>
      'Termuxのterminal-emulatorでANSI・UTF-8・IME互換性を優先します。Android Canvas描画のため、WebGLよりメモリを抑えられます。履歴は最大50,000行です。';

  @override
  String get settingsJapaneseFont => '画面フォント';

  @override
  String get settingsJapaneseFontMessage =>
      'Termethisの画面とターミナルの日本語表示で優先します。字形がない場合は端末のフォールバックフォントで補います。';

  @override
  String get settingsSelectFont => '画面フォントを選択';

  @override
  String get settingsRefreshRate => '画面の滑らかさ';

  @override
  String get settingsSelectRefreshRate => 'リフレッシュレート制御を選択';

  @override
  String get refreshRateAdaptive => '適応';

  @override
  String get refreshRateAdaptiveDescription =>
      'OSに評価を任せ、操作と端末出力中だけ高いフレームレートを要求します。';

  @override
  String get refreshRateBalanced => 'バランス';

  @override
  String get refreshRateBalancedDescription =>
      '通常は約60Hzで動作し、操作と大量出力中だけ高いフレームレートを要求します。';

  @override
  String get refreshRateMaximum => '最大';

  @override
  String get refreshRateMaximumDescription =>
      '対応する最高リフレッシュレートを継続して要求します。消費電力が増える場合があります。';

  @override
  String get settingsScrollbackLines => 'スクロールバック行数';

  @override
  String settingsScrollbackLinesValue(int lines) {
    return '新しく開くSSHセッションで$lines行を保持します。25,000行以上はWebGL描画を推奨し、行数に応じてメモリ使用量も増えます。';
  }

  @override
  String get settingsBackgroundSession => 'バックグラウンド接続モード';

  @override
  String get settingsBackgroundSessionDescription =>
      '接続中はTermethisの常駐通知を表示し、画面消灯中もSSH接続の維持を試みます。OSの省電力制御によって切断される場合があります。';

  @override
  String get settingsKeyManagementSection => 'キー管理';

  @override
  String get settingsKeyManagement => '秘密鍵と信頼済みホスト鍵';

  @override
  String get settingsKeyManagementDescription =>
      '接続先で使用する秘密鍵と、SSH接続時に登録したホスト鍵を確認します。';

  @override
  String get settingsCredentialProtection => '認証情報の保護';

  @override
  String get settingsCredentialProtectionDescription =>
      '秘密鍵と保存したパスフレーズは端末内で暗号化します。SSHパスワードは保存しません。';

  @override
  String get keyManagementTitle => 'キー管理';

  @override
  String get privateKeysTitle => '秘密鍵';

  @override
  String get privateKeysEmpty => '秘密鍵を使用する接続先はありません。接続先の編集画面から登録できます。';

  @override
  String get knownHostsTitle => '信頼済みホスト鍵';

  @override
  String get knownHostsEmpty => '登録済みのホスト鍵はありません。初回SSH接続時に確認して登録します。';

  @override
  String get removeKnownHostTitle => 'ホスト鍵を削除しますか';

  @override
  String get removeKnownHostMessage => '次回接続時に、この接続先のホスト鍵をもう一度確認します。';

  @override
  String get fontNotoSansJp => 'Noto Sans JP';

  @override
  String get fontKoruri => 'Koruri';

  @override
  String get fontMejiro => 'Mejiro';

  @override
  String get fontRoboto => 'Roboto';

  @override
  String get fontMoralerspace => 'Moralerspace';

  @override
  String get fontSourceCodePro => 'Source Code Pro';

  @override
  String get fontJetBrainsMono => 'JetBrains Mono';

  @override
  String get fontPreview => '日本語 ABC 123 の表示見本';

  @override
  String get settingsFtpSection => 'FTP';

  @override
  String get settingsFtpSecurity => '安全な接続を推奨';

  @override
  String get settingsFtpSecurityMessage =>
      '平文FTPは認証情報も暗号化されません。利用できる場合はSFTP、FTPES、FTPSを選んでください。';

  @override
  String get settingsAboutSection => 'Termethisについて';

  @override
  String get settingsVersion => 'バージョン';

  @override
  String get settingsVersionValue => '0.8.0-alpha3';

  @override
  String get settingsLicenses => 'オープンソースライセンス';
}
