import json, os, select, subprocess, sys, time

# Single-request driver for the moon-lsp stdio surface.
# Sends initialize, waits for its response, then sends the request from the
# JSON file and waits `timeout` seconds for a response with the same id.
req = json.load(open(sys.argv[1]))
timeout = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0
lsp = os.environ.get("MOON_LSP", os.path.expanduser("~/.moon/bin/moon-lsp"))
p = subprocess.Popen([lsp, "--stdio"], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

def send(m):
    b = json.dumps(m).encode()
    p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b)
    p.stdin.flush()

def recv(want, seconds):
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([p.stdout], [], [], 0.2)
        if not r:
            continue
        line = p.stdout.readline()
        if not line:
            return "DEAD"
        if line.startswith(b"Content-Length"):
            n = int(line.split(b":")[1])
            while p.stdout.readline().strip():
                pass
            m = json.loads(p.stdout.read(n))
            if m.get("id") == want:
                return m
    return None

def ticks():
    try:
        st = open("/proc/%d/stat" % p.pid).read().split()
        return int(st[13]) + int(st[14])
    except Exception:
        return None

send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
      "params": {"processId": None, "rootUri": None, "capabilities": {}}})
init = recv(1, 5)
if init is None or init == "DEAD":
    print("initialize failed:", init)
    p.kill()
    p.wait()
    sys.exit(2)

send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
c0, t0 = ticks(), time.time()
send(req)
r = recv(req["id"], timeout)
elapsed = time.time() - t0
c1 = ticks()
cpu = None
if c0 is not None and c1 is not None and elapsed > 0:
    cpu = round((c1 - c0) / 100.0 / elapsed * 100.0, 1)
if r is None:
    print("HUNG (no response in %.1fs), elapsed %.2fs, server cpu %s%%, alive=%s"
          % (timeout, elapsed, cpu, p.poll() is None))
elif r == "DEAD":
    print("CRASH (server exited), elapsed %.2fs" % elapsed)
else:
    print("OK: " + json.dumps(r.get("result", r.get("error")))[:300])
if p.poll() is None:
    p.kill()
p.wait()
