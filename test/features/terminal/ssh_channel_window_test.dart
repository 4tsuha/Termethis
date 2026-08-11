import 'dart:typed_data';

import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:dartssh2/src/ssh_channel.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SSH受信ウィンドウを半分消費するまで更新をまとめる', () async {
    const initialWindowSize = 1024;
    final sentMessages = <SSHMessage>[];
    final controller = SSHChannelController(
      localId: 1,
      localMaximumPacketSize: 256,
      localInitialWindowSize: initialWindowSize,
      remoteId: 2,
      remoteMaximumPacketSize: 256,
      remoteInitialWindowSize: initialWindowSize,
      sendMessage: sentMessages.add,
    );
    final subscription = controller.channel.stream.listen((_) {});

    for (var index = 0; index < 3; index++) {
      controller.handleMessage(
        SSH_Message_Channel_Data(recipientChannel: 1, data: Uint8List(128)),
      );
    }

    expect(
      sentMessages.whereType<SSH_Message_Channel_Window_Adjust>(),
      isEmpty,
    );

    controller.handleMessage(
      SSH_Message_Channel_Data(recipientChannel: 1, data: Uint8List(128)),
    );

    final adjustments = sentMessages
        .whereType<SSH_Message_Channel_Window_Adjust>()
        .toList();
    expect(adjustments, hasLength(1));
    expect(adjustments.single.bytesToAdd, initialWindowSize ~/ 2);
    expect(adjustments.single.recipientChannel, 2);

    await subscription.cancel();
  });
}
