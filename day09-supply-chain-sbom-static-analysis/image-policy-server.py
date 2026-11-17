#!/usr/bin/env python3
"""Minimal ImagePolicyWebhook backend for the Day 9 lab.

Denies images without a tag or tagged :latest (digests are allowed).
Usage: image-policy-server.py <cert> <key> [port]
"""
import json
import ssl
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


def denied_reason(image):
    if "@sha256:" in image:
        return None
    name = image.rsplit("/", 1)[-1]
    if ":" not in name:
        return f"image {image} has no tag"
    if name.endswith(":latest"):
        return f"image {image} uses the latest tag"
    return None


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        review = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        images = [c["image"] for c in review.get("spec", {}).get("containers", [])]
        reasons = [r for r in map(denied_reason, images) if r]
        review["status"] = {"allowed": not reasons}
        if reasons:
            review["status"]["reason"] = "; ".join(reasons)
        body = json.dumps(review).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write("image-policy: " + fmt % args + "\n")


def main():
    cert, key = sys.argv[1], sys.argv[2]
    port = int(sys.argv[3]) if len(sys.argv) > 3 else 8443
    server = HTTPServer(("127.0.0.1", port), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(cert, key)
    server.socket = ctx.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
