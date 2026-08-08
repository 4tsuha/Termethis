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
