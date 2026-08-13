import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('ja')];

  /// No description provided for @appTitle.
  ///
  /// In ja, this message translates to:
  /// **'Termethis'**
  String get appTitle;

  /// No description provided for @connectionsTitle.
  ///
  /// In ja, this message translates to:
  /// **'接続先'**
  String get connectionsTitle;

  /// No description provided for @addConnection.
  ///
  /// In ja, this message translates to:
  /// **'接続先を追加'**
  String get addConnection;

  /// No description provided for @emptyConnectionsTitle.
  ///
  /// In ja, this message translates to:
  /// **'接続先がありません'**
  String get emptyConnectionsTitle;

  /// No description provided for @emptyConnectionsMessage.
  ///
  /// In ja, this message translates to:
  /// **'SSH、RDP、VNCの接続先を、右下の追加ボタンから登録できます。'**
  String get emptyConnectionsMessage;

  /// No description provided for @loadConnectionsFailed.
  ///
  /// In ja, this message translates to:
  /// **'接続先を読み込めませんでした。'**
  String get loadConnectionsFailed;

  /// No description provided for @edit.
  ///
  /// In ja, this message translates to:
  /// **'編集'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In ja, this message translates to:
  /// **'削除'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get cancel;

  /// No description provided for @discardChangesTitle.
  ///
  /// In ja, this message translates to:
  /// **'変更を破棄しますか？'**
  String get discardChangesTitle;

  /// No description provided for @discardChangesMessage.
  ///
  /// In ja, this message translates to:
  /// **'保存していない入力内容は失われます。'**
  String get discardChangesMessage;

  /// No description provided for @discardChanges.
  ///
  /// In ja, this message translates to:
  /// **'破棄して戻る'**
  String get discardChanges;

  /// No description provided for @save.
  ///
  /// In ja, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @connect.
  ///
  /// In ja, this message translates to:
  /// **'接続'**
  String get connect;

  /// No description provided for @connectionName.
  ///
  /// In ja, this message translates to:
  /// **'表示名'**
  String get connectionName;

  /// No description provided for @connectionNameHint.
  ///
  /// In ja, this message translates to:
  /// **'自宅サーバー'**
  String get connectionNameHint;

  /// No description provided for @host.
  ///
  /// In ja, this message translates to:
  /// **'ホスト名またはIPアドレス'**
  String get host;

  /// No description provided for @hostHint.
  ///
  /// In ja, this message translates to:
  /// **'192.168.1.10'**
  String get hostHint;

  /// No description provided for @port.
  ///
  /// In ja, this message translates to:
  /// **'ポート'**
  String get port;

  /// No description provided for @username.
  ///
  /// In ja, this message translates to:
  /// **'ユーザー名'**
  String get username;

  /// No description provided for @authentication.
  ///
  /// In ja, this message translates to:
  /// **'認証'**
  String get authentication;

  /// No description provided for @passwordAuthentication.
  ///
  /// In ja, this message translates to:
  /// **'パスワードまたは対話形式'**
  String get passwordAuthentication;

  /// No description provided for @privateKeyAuthentication.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵'**
  String get privateKeyAuthentication;

  /// No description provided for @selectPrivateKey.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵を選択'**
  String get selectPrivateKey;

  /// No description provided for @replacePrivateKey.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵を置き換える'**
  String get replacePrivateKey;

  /// No description provided for @privateKeyNotSelected.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵を選択してください。'**
  String get privateKeyNotSelected;

  /// No description provided for @privateKeySelected.
  ///
  /// In ja, this message translates to:
  /// **'選択済み: {name}'**
  String privateKeySelected(String name);

  /// No description provided for @keyPassphrase.
  ///
  /// In ja, this message translates to:
  /// **'鍵のパスフレーズ'**
  String get keyPassphrase;

  /// No description provided for @saveKeyPassphrase.
  ///
  /// In ja, this message translates to:
  /// **'パスフレーズを暗号化して保存'**
  String get saveKeyPassphrase;

  /// No description provided for @keyPassphraseTitle.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵のパスフレーズ'**
  String get keyPassphraseTitle;

  /// No description provided for @keyPassphraseMessage.
  ///
  /// In ja, this message translates to:
  /// **'{name}を復号するパスフレーズを入力してください。'**
  String keyPassphraseMessage(String name);

  /// No description provided for @privateKeyInvalid.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵を読み込めません。形式とパスフレーズを確認してください。'**
  String get privateKeyInvalid;

  /// No description provided for @privateKeyTooLarge.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵ファイルが大きすぎます。'**
  String get privateKeyTooLarge;

  /// No description provided for @requiredField.
  ///
  /// In ja, this message translates to:
  /// **'入力してください。'**
  String get requiredField;

  /// No description provided for @invalidPort.
  ///
  /// In ja, this message translates to:
  /// **'1から65535までの数値を入力してください。'**
  String get invalidPort;

  /// No description provided for @wakeOnLanTitle.
  ///
  /// In ja, this message translates to:
  /// **'Wake on LAN'**
  String get wakeOnLanTitle;

  /// No description provided for @wakeOnLanDescription.
  ///
  /// In ja, this message translates to:
  /// **'接続前にMagic Packetで端末を起動します。'**
  String get wakeOnLanDescription;

  /// No description provided for @wakeOnLanMacAddress.
  ///
  /// In ja, this message translates to:
  /// **'MACアドレス'**
  String get wakeOnLanMacAddress;

  /// No description provided for @wakeOnLanMacHint.
  ///
  /// In ja, this message translates to:
  /// **'00:11:22:33:44:55'**
  String get wakeOnLanMacHint;

  /// No description provided for @wakeOnLanBroadcastAddress.
  ///
  /// In ja, this message translates to:
  /// **'ブロードキャストアドレス'**
  String get wakeOnLanBroadcastAddress;

  /// No description provided for @wakeOnLanBroadcastHint.
  ///
  /// In ja, this message translates to:
  /// **'192.168.1.255'**
  String get wakeOnLanBroadcastHint;

  /// No description provided for @wakeOnLanPort.
  ///
  /// In ja, this message translates to:
  /// **'UDPポート'**
  String get wakeOnLanPort;

  /// No description provided for @invalidMacAddress.
  ///
  /// In ja, this message translates to:
  /// **'6バイトのMACアドレスを入力してください。'**
  String get invalidMacAddress;

  /// No description provided for @invalidIpv4Address.
  ///
  /// In ja, this message translates to:
  /// **'有効なIPv4ブロードキャストアドレスを入力してください。'**
  String get invalidIpv4Address;

  /// No description provided for @wakeOnLanSend.
  ///
  /// In ja, this message translates to:
  /// **'Wake on LANを送信'**
  String get wakeOnLanSend;

  /// No description provided for @wakeOnLanSent.
  ///
  /// In ja, this message translates to:
  /// **'{name}へMagic Packetを送信しました。'**
  String wakeOnLanSent(String name);

  /// No description provided for @wakeOnLanFailed.
  ///
  /// In ja, this message translates to:
  /// **'Magic Packetを送信できませんでした。ネットワーク設定を確認してください。'**
  String get wakeOnLanFailed;

  /// No description provided for @deleteConnectionTitle.
  ///
  /// In ja, this message translates to:
  /// **'接続先を削除しますか'**
  String get deleteConnectionTitle;

  /// No description provided for @deleteConnectionMessage.
  ///
  /// In ja, this message translates to:
  /// **'{name}を一覧から削除します。'**
  String deleteConnectionMessage(String name);

  /// No description provided for @passwordDialogTitle.
  ///
  /// In ja, this message translates to:
  /// **'認証情報'**
  String get passwordDialogTitle;

  /// No description provided for @passwordDialogMessage.
  ///
  /// In ja, this message translates to:
  /// **'{target}へ接続するパスワードを入力してください。端末には保存しません。'**
  String passwordDialogMessage(String target);

  /// No description provided for @password.
  ///
  /// In ja, this message translates to:
  /// **'パスワード'**
  String get password;

  /// No description provided for @hostKeyDialogTitle.
  ///
  /// In ja, this message translates to:
  /// **'ホスト鍵の確認'**
  String get hostKeyDialogTitle;

  /// No description provided for @hostKeyDialogMessage.
  ///
  /// In ja, this message translates to:
  /// **'このサーバーは初めて接続する相手です。管理者から案内されたフィンガープリントと一致することを確認してください。'**
  String get hostKeyDialogMessage;

  /// No description provided for @hostKeyAlgorithm.
  ///
  /// In ja, this message translates to:
  /// **'アルゴリズム'**
  String get hostKeyAlgorithm;

  /// No description provided for @hostKeyFingerprint.
  ///
  /// In ja, this message translates to:
  /// **'SHA-256フィンガープリント'**
  String get hostKeyFingerprint;

  /// No description provided for @trustAndConnect.
  ///
  /// In ja, this message translates to:
  /// **'登録して接続'**
  String get trustAndConnect;

  /// No description provided for @reject.
  ///
  /// In ja, this message translates to:
  /// **'接続しない'**
  String get reject;

  /// No description provided for @interactiveAuthenticationTitle.
  ///
  /// In ja, this message translates to:
  /// **'追加認証'**
  String get interactiveAuthenticationTitle;

  /// No description provided for @interactiveAuthenticationMessage.
  ///
  /// In ja, this message translates to:
  /// **'サーバーから追加の入力が求められています。'**
  String get interactiveAuthenticationMessage;

  /// No description provided for @submit.
  ///
  /// In ja, this message translates to:
  /// **'送信'**
  String get submit;

  /// No description provided for @statusIdle.
  ///
  /// In ja, this message translates to:
  /// **'未接続'**
  String get statusIdle;

  /// No description provided for @statusConnecting.
  ///
  /// In ja, this message translates to:
  /// **'接続中'**
  String get statusConnecting;

  /// No description provided for @statusVerifyingHost.
  ///
  /// In ja, this message translates to:
  /// **'ホスト鍵を確認中'**
  String get statusVerifyingHost;

  /// No description provided for @statusAuthenticating.
  ///
  /// In ja, this message translates to:
  /// **'認証中'**
  String get statusAuthenticating;

  /// No description provided for @statusOpeningPty.
  ///
  /// In ja, this message translates to:
  /// **'ターミナルを準備中'**
  String get statusOpeningPty;

  /// No description provided for @statusConnected.
  ///
  /// In ja, this message translates to:
  /// **'接続済み'**
  String get statusConnected;

  /// No description provided for @statusClosing.
  ///
  /// In ja, this message translates to:
  /// **'切断中'**
  String get statusClosing;

  /// No description provided for @statusClosed.
  ///
  /// In ja, this message translates to:
  /// **'切断済み'**
  String get statusClosed;

  /// No description provided for @statusFailed.
  ///
  /// In ja, this message translates to:
  /// **'接続できませんでした'**
  String get statusFailed;

  /// No description provided for @statusReconnectPrompt.
  ///
  /// In ja, this message translates to:
  /// **'接続が失われました'**
  String get statusReconnectPrompt;

  /// No description provided for @disconnect.
  ///
  /// In ja, this message translates to:
  /// **'切断'**
  String get disconnect;

  /// No description provided for @retry.
  ///
  /// In ja, this message translates to:
  /// **'再試行'**
  String get retry;

  /// No description provided for @closeSessionTitle.
  ///
  /// In ja, this message translates to:
  /// **'SSH接続を切断しますか'**
  String get closeSessionTitle;

  /// No description provided for @closeSessionMessage.
  ///
  /// In ja, this message translates to:
  /// **'このタブを閉じると、実行中のシェルも終了します。'**
  String get closeSessionMessage;

  /// No description provided for @closeSessionTab.
  ///
  /// In ja, this message translates to:
  /// **'セッションタブを閉じる'**
  String get closeSessionTab;

  /// No description provided for @sessionRestoredMessage.
  ///
  /// In ja, this message translates to:
  /// **'保存されたタブです。SSHセッションは切断されています。再接続してください。'**
  String get sessionRestoredMessage;

  /// No description provided for @failureDnsLookup.
  ///
  /// In ja, this message translates to:
  /// **'ホスト名を解決できませんでした。ホスト名とネットワークを確認してください。'**
  String get failureDnsLookup;

  /// No description provided for @failureConnectionRefused.
  ///
  /// In ja, this message translates to:
  /// **'サーバーに接続を拒否されました。ホスト名、ポート、SSHサービスを確認してください。'**
  String get failureConnectionRefused;

  /// No description provided for @failureConnectionTimeout.
  ///
  /// In ja, this message translates to:
  /// **'接続がタイムアウトしました。ネットワークと接続先を確認してください。'**
  String get failureConnectionTimeout;

  /// No description provided for @failureHostKeyRejected.
  ///
  /// In ja, this message translates to:
  /// **'ホスト鍵が承認されなかったため接続を中止しました。'**
  String get failureHostKeyRejected;

  /// No description provided for @failureHostKeyMismatch.
  ///
  /// In ja, this message translates to:
  /// **'登録済みのホスト鍵と一致しません。安全を確認するまで接続できません。'**
  String get failureHostKeyMismatch;

  /// No description provided for @failureAuthentication.
  ///
  /// In ja, this message translates to:
  /// **'認証に失敗しました。ユーザー名または認証情報を確認してください。'**
  String get failureAuthentication;

  /// No description provided for @failurePrivateKey.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵を使用できません。鍵とパスフレーズを確認してください。'**
  String get failurePrivateKey;

  /// No description provided for @failureKeyPassphraseRequired.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵のパスフレーズが必要です。'**
  String get failureKeyPassphraseRequired;

  /// No description provided for @failurePty.
  ///
  /// In ja, this message translates to:
  /// **'サーバーが対話型ターミナルを開始できませんでした。'**
  String get failurePty;

  /// No description provided for @failureRemoteClosed.
  ///
  /// In ja, this message translates to:
  /// **'サーバーが接続を終了しました。'**
  String get failureRemoteClosed;

  /// No description provided for @failureNetwork.
  ///
  /// In ja, this message translates to:
  /// **'ネットワーク接続が失われました。'**
  String get failureNetwork;

  /// No description provided for @failureUnexpected.
  ///
  /// In ja, this message translates to:
  /// **'SSH接続で予期しないエラーが発生しました。'**
  String get failureUnexpected;

  /// No description provided for @profileNotFound.
  ///
  /// In ja, this message translates to:
  /// **'接続先が見つかりません。'**
  String get profileNotFound;

  /// No description provided for @paste.
  ///
  /// In ja, this message translates to:
  /// **'貼り付け'**
  String get paste;

  /// No description provided for @pasteConfirmationTitle.
  ///
  /// In ja, this message translates to:
  /// **'この内容を貼り付けますか'**
  String get pasteConfirmationTitle;

  /// No description provided for @pasteConfirmationMessage.
  ///
  /// In ja, this message translates to:
  /// **'複数行または長い文字列が含まれています。意図しないコマンド実行を防ぐため、内容を確認してください。'**
  String get pasteConfirmationMessage;

  /// No description provided for @nothingToPaste.
  ///
  /// In ja, this message translates to:
  /// **'貼り付ける文字列がありません。'**
  String get nothingToPaste;

  /// No description provided for @stageOneNotice.
  ///
  /// In ja, this message translates to:
  /// **'接続先はこの端末に保存します。SSH秘密鍵は暗号化し、パスワードは保存しません。'**
  String get stageOneNotice;

  /// No description provided for @navHome.
  ///
  /// In ja, this message translates to:
  /// **'ホーム'**
  String get navHome;

  /// No description provided for @navConnections.
  ///
  /// In ja, this message translates to:
  /// **'接続'**
  String get navConnections;

  /// No description provided for @navFiles.
  ///
  /// In ja, this message translates to:
  /// **'ファイル'**
  String get navFiles;

  /// No description provided for @navTerminal.
  ///
  /// In ja, this message translates to:
  /// **'ターミナル'**
  String get navTerminal;

  /// No description provided for @navDesktop.
  ///
  /// In ja, this message translates to:
  /// **'デスクトップ'**
  String get navDesktop;

  /// No description provided for @navFtp.
  ///
  /// In ja, this message translates to:
  /// **'FTP'**
  String get navFtp;

  /// No description provided for @navSettings.
  ///
  /// In ja, this message translates to:
  /// **'設定'**
  String get navSettings;

  /// No description provided for @terminalSessionsTitle.
  ///
  /// In ja, this message translates to:
  /// **'ターミナル'**
  String get terminalSessionsTitle;

  /// No description provided for @terminalSessionsEmptyTitle.
  ///
  /// In ja, this message translates to:
  /// **'ターミナルは開かれていません'**
  String get terminalSessionsEmptyTitle;

  /// No description provided for @terminalSessionsEmptyMessage.
  ///
  /// In ja, this message translates to:
  /// **'ホームのSSH接続先からターミナルを開くと、ここで切り替えと終了ができます。'**
  String get terminalSessionsEmptyMessage;

  /// No description provided for @terminalSessionsOpenConnections.
  ///
  /// In ja, this message translates to:
  /// **'SSH接続先を開く'**
  String get terminalSessionsOpenConnections;

  /// No description provided for @desktopTitle.
  ///
  /// In ja, this message translates to:
  /// **'デスクトップ'**
  String get desktopTitle;

  /// No description provided for @desktopEmptyTitle.
  ///
  /// In ja, this message translates to:
  /// **'デスクトップ接続がありません'**
  String get desktopEmptyTitle;

  /// No description provided for @desktopEmptyMessage.
  ///
  /// In ja, this message translates to:
  /// **'RDPまたはVNC接続先を右下の追加ボタンから登録できます。'**
  String get desktopEmptyMessage;

  /// No description provided for @chooseConnectionTypeTitle.
  ///
  /// In ja, this message translates to:
  /// **'接続方式を選択'**
  String get chooseConnectionTypeTitle;

  /// No description provided for @chooseConnectionTypeMessage.
  ///
  /// In ja, this message translates to:
  /// **'接続先で利用する方式を選んでください。あとから方式を変更する場合は、新しい接続先として登録します。'**
  String get chooseConnectionTypeMessage;

  /// No description provided for @connectionTypeSsh.
  ///
  /// In ja, this message translates to:
  /// **'SSH'**
  String get connectionTypeSsh;

  /// No description provided for @connectionTypeSshDescription.
  ///
  /// In ja, this message translates to:
  /// **'Termethis内のターミナルで、シェルやTUIを操作します。'**
  String get connectionTypeSshDescription;

  /// No description provided for @connectionTypeSshCompactDescription.
  ///
  /// In ja, this message translates to:
  /// **'ターミナル接続'**
  String get connectionTypeSshCompactDescription;

  /// No description provided for @connectionTypeRdp.
  ///
  /// In ja, this message translates to:
  /// **'RDP'**
  String get connectionTypeRdp;

  /// No description provided for @connectionTypeRdpDescription.
  ///
  /// In ja, this message translates to:
  /// **'Windowsのリモートデスクトップへアプリ内から接続します。'**
  String get connectionTypeRdpDescription;

  /// No description provided for @connectionTypeRdpCompactDescription.
  ///
  /// In ja, this message translates to:
  /// **'Windowsリモート'**
  String get connectionTypeRdpCompactDescription;

  /// No description provided for @connectionTypeVnc.
  ///
  /// In ja, this message translates to:
  /// **'VNC'**
  String get connectionTypeVnc;

  /// No description provided for @connectionTypeVncDescription.
  ///
  /// In ja, this message translates to:
  /// **'VNC対応アプリでリモート画面を開きます。'**
  String get connectionTypeVncDescription;

  /// No description provided for @connectionTypeVncCompactDescription.
  ///
  /// In ja, this message translates to:
  /// **'リモート画面'**
  String get connectionTypeVncCompactDescription;

  /// No description provided for @addTypedConnection.
  ///
  /// In ja, this message translates to:
  /// **'{type}接続先を追加'**
  String addTypedConnection(String type);

  /// No description provided for @connectionMethod.
  ///
  /// In ja, this message translates to:
  /// **'接続方式'**
  String get connectionMethod;

  /// No description provided for @usernameOptional.
  ///
  /// In ja, this message translates to:
  /// **'ユーザー名（任意）'**
  String get usernameOptional;

  /// No description provided for @externalAuthenticationNotice.
  ///
  /// In ja, this message translates to:
  /// **'認証は接続先アプリで行います。Termethisからパスワードは渡しません。'**
  String get externalAuthenticationNotice;

  /// No description provided for @internalRdpAuthenticationNotice.
  ///
  /// In ja, this message translates to:
  /// **'パスワードは接続時に入力し、リモートデスクトップ接続にのみ使用します。接続先やログには保存しません。'**
  String get internalRdpAuthenticationNotice;

  /// No description provided for @remoteClientUnavailableTitle.
  ///
  /// In ja, this message translates to:
  /// **'対応アプリが見つかりません'**
  String get remoteClientUnavailableTitle;

  /// No description provided for @rdpClientUnavailableMessage.
  ///
  /// In ja, this message translates to:
  /// **'RDP接続にはRDP URIを開けるリモートデスクトップアプリが必要です。対応アプリをインストールしてから再試行してください。'**
  String get rdpClientUnavailableMessage;

  /// No description provided for @vncClientUnavailableMessage.
  ///
  /// In ja, this message translates to:
  /// **'VNC接続にはvnc URIを開けるVNCクライアントが必要です。対応アプリをインストールしてから再試行してください。'**
  String get vncClientUnavailableMessage;

  /// No description provided for @remoteEndpointUnavailableTitle.
  ///
  /// In ja, this message translates to:
  /// **'接続先に到達できません'**
  String get remoteEndpointUnavailableTitle;

  /// No description provided for @rdpEndpointUnavailableMessage.
  ///
  /// In ja, this message translates to:
  /// **'RDPサービスへ接続できませんでした。接続先、ポート、ネットワークとWindows側のリモートデスクトップ設定を確認してください。'**
  String get rdpEndpointUnavailableMessage;

  /// No description provided for @rdpProtocolMismatchTitle.
  ///
  /// In ja, this message translates to:
  /// **'RDPサービスを確認できません'**
  String get rdpProtocolMismatchTitle;

  /// No description provided for @rdpProtocolMismatchMessage.
  ///
  /// In ja, this message translates to:
  /// **'接続先からRDPの応答を確認できませんでした。指定したポートがリモートデスクトップ用か確認してください。'**
  String get rdpProtocolMismatchMessage;

  /// No description provided for @close.
  ///
  /// In ja, this message translates to:
  /// **'閉じる'**
  String get close;

  /// No description provided for @ftpTitle.
  ///
  /// In ja, this message translates to:
  /// **'FTPマネージャー'**
  String get ftpTitle;

  /// No description provided for @ftpAddTab.
  ///
  /// In ja, this message translates to:
  /// **'ファイル接続'**
  String get ftpAddTab;

  /// No description provided for @ftpEmptyTitle.
  ///
  /// In ja, this message translates to:
  /// **'ファイル接続がありません'**
  String get ftpEmptyTitle;

  /// No description provided for @ftpEmptyMessage.
  ///
  /// In ja, this message translates to:
  /// **'FTP、FTPS、SFTPの接続先を追加すると、サーバー内のファイルを管理できます。'**
  String get ftpEmptyMessage;

  /// No description provided for @ftpConnectionTitle.
  ///
  /// In ja, this message translates to:
  /// **'FTP接続を追加'**
  String get ftpConnectionTitle;

  /// No description provided for @ftpTabName.
  ///
  /// In ja, this message translates to:
  /// **'タブ名'**
  String get ftpTabName;

  /// No description provided for @ftpTabNameHint.
  ///
  /// In ja, this message translates to:
  /// **'Webサーバー'**
  String get ftpTabNameHint;

  /// No description provided for @ftpSecurity.
  ///
  /// In ja, this message translates to:
  /// **'接続方式'**
  String get ftpSecurity;

  /// No description provided for @ftpPlain.
  ///
  /// In ja, this message translates to:
  /// **'FTP（暗号化なし）'**
  String get ftpPlain;

  /// No description provided for @ftpExplicitTls.
  ///
  /// In ja, this message translates to:
  /// **'FTPES（明示的TLS）'**
  String get ftpExplicitTls;

  /// No description provided for @ftpImplicitTls.
  ///
  /// In ja, this message translates to:
  /// **'FTPS（暗黙的TLS）'**
  String get ftpImplicitTls;

  /// No description provided for @sftp.
  ///
  /// In ja, this message translates to:
  /// **'SFTP（SSHファイル転送）'**
  String get sftp;

  /// No description provided for @sftpSecurityNotice.
  ///
  /// In ja, this message translates to:
  /// **'SFTPはSSHの暗号化通信とknown_hosts確認を使用します。パスワードは保存しません。'**
  String get sftpSecurityNotice;

  /// No description provided for @sftpSavedConnection.
  ///
  /// In ja, this message translates to:
  /// **'保存済みSSH接続先（任意）'**
  String get sftpSavedConnection;

  /// No description provided for @sftpUsesPrivateKey.
  ///
  /// In ja, this message translates to:
  /// **'保存済み秘密鍵を使用: {name}'**
  String sftpUsesPrivateKey(String name);

  /// No description provided for @ftpPlainWarning.
  ///
  /// In ja, this message translates to:
  /// **'FTPではパスワードと通信内容が暗号化されません。信頼できるネットワークでのみ使用してください。'**
  String get ftpPlainWarning;

  /// No description provided for @ftpPasswordNotSaved.
  ///
  /// In ja, this message translates to:
  /// **'パスワードは端末に保存せず、このタブを閉じるまでだけ保持します。'**
  String get ftpPasswordNotSaved;

  /// No description provided for @ftpConnecting.
  ///
  /// In ja, this message translates to:
  /// **'接続しています…'**
  String get ftpConnecting;

  /// No description provided for @ftpLoading.
  ///
  /// In ja, this message translates to:
  /// **'一覧を読み込んでいます…'**
  String get ftpLoading;

  /// No description provided for @ftpConnected.
  ///
  /// In ja, this message translates to:
  /// **'接続済み'**
  String get ftpConnected;

  /// No description provided for @ftpConnectionFailed.
  ///
  /// In ja, this message translates to:
  /// **'FTPサーバーに接続できませんでした。接続情報とネットワークを確認してください。'**
  String get ftpConnectionFailed;

  /// No description provided for @ftpOperationFailed.
  ///
  /// In ja, this message translates to:
  /// **'FTP操作を完了できませんでした。権限と接続状態を確認してください。'**
  String get ftpOperationFailed;

  /// No description provided for @ftpEmptyDirectory.
  ///
  /// In ja, this message translates to:
  /// **'このフォルダーは空です'**
  String get ftpEmptyDirectory;

  /// No description provided for @ftpRefresh.
  ///
  /// In ja, this message translates to:
  /// **'再読み込み'**
  String get ftpRefresh;

  /// No description provided for @ftpNewFolder.
  ///
  /// In ja, this message translates to:
  /// **'新しいフォルダー'**
  String get ftpNewFolder;

  /// No description provided for @ftpNewFolderTitle.
  ///
  /// In ja, this message translates to:
  /// **'フォルダーを作成'**
  String get ftpNewFolderTitle;

  /// No description provided for @ftpFolderName.
  ///
  /// In ja, this message translates to:
  /// **'フォルダー名'**
  String get ftpFolderName;

  /// No description provided for @ftpRename.
  ///
  /// In ja, this message translates to:
  /// **'名前を変更'**
  String get ftpRename;

  /// No description provided for @ftpRenameTitle.
  ///
  /// In ja, this message translates to:
  /// **'名前を変更'**
  String get ftpRenameTitle;

  /// No description provided for @ftpNewName.
  ///
  /// In ja, this message translates to:
  /// **'新しい名前'**
  String get ftpNewName;

  /// No description provided for @ftpDeleteTitle.
  ///
  /// In ja, this message translates to:
  /// **'削除しますか'**
  String get ftpDeleteTitle;

  /// No description provided for @ftpDeleteMessage.
  ///
  /// In ja, this message translates to:
  /// **'{name}をFTPサーバーから削除します。この操作は取り消せません。'**
  String ftpDeleteMessage(String name);

  /// No description provided for @ftpCloseTab.
  ///
  /// In ja, this message translates to:
  /// **'タブを閉じる'**
  String get ftpCloseTab;

  /// No description provided for @ftpCloseTabTitle.
  ///
  /// In ja, this message translates to:
  /// **'FTPタブを閉じますか'**
  String get ftpCloseTabTitle;

  /// No description provided for @ftpCloseTabMessage.
  ///
  /// In ja, this message translates to:
  /// **'FTP接続を切断してタブを閉じます。'**
  String get ftpCloseTabMessage;

  /// No description provided for @ftpRoot.
  ///
  /// In ja, this message translates to:
  /// **'ルート'**
  String get ftpRoot;

  /// No description provided for @ftpDirectory.
  ///
  /// In ja, this message translates to:
  /// **'フォルダー'**
  String get ftpDirectory;

  /// No description provided for @ftpFile.
  ///
  /// In ja, this message translates to:
  /// **'ファイル'**
  String get ftpFile;

  /// No description provided for @ftpUnknownSize.
  ///
  /// In ja, this message translates to:
  /// **'サイズ不明'**
  String get ftpUnknownSize;

  /// No description provided for @settingsTitle.
  ///
  /// In ja, this message translates to:
  /// **'設定'**
  String get settingsTitle;

  /// No description provided for @settingsTerminalSection.
  ///
  /// In ja, this message translates to:
  /// **'ターミナル'**
  String get settingsTerminalSection;

  /// No description provided for @settingsTerminalFont.
  ///
  /// In ja, this message translates to:
  /// **'ターミナルフォント'**
  String get settingsTerminalFont;

  /// No description provided for @settingsTerminalFontValue.
  ///
  /// In ja, this message translates to:
  /// **'ターミナルの英数字・記号・罫線に使用します。日本語は画面フォントで補います。'**
  String get settingsTerminalFontValue;

  /// No description provided for @settingsSelectTerminalFont.
  ///
  /// In ja, this message translates to:
  /// **'ターミナルフォントを選択'**
  String get settingsSelectTerminalFont;

  /// No description provided for @terminalFontCascadiaMono.
  ///
  /// In ja, this message translates to:
  /// **'Cascadia Mono'**
  String get terminalFontCascadiaMono;

  /// No description provided for @terminalFontJetBrainsMono.
  ///
  /// In ja, this message translates to:
  /// **'JetBrains Mono'**
  String get terminalFontJetBrainsMono;

  /// No description provided for @settingsTerminalRenderer.
  ///
  /// In ja, this message translates to:
  /// **'ターミナルエミュレータ'**
  String get settingsTerminalRenderer;

  /// No description provided for @settingsSelectTerminalRenderer.
  ///
  /// In ja, this message translates to:
  /// **'ターミナルエミュレータを選択'**
  String get settingsSelectTerminalRenderer;

  /// No description provided for @terminalRendererWebgl.
  ///
  /// In ja, this message translates to:
  /// **'xterm.js WebGL'**
  String get terminalRendererWebgl;

  /// No description provided for @terminalRendererWebglDescription.
  ///
  /// In ja, this message translates to:
  /// **'複雑なTUIと高速更新を優先します。WebViewを使うためメモリ使用量は増えます。WebGLを使えない場合はDOM描画へ切り替わります。'**
  String get terminalRendererWebglDescription;

  /// No description provided for @terminalRendererAlacritty.
  ///
  /// In ja, this message translates to:
  /// **'Flutter Alacritty'**
  String get terminalRendererAlacritty;

  /// No description provided for @terminalRendererAlacrittyDescription.
  ///
  /// In ja, this message translates to:
  /// **'AlacrittyベースのRust VTエンジンとGPUグリフ描画を使用します。Android対応は実験段階のため、問題が起きた場合はxterm.js WebGLへ切り替わります。'**
  String get terminalRendererAlacrittyDescription;

  /// No description provided for @terminalRendererConnectBot.
  ///
  /// In ja, this message translates to:
  /// **'termlib'**
  String get terminalRendererConnectBot;

  /// No description provided for @terminalRendererConnectBotDescription.
  ///
  /// In ja, this message translates to:
  /// **'termlibとlibvtermの標準描画を使用します。IME、文字選択、スクロール、マウス入力をAndroid上で処理し、WebViewを使用しません。'**
  String get terminalRendererConnectBotDescription;

  /// No description provided for @terminalRendererTermux.
  ///
  /// In ja, this message translates to:
  /// **'Termux'**
  String get terminalRendererTermux;

  /// No description provided for @terminalRendererTermuxDescription.
  ///
  /// In ja, this message translates to:
  /// **'Termuxのterminal-emulatorでANSI・UTF-8・IME互換性を優先します。Android Canvas描画のため、WebGLよりメモリを抑えられます。履歴は最大50,000行です。'**
  String get terminalRendererTermuxDescription;

  /// No description provided for @settingsJapaneseFont.
  ///
  /// In ja, this message translates to:
  /// **'画面フォント'**
  String get settingsJapaneseFont;

  /// No description provided for @settingsJapaneseFontMessage.
  ///
  /// In ja, this message translates to:
  /// **'Termethisの画面とターミナルの日本語表示で優先します。字形がない場合は端末のフォールバックフォントで補います。'**
  String get settingsJapaneseFontMessage;

  /// No description provided for @settingsSelectFont.
  ///
  /// In ja, this message translates to:
  /// **'画面フォントを選択'**
  String get settingsSelectFont;

  /// No description provided for @settingsRefreshRate.
  ///
  /// In ja, this message translates to:
  /// **'画面の滑らかさ'**
  String get settingsRefreshRate;

  /// No description provided for @settingsSelectRefreshRate.
  ///
  /// In ja, this message translates to:
  /// **'リフレッシュレート制御を選択'**
  String get settingsSelectRefreshRate;

  /// No description provided for @refreshRateAdaptive.
  ///
  /// In ja, this message translates to:
  /// **'適応'**
  String get refreshRateAdaptive;

  /// No description provided for @refreshRateAdaptiveDescription.
  ///
  /// In ja, this message translates to:
  /// **'OSに評価を任せ、操作と端末出力中だけ高いフレームレートを要求します。'**
  String get refreshRateAdaptiveDescription;

  /// No description provided for @refreshRateBalanced.
  ///
  /// In ja, this message translates to:
  /// **'バランス'**
  String get refreshRateBalanced;

  /// No description provided for @refreshRateBalancedDescription.
  ///
  /// In ja, this message translates to:
  /// **'通常は約60Hzで動作し、操作と大量出力中だけ高いフレームレートを要求します。'**
  String get refreshRateBalancedDescription;

  /// No description provided for @refreshRateMaximum.
  ///
  /// In ja, this message translates to:
  /// **'最大'**
  String get refreshRateMaximum;

  /// No description provided for @refreshRateMaximumDescription.
  ///
  /// In ja, this message translates to:
  /// **'対応する最高リフレッシュレートを継続して要求します。消費電力が増える場合があります。'**
  String get refreshRateMaximumDescription;

  /// No description provided for @settingsScrollbackLines.
  ///
  /// In ja, this message translates to:
  /// **'スクロールバック行数'**
  String get settingsScrollbackLines;

  /// No description provided for @settingsScrollbackLinesValue.
  ///
  /// In ja, this message translates to:
  /// **'新しく開くSSHセッションで{lines}行を保持します。25,000行以上はWebGL描画を推奨し、行数に応じてメモリ使用量も増えます。'**
  String settingsScrollbackLinesValue(int lines);

  /// No description provided for @settingsBackgroundSession.
  ///
  /// In ja, this message translates to:
  /// **'バックグラウンド接続モード'**
  String get settingsBackgroundSession;

  /// No description provided for @settingsBackgroundSessionDescription.
  ///
  /// In ja, this message translates to:
  /// **'接続中はTermethisの常駐通知を表示し、画面消灯中もSSH接続の維持を試みます。OSの省電力制御によって切断される場合があります。'**
  String get settingsBackgroundSessionDescription;

  /// No description provided for @settingsKeyManagementSection.
  ///
  /// In ja, this message translates to:
  /// **'キー管理'**
  String get settingsKeyManagementSection;

  /// No description provided for @settingsKeyManagement.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵と信頼済みホスト鍵'**
  String get settingsKeyManagement;

  /// No description provided for @settingsKeyManagementDescription.
  ///
  /// In ja, this message translates to:
  /// **'接続先で使用する秘密鍵と、SSH接続時に登録したホスト鍵を確認します。'**
  String get settingsKeyManagementDescription;

  /// No description provided for @settingsCredentialProtection.
  ///
  /// In ja, this message translates to:
  /// **'認証情報の保護'**
  String get settingsCredentialProtection;

  /// No description provided for @settingsCredentialProtectionDescription.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵と保存したパスフレーズは端末内で暗号化します。SSHパスワードは保存しません。'**
  String get settingsCredentialProtectionDescription;

  /// No description provided for @keyManagementTitle.
  ///
  /// In ja, this message translates to:
  /// **'キー管理'**
  String get keyManagementTitle;

  /// No description provided for @privateKeysTitle.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵'**
  String get privateKeysTitle;

  /// No description provided for @privateKeysEmpty.
  ///
  /// In ja, this message translates to:
  /// **'秘密鍵を使用する接続先はありません。接続先の編集画面から登録できます。'**
  String get privateKeysEmpty;

  /// No description provided for @knownHostsTitle.
  ///
  /// In ja, this message translates to:
  /// **'信頼済みホスト鍵'**
  String get knownHostsTitle;

  /// No description provided for @knownHostsEmpty.
  ///
  /// In ja, this message translates to:
  /// **'登録済みのホスト鍵はありません。初回SSH接続時に確認して登録します。'**
  String get knownHostsEmpty;

  /// No description provided for @removeKnownHostTitle.
  ///
  /// In ja, this message translates to:
  /// **'ホスト鍵を削除しますか'**
  String get removeKnownHostTitle;

  /// No description provided for @removeKnownHostMessage.
  ///
  /// In ja, this message translates to:
  /// **'次回接続時に、この接続先のホスト鍵をもう一度確認します。'**
  String get removeKnownHostMessage;

  /// No description provided for @fontNotoSansJp.
  ///
  /// In ja, this message translates to:
  /// **'Noto Sans JP'**
  String get fontNotoSansJp;

  /// No description provided for @fontKoruri.
  ///
  /// In ja, this message translates to:
  /// **'Koruri'**
  String get fontKoruri;

  /// No description provided for @fontMejiro.
  ///
  /// In ja, this message translates to:
  /// **'Mejiro'**
  String get fontMejiro;

  /// No description provided for @fontRoboto.
  ///
  /// In ja, this message translates to:
  /// **'Roboto'**
  String get fontRoboto;

  /// No description provided for @fontMoralerspace.
  ///
  /// In ja, this message translates to:
  /// **'Moralerspace'**
  String get fontMoralerspace;

  /// No description provided for @fontSourceCodePro.
  ///
  /// In ja, this message translates to:
  /// **'Source Code Pro'**
  String get fontSourceCodePro;

  /// No description provided for @fontJetBrainsMono.
  ///
  /// In ja, this message translates to:
  /// **'JetBrains Mono'**
  String get fontJetBrainsMono;

  /// No description provided for @fontPreview.
  ///
  /// In ja, this message translates to:
  /// **'日本語 ABC 123 の表示見本'**
  String get fontPreview;

  /// No description provided for @settingsFtpSection.
  ///
  /// In ja, this message translates to:
  /// **'FTP'**
  String get settingsFtpSection;

  /// No description provided for @settingsFtpSecurity.
  ///
  /// In ja, this message translates to:
  /// **'安全な接続を推奨'**
  String get settingsFtpSecurity;

  /// No description provided for @settingsFtpSecurityMessage.
  ///
  /// In ja, this message translates to:
  /// **'平文FTPは認証情報も暗号化されません。利用できる場合はSFTP、FTPES、FTPSを選んでください。'**
  String get settingsFtpSecurityMessage;

  /// No description provided for @settingsAboutSection.
  ///
  /// In ja, this message translates to:
  /// **'Termethisについて'**
  String get settingsAboutSection;

  /// No description provided for @settingsVersion.
  ///
  /// In ja, this message translates to:
  /// **'バージョン'**
  String get settingsVersion;

  /// No description provided for @settingsVersionValue.
  ///
  /// In ja, this message translates to:
  /// **'0.8.0-alpha4'**
  String get settingsVersionValue;

  /// No description provided for @settingsLicenses.
  ///
  /// In ja, this message translates to:
  /// **'オープンソースライセンス'**
  String get settingsLicenses;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
