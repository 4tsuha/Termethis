import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mosh_dart/mosh_pb.dart';
import 'package:mosh_dart/mosh_transport.dart';
import 'package:mosh_dart/ocb.dart';

import '../domain/ssh_gateway.dart';

class MoshBootstrap {
  const MoshBootstrap({
    required this.host,
    required this.port,
    required this.key,
  });

  final String host;
  final int port;
  final String key;

  static MoshBootstrap parse(String output, {required String fallbackHost}) {
    final match = RegExp(
      r'MOSH CONNECT (\d+) ([A-Za-z0-9+/]+={0,2})',
    ).firstMatch(output);
    if (match == null) {
      throw const FormatException('mosh-server did not return MOSH CONNECT');
    }
    final port = int.parse(match.group(1)!);
    if (port <= 0 || port > 65535) {
      throw const FormatException('Mosh UDP port is outside the valid range');
    }
    final key = _decodeKey(match.group(2)!);
    return MoshBootstrap(
      host: fallbackHost,
      port: port,
      key: base64Encode(key),
    );
  }

  static Uint8List _decodeKey(String encoded) {
    var normalized = encoded;
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    final decoded = base64Decode(normalized);
    if (decoded.length != 16) {
      throw const FormatException('Mosh connection key must be 128 bits');
    }
    return decoded;
  }
}

class MoshConnection implements SshConnection {
  MoshConnection._(this._bootstrap, this._socket, this._transport) {
    _subscription = _socket.listen(
      _onSocketEvent,
      onError: _fail,
      onDone: () => unawaited(_shutdown()),
    );
    _transport.forceNextSend();
    _flush();
  }

  final MoshBootstrap _bootstrap;
  final RawDatagramSocket _socket;
  final MoshTransport _transport;
  final StreamController<Uint8List> _stdout = StreamController();
  final StreamController<Uint8List> _stderr = StreamController();
  final Completer<void> _done = Completer<void>();
  final Completer<void> _ready = Completer<void>();
  BytesBuilder _pendingKeys = BytesBuilder(copy: false);
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _pumpTimer;
  Timer? _handshakeTimer;
  DateTime? _pumpDeadline;
  InternetAddress? _address;
  int _pendingWidth = 0;
  int _pendingHeight = 0;
  int _lastWidth = 0;
  int _lastHeight = 0;
  bool _closed = false;
  bool _receivedPacket = false;
  Future<void>? _shutdownFuture;

  static const _maximumPendingInputBytes = 1024 * 1024;

  static Future<MoshConnection> connect(
    MoshBootstrap bootstrap, {
    Duration handshakeTimeout = const Duration(seconds: 10),
  }) async {
    if (bootstrap.port <= 0 || bootstrap.port > 65535) {
      throw const FormatException('Mosh UDP port is outside the valid range');
    }
    final key = MoshBootstrap._decodeKey(bootstrap.key);
    final address = (await InternetAddress.lookup(bootstrap.host)).first;
    final socket = await RawDatagramSocket.bind(
      address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    final connection = MoshConnection._(
      bootstrap,
      socket,
      MoshTransport.client(AesOcb(key)),
    );
    connection._address = address;
    connection._handshakeTimer = Timer(handshakeTimeout, () {
      if (!connection._receivedPacket && !connection._closed) {
        connection._fail(
          const SocketException('MoshのUDP応答を受信できません。UDPポートとファイアウォールを確認してください。'),
        );
      }
    });
    connection._flush();
    try {
      await connection._ready.future;
    } catch (_) {
      await connection._shutdown();
      rethrow;
    }
    return connection;
  }

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Future<void> get done => _done.future;

  @override
  void write(Uint8List data) {
    if (_closed || data.isEmpty) return;
    if (_pendingKeys.length + data.length > _maximumPendingInputBytes) {
      _fail(const SocketException('Moshの未送信入力が上限を超えました。接続状態を確認して再接続してください。'));
      return;
    }
    _pendingKeys.add(data);
    _flush();
  }

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {
    if (_closed || width <= 0 || height <= 0) return;
    if (width == _lastWidth && height == _lastHeight) return;
    _pendingWidth = width;
    _pendingHeight = height;
    _flush();
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _closed) return;
    Datagram? datagram;
    while ((datagram = _socket.receive()) != null) {
      try {
        final receivedBefore = _transport.receivedPackets;
        final diff = _transport.recv(datagram!.data);
        if (_transport.receivedPackets > receivedBefore) {
          _receivedPacket = true;
          _handshakeTimer?.cancel();
          _handshakeTimer = null;
          if (!_ready.isCompleted) _ready.complete();
        }
        if (diff == null || diff.isEmpty) continue;
        final output = BytesBuilder(copy: false);
        for (final instruction in unmarshalHostMessage(diff)) {
          final bytes = instruction.hoststring;
          if (bytes != null && bytes.isNotEmpty) output.add(bytes);
        }
        final data = output.takeBytes();
        if (data.isNotEmpty) _stdout.add(data);
      } catch (error, stackTrace) {
        _fail(error, stackTrace);
        break;
      }
    }
    _flush();
  }

  void _flush() {
    if (_closed || _address == null) return;
    if (!_transport.hasPendingState &&
        (_pendingKeys.length > 0 || _pendingWidth > 0)) {
      final instructions = <UserInstruction>[];
      if (_pendingWidth > 0) {
        instructions.add(
          UserInstruction(width: _pendingWidth, height: _pendingHeight),
        );
        _lastWidth = _pendingWidth;
        _lastHeight = _pendingHeight;
        _pendingWidth = 0;
        _pendingHeight = 0;
      }
      if (_pendingKeys.length > 0) {
        instructions.add(UserInstruction(keys: _pendingKeys.takeBytes()));
        _pendingKeys = BytesBuilder(copy: false);
      }
      _transport.sendNew(marshalUserMessage(instructions));
    }
    for (final datagram in _transport.tick()) {
      _socket.send(datagram, _address!, _bootstrap.port);
    }
    _schedulePump(_transport.nextTickDelay);
  }

  void _schedulePump(Duration delay) {
    if (_closed) return;
    final now = DateTime.now();
    final deadline = now.add(delay);
    if (_pumpTimer?.isActive == true &&
        _pumpDeadline != null &&
        !_pumpDeadline!.isAfter(deadline)) {
      return;
    }
    _pumpTimer?.cancel();
    _pumpDeadline = deadline;
    _pumpTimer = Timer(delay, () {
      _pumpTimer = null;
      _pumpDeadline = null;
      _flush();
    });
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    if (_closed) return;
    if (!_ready.isCompleted) {
      _ready.completeError(error, stackTrace);
    } else {
      _stderr.addError(error, stackTrace);
    }
    unawaited(_shutdown());
  }

  void _complete() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> close() async {
    await _shutdown();
  }

  Future<void> _shutdown() => _shutdownFuture ??= _performShutdown();

  Future<void> _performShutdown() async {
    _closed = true;
    if (!_ready.isCompleted) {
      _ready.completeError(const SocketException('MoshのUDPソケットが接続前に終了しました。'));
    }
    _pumpTimer?.cancel();
    _handshakeTimer?.cancel();
    _pumpTimer = null;
    _handshakeTimer = null;
    final subscription = _subscription;
    _subscription = null;
    _socket.close();
    await subscription?.cancel();
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    _complete();
  }
}
