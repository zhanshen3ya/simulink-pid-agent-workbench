import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import TCPServer


class LocalHTTPServer(ThreadingHTTPServer):
    def server_bind(self):
        TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = str(host)
        self.server_port = int(port)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8"))
        request = json.loads(payload["messages"][-1]["content"])
        blocks = request["pidBlocks"]
        if isinstance(blocks, dict):
            blocks = [blocks]
        center = request["searchCenter"]["pids"]
        if isinstance(center, dict):
            center = [center]

        pids = []
        for index, block in enumerate(blocks):
            source = center[index]
            pids.append({
                "name": block["name"],
                "Kp": source["Kp"],
                "Ki": source["Ki"],
                "Kd": source["Kd"],
                "N": source["N"],
            })
        content = json.dumps({"candidates": [{"pids": pids}]})
        response = {
            "id": "mock-pid-response",
            "choices": [{"message": {"role": "assistant", "content": content}}],
        }
        data = json.dumps(response).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    LocalHTTPServer(("127.0.0.1", 8790), Handler).serve_forever()
