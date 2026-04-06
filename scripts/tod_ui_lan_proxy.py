from __future__ import annotations

import argparse
import http.client
import http.server
import socketserver


class ThreadingProxyServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _forward(self) -> None:
        content_length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(content_length) if content_length > 0 else None
        original_host = self.headers.get("Host", "")

        upstream = http.client.HTTPConnection(self.server.target_host, self.server.target_port, timeout=30)
        try:
            headers = {key: value for key, value in self.headers.items() if key.lower() not in {"host", "connection", "proxy-connection"}}
            headers["Host"] = f"localhost:{self.server.target_port}"
            if original_host:
                headers["X-Forwarded-Host"] = original_host
            headers["X-Forwarded-Proto"] = "http"
            upstream.request(self.command, self.path, body=body, headers=headers)
            response = upstream.getresponse()
            payload = response.read()

            self.send_response(response.status, response.reason)
            for key, value in response.getheaders():
                if key.lower() in {"connection", "transfer-encoding", "content-length"}:
                    continue
                self.send_header(key, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if payload:
                self.wfile.write(payload)
        finally:
            upstream.close()

    def do_GET(self) -> None:
        self._forward()

    def do_POST(self) -> None:
        self._forward()

    def do_PUT(self) -> None:
        self._forward()

    def do_PATCH(self) -> None:
        self._forward()

    def do_DELETE(self) -> None:
        self._forward()

    def do_OPTIONS(self) -> None:
        self._forward()

    def log_message(self, format: str, *args: object) -> None:
        return


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish the TOD localhost UI on a LAN interface.")
    parser.add_argument("--listen-host", required=True)
    parser.add_argument("--listen-port", required=True, type=int)
    parser.add_argument("--target-host", required=True)
    parser.add_argument("--target-port", required=True, type=int)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    server = ThreadingProxyServer((args.listen_host, args.listen_port), ProxyHandler)
    server.target_host = args.target_host
    server.target_port = args.target_port
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
