import 'dart:typed_data';

import 'package:pointycastle/pointycastle.dart';

/// AES-128-OCB3 authenticated encryption (RFC 7253).
///
/// Used by the mosh protocol for datagram encryption.
class AesOcb {
  static const blockSize = 16;
  static const tagSize = 16;

  final Uint8List _key;
  late final BlockCipher _cipher;
  late final Uint8List _lStar;
  late final Uint8List _lDollar;
  late final List<Uint8List> _l;

  AesOcb(this._key) {
    _cipher = BlockCipher('AES')
      ..init(true, KeyParameter(_key));

    // L_* = ENCIPHER(K, zeros)
    _lStar = Uint8List(blockSize);
    _cipher.processBlock(_lStar, 0, _lStar, 0);

    // L_$ = double(L_*)
    _lDollar = _double(_lStar);

    // Precompute L_0 .. L_31
    _l = List.generate(32, (_) => Uint8List(blockSize));
    _l[0] = _double(_lDollar);
    for (var i = 1; i < 32; i++) {
      _l[i] = _double(_l[i - 1]);
    }
  }

  /// Encrypt plaintext with the given nonce. Returns tag + ciphertext.
  Uint8List encrypt(Uint8List nonce, Uint8List plaintext) {
    final offset = _initOffset(nonce);
    final checksum = Uint8List(blockSize);

    final fullBlocks = plaintext.length ~/ blockSize;
    final remaining = plaintext.length % blockSize;
    final ciphertext = Uint8List(plaintext.length);

    // Process full blocks.
    for (var i = 0; i < fullBlocks; i++) {
      final ntz = _ntz(i + 1);
      _xorInto(offset, _l[ntz]);

      // Plaintext block.
      final pBlock = Uint8List.sublistView(plaintext, i * blockSize, (i + 1) * blockSize);
      _xorInto(checksum, pBlock);

      // C_i = Offset xor ENCIPHER(K, Offset xor P_i)
      final tmp = _xor(offset, pBlock);
      final enc = Uint8List(blockSize);
      _cipher.processBlock(tmp, 0, enc, 0);
      _xorInto(enc, offset);
      ciphertext.setRange(i * blockSize, (i + 1) * blockSize, enc);
    }

    // Process final partial block (if any).
    if (remaining > 0) {
      _xorInto(offset, _lStar);

      final pad = Uint8List(blockSize);
      _cipher.processBlock(offset, 0, pad, 0);

      final pStar = Uint8List.sublistView(plaintext, fullBlocks * blockSize);
      for (var i = 0; i < remaining; i++) {
        ciphertext[fullBlocks * blockSize + i] = pStar[i] ^ pad[i];
      }

      // Checksum_* = Checksum_m xor (P_* || 1 || zeros)
      final padded = Uint8List(blockSize);
      padded.setRange(0, remaining, pStar);
      padded[remaining] = 0x80;
      _xorInto(checksum, padded);
    }

    // Tag = ENCIPHER(K, Checksum xor Offset xor L_$)
    _xorInto(checksum, offset);
    _xorInto(checksum, _lDollar);
    final tag = Uint8List(blockSize);
    _cipher.processBlock(checksum, 0, tag, 0);

    // Return ciphertext || tag (mosh wire order).
    final result = Uint8List(ciphertext.length + tagSize);
    result.setRange(0, ciphertext.length, ciphertext);
    result.setRange(ciphertext.length, result.length, tag);
    return result;
  }

  /// Decrypt ciphertext + tag with the given nonce. Returns plaintext or null
  /// if authentication fails.
  Uint8List? decrypt(Uint8List nonce, Uint8List ciphertextAndTag) {
    if (ciphertextAndTag.length < tagSize) return null;

    final ciphertext = Uint8List.sublistView(ciphertextAndTag, 0, ciphertextAndTag.length - tagSize);
    final tag = Uint8List.sublistView(ciphertextAndTag, ciphertextAndTag.length - tagSize);

    // Need decrypt direction cipher.
    final decCipher = BlockCipher('AES')
      ..init(false, KeyParameter(_key));

    final offset = _initOffset(nonce);
    final checksum = Uint8List(blockSize);

    final fullBlocks = ciphertext.length ~/ blockSize;
    final remaining = ciphertext.length % blockSize;
    final plaintext = Uint8List(ciphertext.length);

    // Process full blocks.
    for (var i = 0; i < fullBlocks; i++) {
      final ntz = _ntz(i + 1);
      _xorInto(offset, _l[ntz]);

      final cBlock = Uint8List.sublistView(ciphertext, i * blockSize, (i + 1) * blockSize);
      final tmp = _xor(offset, cBlock);
      final dec = Uint8List(blockSize);
      decCipher.processBlock(tmp, 0, dec, 0);
      _xorInto(dec, offset);
      plaintext.setRange(i * blockSize, (i + 1) * blockSize, dec);
      _xorInto(checksum, dec);
    }

    // Process final partial block.
    if (remaining > 0) {
      _xorInto(offset, _lStar);

      final pad = Uint8List(blockSize);
      _cipher.processBlock(offset, 0, pad, 0);

      final cStar = Uint8List.sublistView(ciphertext, fullBlocks * blockSize);
      for (var i = 0; i < remaining; i++) {
        plaintext[fullBlocks * blockSize + i] = cStar[i] ^ pad[i];
      }

      final pStar = Uint8List.sublistView(plaintext, fullBlocks * blockSize);
      final padded = Uint8List(blockSize);
      padded.setRange(0, remaining, pStar);
      padded[remaining] = 0x80;
      _xorInto(checksum, padded);
    }

    // Compute expected tag.
    _xorInto(checksum, offset);
    _xorInto(checksum, _lDollar);
    final expectedTag = Uint8List(blockSize);
    _cipher.processBlock(checksum, 0, expectedTag, 0);

    // Constant-time tag comparison.
    var diff = 0;
    for (var i = 0; i < tagSize; i++) {
      diff |= tag[i] ^ expectedTag[i];
    }
    if (diff != 0) return null;

    return plaintext;
  }

  /// Compute the initial offset from a nonce (up to 15 bytes for OCB3-128).
  Uint8List _initOffset(Uint8List nonce) {
    // RFC 7253 Section 4.2 — nonce-dependent offset.
    // For taglen=128 and nonce <= 120 bits (15 bytes):
    //
    // Nonce = num2str(taglen mod 128, 7) || zeros(120-bitlen(N)) || 1 || N
    // bottom = str2num(Nonce[123..128])
    // Ktop = ENCIPHER(K, Nonce[1..122] || zeros(6))
    // Stretch = Ktop || (Ktop[1..64] xor Ktop[9..72])
    // Offset_0 = Stretch[1+bottom..128+bottom]

    final nonceLen = nonce.length;
    if (nonceLen > 15) {
      throw ArgumentError('OCB nonce must be <= 15 bytes, got $nonceLen');
    }

    // Build the full 16-byte nonce block.
    final nn = Uint8List(blockSize);
    nn[0] = ((tagSize * 8) % 128) & 0x7f; // taglen mod 128 in top 7 bits
    nn[blockSize - 1 - nonceLen] |= 0x01;
    for (var i = 0; i < nonceLen; i++) {
      nn[blockSize - nonceLen + i] |= nonce[i];
    }

    final bottom = nn[15] & 0x3f;
    nn[15] &= 0xc0;

    // Ktop = ENCIPHER(K, nn)
    final ktop = Uint8List(blockSize);
    _cipher.processBlock(nn, 0, ktop, 0);

    // Stretch = Ktop || (Ktop[0..7] xor Ktop[1..8])
    final stretch = Uint8List(24);
    stretch.setRange(0, 16, ktop);
    for (var i = 0; i < 8; i++) {
      stretch[16 + i] = ktop[i] ^ ktop[i + 1];
    }

    // Extract 128 bits starting at bit position `bottom`.
    final offset = Uint8List(blockSize);
    final byteShift = bottom >> 3;
    final bitShift = bottom & 7;

    for (var i = 0; i < blockSize; i++) {
      final idx = byteShift + i;
      if (idx < 24) {
        offset[i] = (stretch[idx] << bitShift) & 0xff;
        if (idx + 1 < 24) {
          offset[i] |= (stretch[idx + 1] >> (8 - bitShift)) & 0xff;
        }
      }
    }

    return offset;
  }

  /// Number of trailing zeros in a positive integer.
  static int _ntz(int n) {
    if (n == 0) return 32;
    var count = 0;
    while ((n & 1) == 0) {
      count++;
      n >>= 1;
    }
    return count;
  }

  /// Double a block in GF(2^128) with the polynomial x^128 + x^7 + x^2 + x + 1.
  static Uint8List _double(Uint8List block) {
    final result = Uint8List(blockSize);
    var carry = 0;
    for (var i = blockSize - 1; i >= 0; i--) {
      final tmp = (block[i] << 1) | carry;
      result[i] = tmp & 0xff;
      carry = (block[i] >> 7) & 1;
    }
    // If carry, XOR with 0x87 at the last byte.
    if (carry != 0) {
      result[blockSize - 1] ^= 0x87;
    }
    return result;
  }

  /// XOR two blocks, returning a new block.
  static Uint8List _xor(Uint8List a, Uint8List b) {
    final result = Uint8List(blockSize);
    for (var i = 0; i < blockSize; i++) {
      result[i] = a[i] ^ b[i];
    }
    return result;
  }

  /// XOR b into a in-place.
  static void _xorInto(Uint8List a, Uint8List b) {
    for (var i = 0; i < blockSize; i++) {
      a[i] ^= b[i];
    }
  }
}
