from __future__ import annotations

import argparse
from pathlib import Path

from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer


def main() -> None:
    parser = argparse.ArgumentParser(description="Local FTP server for device tests")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--port", type=int, default=2121)
    args = parser.parse_args()

    authorizer = DummyAuthorizer()
    authorizer.add_user(
        "tester",
        "secret",
        str(args.root.resolve()),
        perm="elradfmwMT",
    )
    authorizer.add_user(
        "1234",
        "5678",
        str(args.root.resolve()),
        perm="elradfmwMT",
    )

    handler = FTPHandler
    handler.authorizer = authorizer
    handler.banner = "SSH Terminal JA FTP test server"
    handler.passive_ports = range(30000, 30010)

    server = FTPServer(("127.0.0.1", args.port), handler)
    server.serve_forever(timeout=0.5, blocking=True, handle_exit=True)


if __name__ == "__main__":
    main()
