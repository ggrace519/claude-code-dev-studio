# Defensive native-host skeleton (stdio framing + handshake)

Python-flavored; the pattern (bounded length read → full drain → schema check →
allowlisted dispatch → length-prefixed reply) is identical in Go, Rust, or Node.
stdout is the transport — every log line goes to stderr.

```python
import sys, json, struct

MAX_INBOUND = 1024 * 1024          # defensive cap; reject before allocating
MAX_OUTBOUND = 1024 * 1024         # Chromium drops host->extension messages > 1 MB
PROTOCOL_VERSION = 2
COMMANDS = {"ping", "get_status", "open_file"}   # explicit allowlist

def read_message():
    raw_len = sys.stdin.buffer.read(4)
    if len(raw_len) < 4:
        sys.exit(0)                # EOF: browser closed the port — exit cleanly
    (length,) = struct.unpack("=I", raw_len)     # native byte order, like Chromium
    if length == 0 or length > MAX_INBOUND:
        sys.exit(1)                # framing is broken; resync is impossible
    payload = sys.stdin.buffer.read(length)
    if len(payload) < length:
        sys.exit(1)                # truncated read — do not parse a partial body
    return json.loads(payload)

def write_message(obj):
    body = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    if len(body) > MAX_OUTBOUND:
        body = json.dumps({"error": "response_too_large"}).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("=I", len(body)))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()      # unflushed replies look like a hung host

def main():
    # 1. Version handshake before any work. Older host than the extension
    #    expects -> structured upgrade_required, never a crash.
    hello = read_message()
    if hello.get("type") != "hello":
        write_message({"error": "expected_hello"}); sys.exit(1)
    write_message({"type": "hello", "version": PROTOCOL_VERSION})

    while True:
        msg = read_message()
        cmd = msg.get("command")
        # 2. Allowlist dispatch — no getattr/dict-of-everything off user input.
        if cmd not in COMMANDS:
            write_message({"id": msg.get("id"), "error": "unknown_command"})
            continue
        # 3. Per-command authorization: validate argument schema, canonicalize
        #    any paths (resolve + prefix-check against the sandbox root), and
        #    require native-side user confirmation for high-privilege actions.
        try:
            write_message({"id": msg.get("id"), "result": dispatch(cmd, msg)})
        except Exception as e:
            print(f"dispatch error: {e}", file=sys.stderr)
            write_message({"id": msg.get("id"), "error": "internal"})

if __name__ == "__main__":
    main()
```

## Test matrix

- [ ] Length prefix claims 2 GB → host exits/rejects without allocating
- [ ] Truncated payload (length says 100, body has 60) → no partial-JSON parse
- [ ] Unknown command → structured error reply, host stays alive
- [ ] Handshake with older host version → `upgrade_required` path in the extension
- [ ] Browser closes the port mid-session (stdin EOF) → host exits, no orphan
- [ ] Payload-supplied path `../../etc/passwd` → rejected by canonicalization check
- [ ] Reply just over 1 MB → replaced with structured error, not silently dropped by Chromium
- [ ] Dev-build extension ID against the production manifest → connection refused
