"""Loopback-only deterministic text service; receives synthetic check text only."""
import http.server
import json
import sys
import time
from pathlib import Path


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if request['model'] == 'slow':
            time.sleep(10)
        if request['model'] == 'invalid':
            content = 'invalid JSON'
        else:
            content = json.dumps(dict(corrected='产品需求 PRD', edits=[dict(
                source='PLD', replacement='PRD', occurrence=0, basis='vocabulary', evidence='需求')],
                suggestions=[], output='产品需求 PRD'), ensure_ascii=False)
        body = json.dumps(dict(choices=[dict(finish_reason='stop', message=dict(role='assistant', content=content))])).encode()
        try:
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Path(sys.argv[1]).write_text(f'http://127.0.0.1:{server.server_port}/v1')
server.serve_forever()
