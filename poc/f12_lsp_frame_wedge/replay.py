#!/usr/bin/env python3
"""Replay moon-lsp stdio framing failures.

Modes:
  control   valid shutdown frame; both requests are answered
  bom       UTF-8 BOM before the first header
  array     Content-Length: 5 body "[1,2]" (valid JSON, not a JSON-RPC object)

Each mode starts a fresh moon-lsp, completes `initialize`, sends the trigger,
then sends a second, complete shutdown request (id 3).  A wedged server stays
alive, answers neither request, and logs an uncaught exception on stderr.

Exit status: 0 when the mode behaves as documented, 1 otherwise.
The server is always SIGKILLed and reaped.
"""
import json, os, select, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
LSP = os.environ.get("MOON_LSP", os.path.expanduser("~/.moon/bin/moon-lsp"))
TIMEOUT = float(os.environ.get("REPLAY_TIMEOUT", "2.0"))


def frame(obj):
    body = json.dumps(obj).encode()
    return b"Content-Length: %d\r\n\r\n" % len(body) + body


INIT = frame({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"processId": None, "rootUri": None, "capabilities": {}}})
SHUTDOWN2 = frame({"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": {}})
SHUTDOWN3 = frame({"jsonrpc": "2.0", "id": 3, "method": "shutdown", "params": {}})


def payload(mode):
    if mode == "control":
        return SHUTDOWN2
    if mode == "bom":
        return b"\xef\xbb\xbf" + SHUTDOWN2
    if mode == "array":
        return b"Content-Length: 5\r\n\r\n[1,2]"
    raise SystemExit("unknown mode: " + mode)


def read_all(p, seconds):
    """Read complete Content-Length frames from the raw pipe.

    Deliberately avoids buffered readline(): a buffered reader can hide a
    second response from select(2), which would fake a dropped message.
    """
    buf = b""
    msgs = []
    end = time.time() + seconds
    fd = p.stdout.fileno()
    while time.time() < end:
        r, _, _ = select.select([p.stdout], [], [], max(0.0, end - time.time()))
        if not r:
            break
        chunk = os.read(fd, 65536)
        if not chunk:
            break
        buf += chunk
        while True:
            i = buf.find(b"\r\n\r\n")
            if i < 0:
                break
            length = None
            for line in buf[:i].split(b"\r\n"):
                if line.lower().startswith(b"content-length:"):
                    length = int(line.split(b":", 1)[1])
            if length is None or length < 0:
                buf = buf[i + 4:]
                continue
            if len(buf) < i + 4 + length:
                break
            body = buf[i + 4:i + 4 + length]
            buf = buf[i + 4 + length:]
            try:
                msgs.append(json.loads(body))
            except Exception:
                msgs.append({"__unparsable__": body[:80].decode("utf-8", "replace")})
    return msgs


def ticks(pid):
    try:
        st = open("/proc/%d/stat" % pid).read().split()
        return int(st[13]) + int(st[14])
    except Exception:
        return None


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "bom"
    work = tempfile.mkdtemp(prefix="f12_lsp_")
    p = subprocess.Popen([LSP, "--stdio"], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=work)
    wedged = False
    try:
        p.stdin.write(INIT)
        p.stdin.flush()
        init = read_all(p, 3.0)
        init_ok = any(m.get("id") == 1 for m in init)

        t0 = time.time()
        c0 = ticks(p.pid)
        p.stdin.write(payload(mode))
        p.stdin.flush()
        time.sleep(0.05)
        p.stdin.write(SHUTDOWN3)
        p.stdin.flush()
        got = read_all(p, TIMEOUT)
        elapsed = time.time() - t0
        c1 = ticks(p.pid)
        cpu = None
        if c0 is not None and c1 is not None and elapsed > 0:
            cpu = round((c1 - c0) / 100.0 / elapsed * 100.0, 1)

        alive = p.poll() is None
        ids = [m.get("id") for m in got]
        id3 = any(m.get("id") == 3 for m in got)
        id2 = any(m.get("id") == 2 for m in got)

        err = b""
        if alive:
            import fcntl
            fd = p.stderr.fileno()
            flags = fcntl.fcntl(fd, fcntl.F_GETFL)
            fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
            try:
                err = os.read(fd, 8192)
            except Exception:
                err = b""
        err_line = ""
        for line in err.decode("utf-8", "replace").splitlines():
            if "Internal error" in line or "Json_error" in line or "conversion failed" in line:
                err_line = line.strip("| ")
                break

        wedged = alive and not id3
        crashed = not alive
        if mode == "control":
            expected = init_ok and id2 and id3 and not crashed
            verdict = "CONTROL_OK" if expected else "CONTROL_FAILED"
        else:
            expected = init_ok and wedged and not crashed and not id2
            verdict = "WEDGED" if expected else "NOT_WEDGED"

        print(json.dumps({
            "mode": mode,
            "verdict": verdict,
            "init_ok": init_ok,
            "alive": alive,
            "ids": ids,
            "id2_answered": id2,
            "id3_answered": id3,
            "elapsed_ms": round(elapsed * 1000),
            "server_cpu_pct": cpu,
            "stderr": err_line,
        }, sort_keys=True))
        return 0 if expected else 1
    finally:
        if p.poll() is None:
            p.kill()
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()


if __name__ == "__main__":
    sys.exit(main())
