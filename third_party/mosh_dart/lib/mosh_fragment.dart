import 'dart:typed_data';

/// Mosh fragment wire format:
///   [instruction_id : 8 bytes, big-endian]
///   [fragment_num(15 bits) | final_flag(1 bit) : 2 bytes, big-endian]
///   [payload : remaining bytes]

const fragmentHeaderSize = 10;
const maxFragmentPayload = 1300;

class Fragment {
  final int id;
  final int fragmentNum;
  final bool isFinal;
  final Uint8List payload;

  Fragment({
    required this.id,
    required this.fragmentNum,
    required this.isFinal,
    required this.payload,
  });

  Uint8List marshal() {
    final b = Uint8List(fragmentHeaderSize + payload.length);
    final view = ByteData.sublistView(b);
    view.setUint64(0, id);
    // Mosh layout: [final:1 bit][fragment_num:15 bits] (big-endian uint16).
    var numAndFinal = fragmentNum & 0x7fff;
    if (isFinal) numAndFinal |= 0x8000;
    view.setUint16(8, numAndFinal);
    b.setRange(fragmentHeaderSize, b.length, payload);
    return b;
  }

  static Fragment unmarshal(Uint8List data) {
    if (data.length < fragmentHeaderSize) {
      throw FormatException('fragment too short');
    }
    final view = ByteData.sublistView(data);
    final id = view.getUint64(0);
    final numAndFinal = view.getUint16(8);
    return Fragment(
      id: id,
      fragmentNum: numAndFinal & 0x7fff,
      isFinal: (numAndFinal & 0x8000) != 0,
      payload: Uint8List.sublistView(data, fragmentHeaderSize),
    );
  }
}

/// Split data into fragments.
List<Fragment> fragmentize(int id, Uint8List data) {
  if (data.isEmpty) {
    return [Fragment(id: id, fragmentNum: 0, isFinal: true, payload: Uint8List(0))];
  }

  final n = (data.length + maxFragmentPayload - 1) ~/ maxFragmentPayload;
  final frags = <Fragment>[];
  for (var i = 0; i < n; i++) {
    final start = i * maxFragmentPayload;
    var end = start + maxFragmentPayload;
    if (end > data.length) end = data.length;
    frags.add(Fragment(
      id: id,
      fragmentNum: i,
      isFinal: i == n - 1,
      payload: Uint8List.sublistView(data, start, end),
    ));
  }
  return frags;
}

/// Reassembles fragments into complete messages.
class FragmentAssembler {
  int _currentID = 0;
  List<Uint8List?> _fragments = [];
  int _totalNum = -1;

  /// Returns reassembled message when complete, or null.
  Uint8List? add(Fragment f) {
    if (f.id < _currentID) return null; // stale

    if (f.id != _currentID) {
      _currentID = f.id;
      _fragments = [];
      _totalNum = -1;
    }

    final idx = f.fragmentNum;
    while (_fragments.length <= idx) {
      _fragments.add(null);
    }
    _fragments[idx] = f.payload;

    if (f.isFinal) _totalNum = idx + 1;

    if (_totalNum < 0 || _fragments.length < _totalNum) return null;
    for (var i = 0; i < _totalNum; i++) {
      if (_fragments[i] == null) return null;
    }

    // Reassemble.
    final b = BytesBuilder();
    for (var i = 0; i < _totalNum; i++) {
      b.add(_fragments[i]!);
    }

    _fragments = [];
    _totalNum = -1;
    return b.toBytes();
  }
}
