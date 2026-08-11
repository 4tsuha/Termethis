# Local dartssh2 patches

This directory vendors `dartssh2` 2.22.5 so connection-path fixes remain
reproducible.

## PTY and shell request pipelining

`SSHClient.shell()` has an opt-in `pipelinePtyAndShellRequests` parameter.
When enabled without X11, the PTY and shell channel requests are sent in order
without waiting for the PTY reply before sending the shell request. Both
ordered replies are still checked before returning the session.

RFC 4254 section 5.4 permits sending another channel request before the prior
reply and requires replies for the same channel to remain in request order.

The app enables this option only for its interactive terminal connection.

## Receive window adjustment batching

Channel receive windows are replenished after half of the advertised window
has been consumed instead of sending `SSH_MSG_CHANNEL_WINDOW_ADJUST` for every
incoming data packet. This preserves SSH flow control while avoiding an
encrypted response packet for each terminal output packet.

## Native AES-CTR and ETM receive path

ETM verification reads the packet length, ciphertext, and MAC as receive-buffer
views rather than copying and joining the encrypted packet first.
AES-CTR and HMAC-SHA2 ETM use `webcrypto`'s in-process BoringSSL implementation
when available, with the Pointy Castle path retained for other algorithms.
