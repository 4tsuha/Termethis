import 'dart:typed_data';

/// Hand-rolled protobuf encoding for mosh protocol schemas.
/// Field numbers match upstream mobile-shell/mosh exactly.

// Wire types.
const _wireVarint = 0;
const _wireBytes = 2;

// --- TransportInstruction ---
// field 1: protocol_version (uint32)
// field 2: old_num (uint64)
// field 3: new_num (uint64)
// field 4: ack_num (uint64)
// field 5: throwaway_num (uint64)
// field 6: diff (bytes)
// field 7: chaff (bytes)

class TransportInstruction {
  int protocolVersion;
  int oldNum;
  int newNum;
  int ackNum;
  int throwawayNum;
  Uint8List? diff;
  Uint8List? chaff;

  TransportInstruction({
    this.protocolVersion = 0,
    this.oldNum = 0,
    this.newNum = 0,
    this.ackNum = 0,
    this.throwawayNum = 0,
    this.diff,
    this.chaff,
  });

  Uint8List marshal() {
    final b = BytesBuilder();
    if (protocolVersion != 0) _appendTagVarint(b, 1, protocolVersion);
    _appendTagVarint(b, 2, oldNum);
    _appendTagVarint(b, 3, newNum);
    _appendTagVarint(b, 4, ackNum);
    _appendTagVarint(b, 5, throwawayNum);
    if (diff != null && diff!.isNotEmpty) _appendTagBytes(b, 6, diff!);
    if (chaff != null && chaff!.isNotEmpty) _appendTagBytes(b, 7, chaff!);
    return b.toBytes();
  }

  static TransportInstruction unmarshal(Uint8List data) {
    final ti = TransportInstruction();
    var offset = 0;
    while (offset < data.length) {
      final tag = _decodeTag(data, offset);
      if (tag == null) throw FormatException('truncated tag');
      offset += tag.size;

      switch (tag.field) {
        case 1:
          final v = _decodeVarint(data, offset);
          if (v == null) throw FormatException('truncated');
          ti.protocolVersion = v.value;
          offset += v.size;
        case 2:
          final v = _decodeVarint(data, offset);
          if (v == null) throw FormatException('truncated');
          ti.oldNum = v.value;
          offset += v.size;
        case 3:
          final v = _decodeVarint(data, offset);
          if (v == null) throw FormatException('truncated');
          ti.newNum = v.value;
          offset += v.size;
        case 4:
          final v = _decodeVarint(data, offset);
          if (v == null) throw FormatException('truncated');
          ti.ackNum = v.value;
          offset += v.size;
        case 5:
          final v = _decodeVarint(data, offset);
          if (v == null) throw FormatException('truncated');
          ti.throwawayNum = v.value;
          offset += v.size;
        case 6:
          final b = _decodeLengthDelimited(data, offset);
          if (b == null) throw FormatException('truncated');
          ti.diff = b.data;
          offset += b.size;
        case 7:
          final b = _decodeLengthDelimited(data, offset);
          if (b == null) throw FormatException('truncated');
          ti.chaff = b.data;
          offset += b.size;
        default:
          final skip = _skipField(data, offset, tag.wtype);
          if (skip == 0) throw FormatException('truncated');
          offset += skip;
      }
    }
    return ti;
  }
}

// --- HostInstruction ---
// field 2: HostBytes { field 4: hoststring }
// field 3: ResizeMessage { field 5: width, field 6: height }
// field 7: EchoAck { field 8: echo_ack_num }

class HostInstruction {
  Uint8List? hoststring;
  int width;
  int height;
  int echoAckNum; // -1 = not present

  HostInstruction({
    this.hoststring,
    this.width = 0,
    this.height = 0,
    this.echoAckNum = -1,
  });
}

Uint8List marshalHostMessage(List<HostInstruction> instrs) {
  final b = BytesBuilder();
  for (final hi in instrs) {
    final sub = _marshalHostInstruction(hi);
    _appendTagBytes(b, 1, sub);
  }
  return b.toBytes();
}

List<HostInstruction> unmarshalHostMessage(Uint8List data) {
  final instrs = <HostInstruction>[];
  var offset = 0;
  while (offset < data.length) {
    final tag = _decodeTag(data, offset);
    if (tag == null) throw FormatException('truncated');
    offset += tag.size;
    if (tag.field != 1) throw FormatException('unexpected field in HostMessage');
    final b = _decodeLengthDelimited(data, offset);
    if (b == null) throw FormatException('truncated');
    offset += b.size;
    final hi = HostInstruction(echoAckNum: -1);
    _unmarshalHostInstruction(hi, b.data);
    instrs.add(hi);
  }
  return instrs;
}

Uint8List _marshalHostInstruction(HostInstruction hi) {
  final b = BytesBuilder();
  if (hi.hoststring != null && hi.hoststring!.isNotEmpty) {
    final sub = BytesBuilder();
    _appendTagBytes(sub, 4, hi.hoststring!);
    _appendTagBytes(b, 2, sub.toBytes());
  }
  if (hi.width > 0 || hi.height > 0) {
    final sub = BytesBuilder();
    _appendTagVarint(sub, 5, hi.width);
    _appendTagVarint(sub, 6, hi.height);
    _appendTagBytes(b, 3, sub.toBytes());
  }
  if (hi.echoAckNum >= 0) {
    final sub = BytesBuilder();
    _appendTagVarint(sub, 8, hi.echoAckNum);
    _appendTagBytes(b, 7, sub.toBytes());
  }
  return b.toBytes();
}

void _unmarshalHostInstruction(HostInstruction hi, Uint8List data) {
  var offset = 0;
  while (offset < data.length) {
    final tag = _decodeTag(data, offset);
    if (tag == null) throw FormatException('truncated');
    offset += tag.size;

    switch (tag.field) {
      case 2: // HostBytes
        final b = _decodeLengthDelimited(data, offset);
        if (b == null) throw FormatException('truncated');
        offset += b.size;
        _unmarshalHostBytes(hi, b.data);
      case 3: // ResizeMessage
        final b = _decodeLengthDelimited(data, offset);
        if (b == null) throw FormatException('truncated');
        offset += b.size;
        _unmarshalResize(b.data, (w) => hi.width = w, (h) => hi.height = h);
      case 7: // EchoAck
        final b = _decodeLengthDelimited(data, offset);
        if (b == null) throw FormatException('truncated');
        offset += b.size;
        _unmarshalEchoAck(hi, b.data);
      default:
        final skip = _skipField(data, offset, tag.wtype);
        if (skip == 0) throw FormatException('truncated');
        offset += skip;
    }
  }
}

void _unmarshalHostBytes(HostInstruction hi, Uint8List data) {
  var offset = 0;
  while (offset < data.length) {
    final tag = _decodeTag(data, offset);
    if (tag == null) return;
    offset += tag.size;
    if (tag.field == 4) {
      final b = _decodeLengthDelimited(data, offset);
      if (b == null) return;
      hi.hoststring = b.data;
      offset += b.size;
    } else {
      final skip = _skipField(data, offset, tag.wtype);
      if (skip == 0) return;
      offset += skip;
    }
  }
}

void _unmarshalEchoAck(HostInstruction hi, Uint8List data) {
  var offset = 0;
  while (offset < data.length) {
    final tag = _decodeTag(data, offset);
    if (tag == null) return;
    offset += tag.size;
    if (tag.field == 8) {
      final v = _decodeVarint(data, offset);
      if (v == null) return;
      hi.echoAckNum = v.value;
      offset += v.size;
    } else {
      final skip = _skipField(data, offset, tag.wtype);
      if (skip == 0) return;
      offset += skip;
    }
  }
}

// --- UserInstruction ---
// field 2: Keystroke { field 4: keys }
// field 3: ResizeMessage { field 5: width, field 6: height }

class UserInstruction {
  Uint8List? keys;
  int width;
  int height;

  UserInstruction({this.keys, this.width = 0, this.height = 0});
}

Uint8List marshalUserMessage(List<UserInstruction> instrs) {
  final b = BytesBuilder();
  for (final ui in instrs) {
    final sub = _marshalUserInstruction(ui);
    _appendTagBytes(b, 1, sub);
  }
  return b.toBytes();
}

List<UserInstruction> unmarshalUserMessage(Uint8List data) {
  final instrs = <UserInstruction>[];
  var offset = 0;
  while (offset < data.length) {
    final tag = _decodeTag(data, offset);
    if (tag == null) throw FormatException('truncated');
    offset += tag.size;
    if (tag.field != 1) throw FormatException('unexpected field');
    final b = _decodeLengthDelimited(data, offset);
    if (b == null) throw FormatException('truncated');
    offset += b.size;
    final ui = UserInstruction();
    _unmarshalUserInstruction(ui, b.data);
    instrs.add(ui);
  }
  return instrs;
}

Uint8List _marshalUserInstruction(UserInstruction ui) {
  final b = BytesBuilder();
  if (ui.keys != null && ui.keys!.isNotEmpty) {
    final sub = BytesBuilder();
    _appendTagBytes(sub, 4, ui.keys!);
    _appendTagBytes(b, 2, sub.toBytes());
  }
  if (ui.width > 0 || ui.height > 0) {
    final sub = BytesBuilder();
    _appendTagVarint(sub, 5, ui.width);
    _appendTagVarint(sub, 6, ui.height);
    _appendTagBytes(b, 3, sub.toBytes());
  }
  return b.toBytes();
}

void _unmarshalUserInstruction(UserInstruction ui, Uint8List data) {
  var offset = 0;
  while (offset < data.length) {
    final tag = _decodeTag(data, offset);
    if (tag == null) return;
    offset += tag.size;

    switch (tag.field) {
      case 2: // Keystroke
        final b = _decodeLengthDelimited(data, offset);
        if (b == null) return;
        offset += b.size;
        _unmarshalKeystroke(ui, b.data);
      case 3: // ResizeMessage
        final b = _decodeLengthDelimited(data, offset);
        if (b == null) return;
        offset += b.size;
        _unmarshalResize(b.data, (w) => ui.width = w, (h) => ui.height = h);
      default:
        final skip = _skipField(data, offset, tag.wtype);
        if (skip == 0) return;
        offset += skip;
    }
  }
}

void _unmarshalKeystroke(UserInstruction ui, Uint8List data) {
  var offset = 0;
  while (offset < data.length) {
    final tag = _decodeTag(data, offset);
    if (tag == null) return;
    offset += tag.size;
    if (tag.field == 4) {
      final b = _decodeLengthDelimited(data, offset);
      if (b == null) return;
      ui.keys = (ui.keys == null)
          ? b.data
          : Uint8List.fromList([...ui.keys!, ...b.data]);
      offset += b.size;
    } else {
      final skip = _skipField(data, offset, tag.wtype);
      if (skip == 0) return;
      offset += skip;
    }
  }
}

// Shared resize decoder.
void _unmarshalResize(
  Uint8List data,
  void Function(int) setWidth,
  void Function(int) setHeight,
) {
  var offset = 0;
  while (offset < data.length) {
    final tag = _decodeTag(data, offset);
    if (tag == null) return;
    offset += tag.size;
    switch (tag.field) {
      case 5:
        final v = _decodeVarint(data, offset);
        if (v == null) return;
        setWidth(v.value);
        offset += v.size;
      case 6:
        final v = _decodeVarint(data, offset);
        if (v == null) return;
        setHeight(v.value);
        offset += v.size;
      default:
        final skip = _skipField(data, offset, tag.wtype);
        if (skip == 0) return;
        offset += skip;
    }
  }
}

// --- Encoding helpers ---

void _appendTag(BytesBuilder b, int field, int wtype) {
  _appendVarint(b, (field << 3) | wtype);
}

void _appendVarint(BytesBuilder b, int v) {
  // Dart ints are 64-bit. Treat as unsigned.
  var uv = v;
  while (uv >= 0x80) {
    b.addByte((uv & 0x7f) | 0x80);
    uv = (uv >> 7) & 0x1ffffffffffffff; // logical shift
  }
  b.addByte(uv & 0xff);
}

void _appendTagVarint(BytesBuilder b, int field, int v) {
  _appendTag(b, field, _wireVarint);
  _appendVarint(b, v);
}

void _appendTagBytes(BytesBuilder b, int field, Uint8List data) {
  _appendTag(b, field, _wireBytes);
  _appendVarint(b, data.length);
  b.add(data);
}

// --- Decoding helpers ---

class _Varint {
  final int value;
  final int size;
  _Varint(this.value, this.size);
}

class _Tag {
  final int field;
  final int wtype;
  final int size;
  _Tag(this.field, this.wtype, this.size);
}

class _Bytes {
  final Uint8List data;
  final int size; // total consumed bytes (length prefix + data)
  _Bytes(this.data, this.size);
}

_Varint? _decodeVarint(Uint8List data, int offset) {
  var v = 0;
  for (var i = 0; i < 10; i++) {
    if (offset + i >= data.length) return null;
    final c = data[offset + i];
    v |= (c & 0x7f) << (7 * i);
    if (c < 0x80) return _Varint(v, i + 1);
  }
  return null;
}

_Tag? _decodeTag(Uint8List data, int offset) {
  final v = _decodeVarint(data, offset);
  if (v == null) return null;
  return _Tag(v.value >> 3, v.value & 7, v.size);
}

_Bytes? _decodeLengthDelimited(Uint8List data, int offset) {
  final length = _decodeVarint(data, offset);
  if (length == null) return null;
  final start = offset + length.size;
  final end = start + length.value;
  if (end > data.length) return null;
  return _Bytes(
    Uint8List.sublistView(data, start, end),
    length.size + length.value,
  );
}

int _skipField(Uint8List data, int offset, int wtype) {
  switch (wtype) {
    case _wireVarint:
      final v = _decodeVarint(data, offset);
      return v?.size ?? 0;
    case _wireBytes:
      final b = _decodeLengthDelimited(data, offset);
      return b?.size ?? 0;
    case 5: // 32-bit
      return 4;
    case 1: // 64-bit
      return 8;
    default:
      return 0;
  }
}
