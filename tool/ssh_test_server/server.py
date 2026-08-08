"""Local-only SSH echo server used for Android terminal integration tests."""

from __future__ import annotations

import asyncio
import itertools
import json
import time

import asyncssh


HOST = "127.0.0.1"
PORT = 2222
USERNAME = "demo"
PASSWORD = "password"
_SERVER_STARTED_NS = time.perf_counter_ns()
_CONNECTION_IDS = itertools.count(1)


def log_event(name: str, connection_id: int) -> None:
    elapsed_ms = (time.perf_counter_ns() - _SERVER_STARTED_NS) / 1_000_000
    print(
        f"EVENT={name};CONNECTION={connection_id};MS={elapsed_ms:.3f}",
        flush=True,
    )


class TestSshServer(asyncssh.SSHServer):
    def __init__(self) -> None:
        self._connection_id = next(_CONNECTION_IDS)

    def connection_made(self, connection: asyncssh.SSHServerConnection) -> None:
        log_event("tcp_connected", self._connection_id)

    def begin_auth(self, username: str) -> bool:
        log_event("authentication_started", self._connection_id)
        print(f"BEGIN_AUTH={username}", flush=True)
        return True

    def password_auth_supported(self) -> bool:
        print("PASSWORD_AUTH_SUPPORTED", flush=True)
        return True

    def validate_password(self, username: str, password: str) -> bool:
        accepted = username == USERNAME and password == PASSWORD
        log_event("password_validated", self._connection_id)
        print(
            f"VALIDATE_PASSWORD_USER={username};LENGTH={len(password)};ACCEPTED={accepted}",
            flush=True,
        )
        return accepted

    def session_requested(self) -> EchoSession:
        log_event("session_requested", self._connection_id)
        print("SESSION_REQUESTED", flush=True)
        return EchoSession(self._connection_id)


class EchoSession(asyncssh.SSHServerSession):
    def __init__(self, connection_id: int) -> None:
        self._connection_id = connection_id
        self._channel: asyncssh.SSHServerChannel | None = None
        self._line = bytearray()

    def connection_made(self, channel: asyncssh.SSHServerChannel) -> None:
        self._channel = channel
        print("SESSION_CONNECTION_MADE", flush=True)

    def pty_requested(
        self,
        term_type: str,
        term_size: tuple[int, int, int, int],
        term_modes: dict[int, int],
    ) -> bool:
        log_event("pty_requested", self._connection_id)
        print(f"PTY_REQUESTED={term_type};SIZE={term_size}", flush=True)
        return True

    def shell_requested(self) -> bool:
        assert self._channel is not None
        log_event("shell_requested", self._connection_id)
        print("SHELL_REQUESTED", flush=True)
        self._channel.write(
            (
                "Windows Terminal font preview\r\n"
                "0O 1Il | [] {} () => !=\r\n"
                "┌─┬─┐  │ 日本語 │  └─┴─┘\r\n"
                "$ "
            ).encode()
        )
        return True

    def data_received(self, data: bytes, datatype: int | None) -> None:
        assert self._channel is not None
        for byte in data:
            if byte in {0x0D, 0x0A}:
                if self._line:
                    received = bytes(self._line)
                    print("RECEIVED_HEX=" + received.hex(), flush=True)
                    try:
                        decoded = received.decode("utf-8")
                        utf8_valid = True
                    except UnicodeDecodeError:
                        decoded = received.decode("utf-8", errors="replace")
                        utf8_valid = False
                    print(f"RECEIVED_UTF8_VALID={utf8_valid}", flush=True)
                    print(
                        "RECEIVED_JSON="
                        + json.dumps(decoded, ensure_ascii=True),
                        flush=True,
                    )
                    self._channel.write(
                        b"\r\n" + "受信: ".encode() + received + b"\r\n$ "
                    )
                    self._line.clear()
                else:
                    self._channel.write(b"\r\n$ ")
                continue
            if byte == 0x7F:
                if self._line:
                    self._line.pop()
                    self._channel.write(b"\b \b")
                continue
            self._line.append(byte)
            self._channel.write(bytes([byte]))


async def main() -> None:
    host_key = asyncssh.generate_private_key("ssh-ed25519")
    await asyncssh.create_server(
        TestSshServer,
        HOST,
        PORT,
        server_host_keys=[host_key],
        encoding=None,
    )
    print(f"READY={HOST}:{PORT}", flush=True)
    await asyncio.Future()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (OSError, asyncssh.Error) as error:
        raise SystemExit(f"SSH test server failed: {error}") from error
