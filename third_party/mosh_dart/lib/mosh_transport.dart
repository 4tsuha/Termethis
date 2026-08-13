import 'dart:io';
import 'dart:typed_data';

import 'mosh_fragment.dart';
import 'mosh_pb.dart';
import 'ocb.dart';

/// Direction bits in the 8-byte nonce header.
const _dirToServer = 0; // bit 63 = 0
const _dirToClient = 1 << 63; // bit 63 = 1
const _seqMask = (1 << 63) - 1;

/// Minimum wire datagram: 8 (nonce) + 16 (tag) = 24.
const minDatagram = 24;

/// MoshTransport implements the mosh SSP state machine.
///
/// Simple design matching the real mosh client behavior:
/// - At most one unacked diff in flight at a time
/// - The caller provides the diff via setPending()
/// - tick() sends if there's new data, an ack is needed, or RTO expired
/// - The diff is cleared after the server acks our latest state
class MoshTransport {
  final AesOcb _ocb;
  final int _toRemote;
  final int _toLocal;

  // Outgoing.
  int _sentNum = 0;
  int _ackedNum = 0; // highest state the server has acked
  Uint8List? _pendingDiff;
  int _pendingOldNum = 0; // oldNum for the pending diff
  bool _hasPending = false; // true = we have an unacked state in flight
  bool _pendingNeedsSend = false;

  // Incoming.
  int _recvNum = 0;
  int _sentAckNum = 0;
  bool _pendingDataAck = false;

  int _lastRecvOldNum = 0;
  int _lastRecvNewNum = 0;
  int _throwawayNum = 0;
  int _receivedPackets = 0;

  /// The oldNum from the most recently received diff.
  int get lastRecvOldNum => _lastRecvOldNum;

  /// The newNum from the most recently received diff.
  int get lastRecvNewNum => _lastRecvNewNum;

  /// States below this number are no longer referenced by the server.
  int get throwawayNum => _throwawayNum;

  /// Number of authenticated datagrams accepted from the remote endpoint.
  ///
  /// A valid acknowledgement may not contain a state diff, so callers cannot
  /// use [recv]'s return value alone to determine whether the handshake is
  /// alive.
  int get receivedPackets => _receivedPackets;

  // Crypto.
  int _seqOut = 0;
  int _seqInMax = 0;
  bool _seqInMaxSet = false;

  // Timestamps.
  DateTime _lastSend = DateTime.now();
  DateTime _lastRecv = DateTime.now();
  int _lastTS = 0;

  // RTT.
  Duration _srtt = Duration.zero;
  Duration _rttvar = Duration.zero;
  Duration _rto = const Duration(milliseconds: 1000);
  bool _rttInit = false;

  final _assembler = FragmentAssembler();
  static const _minRTO = Duration(milliseconds: 250);
  static const _maxRTO = Duration(seconds: 10);

  MoshTransport._({
    required AesOcb ocb,
    required int toRemote,
    required int toLocal,
  })  : _ocb = ocb,
        _toRemote = toRemote,
        _toLocal = toLocal;

  factory MoshTransport.client(AesOcb ocb) => MoshTransport._(
        ocb: ocb,
        toRemote: _dirToServer,
        toLocal: _dirToClient,
      );

  /// Server-side transport used by protocol tests and embedded peers.
  factory MoshTransport.server(AesOcb ocb) => MoshTransport._(
        ocb: ocb,
        toRemote: _dirToClient,
        toLocal: _dirToServer,
      );

  /// Highest state the server has acked.
  int get ackedByRemote => _ackedNum;

  /// Current sent state number.
  int get sentNum => _sentNum;

  /// True if we have an unacked state in flight.
  bool get hasPendingState => _hasPending;

  Duration get idleTime => DateTime.now().difference(_lastRecv);

  /// Time until [tick] can produce the next datagram.
  ///
  /// Callers can use a one-shot timer instead of polling the transport at a
  /// fixed frame rate. Incoming data and new user input should still call
  /// [tick] immediately.
  Duration get nextTickDelay {
    if (_pendingNeedsSend || _pendingDataAck || _recvNum > _sentAckNum) {
      return Duration.zero;
    }
    final remaining = _rto - DateTime.now().difference(_lastSend);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void forceNextSend() {
    _lastSend = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Set a new diff to send. Only call this when the server has acked
  /// the previous state (hasPendingState == false) or to update
  /// the diff for the current in-flight state.
  void setPending(Uint8List? diff) {
    _pendingDiff = diff;
    _pendingNeedsSend = _hasPending && diff != null;
  }

  /// Send a new state with the given diff. Increments sentNum.
  /// Only call when there's no unacked state in flight.
  void sendNew(Uint8List diff) {
    _sentNum++;
    _pendingDiff = diff;
    _pendingOldNum = _ackedNum;
    _hasPending = true;
    _pendingNeedsSend = true;
  }

  List<Uint8List> tick() {
    final now = DateTime.now();

    final haveDiff = _hasPending && _pendingDiff != null;
    final haveNewDiff = haveDiff && _pendingNeedsSend;
    final needAck = _recvNum > _sentAckNum;
    final sinceLastSend = now.difference(_lastSend);
    final expired = sinceLastSend >= _rto;
    final urgentAck = _pendingDataAck;

    if (!haveNewDiff && !needAck && !expired && !urgentAck) return [];

    _pendingDataAck = false;
    _pendingNeedsSend = false;

    final ti = TransportInstruction(
      protocolVersion: 2,
      oldNum: haveDiff ? _pendingOldNum : _ackedNum,
      newNum: _sentNum,
      ackNum: _recvNum,
      throwawayNum: 0,
      diff: haveDiff ? _pendingDiff : null,
    );
    _sentAckNum = _recvNum;

    final pbData = ti.marshal();
    final compressed = Uint8List.fromList(zlib.encode(pbData));
    final frags = fragmentize(_sentNum, compressed);

    final datagrams = <Uint8List>[];
    for (final f in frags) {
      datagrams.add(_encryptFragment(f, now));
    }

    _lastSend = now;
    return datagrams;
  }

  Uint8List? recv(Uint8List wire) {
    if (wire.length < minDatagram) return null;

    final dirSeq = ByteData.sublistView(wire).getUint64(0);
    if ((dirSeq & _dirToClient) != (_toLocal & _dirToClient)) return null;

    final seq = dirSeq & _seqMask;
    if (_seqInMaxSet && seq <= _seqInMax) return null;

    final nonce = Uint8List(12);
    nonce.setRange(4, 12, Uint8List.sublistView(wire, 0, 8));
    final plaintext = _ocb.decrypt(nonce, Uint8List.sublistView(wire, 8));
    if (plaintext == null) return null;

    if (plaintext.length < 4) return null;
    final ptView = ByteData.sublistView(plaintext);
    final remoteTS = ptView.getUint16(0);
    final tsReply = ptView.getUint16(2);
    final payload = Uint8List.sublistView(plaintext, 4);

    _seqInMax = seq;
    _seqInMaxSet = true;
    _receivedPackets++;
    _lastRecv = DateTime.now();
    _lastTS = remoteTS;

    if (tsReply != 0) _updateRTT(tsReply);

    if (payload.length < fragmentHeaderSize) return null;
    final frag = Fragment.unmarshal(payload);
    final msg = _assembler.add(frag);
    if (msg == null) return null;

    final decompressed = Uint8List.fromList(zlib.decode(msg));
    final ti = TransportInstruction.unmarshal(decompressed);

    if (ti.ackNum > _ackedNum) {
      _ackedNum = ti.ackNum;
      // Server caught up — clear pending state.
      if (_ackedNum >= _sentNum) {
        _hasPending = false;
        _pendingDiff = null;
        _pendingNeedsSend = false;
      }
    }
    if (ti.newNum > _recvNum) _recvNum = ti.newNum;

    if (ti.diff != null && ti.diff!.isNotEmpty) {
      _pendingDataAck = true;
    }

    _lastRecvOldNum = ti.oldNum;
    _lastRecvNewNum = ti.newNum;
    if (ti.throwawayNum > _throwawayNum) {
      _throwawayNum = ti.throwawayNum;
    }
    return ti.diff;
  }

  Uint8List _encryptFragment(Fragment f, DateTime now) {
    _seqOut++;
    final dirSeq = _toRemote | (_seqOut & _seqMask);
    final dirSeqBytes = Uint8List(8);
    ByteData.sublistView(dirSeqBytes).setUint64(0, dirSeq);

    final nonce = Uint8List(12);
    nonce.setRange(4, 12, dirSeqBytes);

    final fragWire = f.marshal();
    final ts = now.millisecondsSinceEpoch & 0xffff;
    final plaintext = Uint8List(4 + fragWire.length);
    final ptView = ByteData.sublistView(plaintext);
    ptView.setUint16(0, ts);
    ptView.setUint16(2, _lastTS);
    plaintext.setRange(4, plaintext.length, fragWire);

    final tagAndCT = _ocb.encrypt(nonce, plaintext);
    final wire = Uint8List(8 + tagAndCT.length);
    wire.setRange(0, 8, dirSeqBytes);
    wire.setRange(8, wire.length, tagAndCT);
    return wire;
  }

  void _updateRTT(int tsReply) {
    final now16 = DateTime.now().millisecondsSinceEpoch & 0xffff;
    var rttMS = now16 - tsReply;
    if (rttMS < 0) rttMS += 65536;
    if (rttMS > 30000) return;
    final rtt = Duration(milliseconds: rttMS);
    if (!_rttInit) {
      _srtt = rtt;
      _rttvar = Duration(microseconds: rtt.inMicroseconds ~/ 2);
      _rttInit = true;
    } else {
      var delta = _srtt - rtt;
      if (delta.isNegative) delta = -delta;
      _rttvar = Duration(
          microseconds:
              (3 * _rttvar.inMicroseconds + delta.inMicroseconds) ~/ 4);
      _srtt = Duration(
          microseconds: (7 * _srtt.inMicroseconds + rtt.inMicroseconds) ~/ 8);
    }
    _rto = _srtt + _rttvar * 4;
    if (_rto < _minRTO) _rto = _minRTO;
    if (_rto > _maxRTO) _rto = _maxRTO;
  }
}
