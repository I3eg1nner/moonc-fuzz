import json, os, select, subprocess, sys, time

req = json.load(open(sys.argv[1]))
p = subprocess.Popen([os.path.expanduser('~/.moon/bin/moon-lsp'), '--stdio'],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

def send(m):
    b = json.dumps(m).encode()
    p.stdin.write(b'Content-Length: %d\r\n\r\n' % len(b) + b)
    p.stdin.flush()

def recv(want, timeout):
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([p.stdout], [], [], 0.2)
        if not r:
            continue
        line = p.stdout.readline()
        if line.startswith(b'Content-Length'):
            n = int(line.split(b':')[1])
            while p.stdout.readline().strip():
                pass
            m = json.loads(p.stdout.read(n))
            if m.get('id') == want:
                return m
    return None

send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
      'params': {'processId': None, 'rootUri': None, 'capabilities': {}}})
init = recv(1, 10)
print('init:', 'ok' if init else 'TIMEOUT')
send({'jsonrpc': '2.0', 'method': 'initialized', 'params': {}})
send({'jsonrpc': '2.0', 'id': 2, 'method': 'moonbit-lsp/format-nth', 'params': req})
r = recv(2, 10)
print('HUNG (no response in 10s)' if r is None
      else 'OK: ' + json.dumps(r.get('result', r.get('error')))[:300])
p.kill()
