#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyserial>=3.5"]
# ///
"""
Pull the T8L's TX-side config over USB-CDC and save:
  radios/t8l/tx-settings.bin  — raw response, byte-stable between runs
  radios/t8l/tx-settings.txt  — decoded, diff-friendly view

Run while the radio is in M+power management mode (hold M while pressing
power for 3s). Runtime mode doesn't expose USB at all.

Protocol (reverse-engineered from radiomaster-rc/RM-Web-Page Connection.html):

  Wire format, 420000 baud USB-CDC:
    Request:  A5 11 00 0D 0A      (TX settings refresh)
    Response: <noise> 56 <pkt> CRC_lo CRC_hi 0D 0A

  Noise to skip at the head of the buffer (other live packets multiplexed
  on the same wire):
    - `67 0C ...` (14B): link strength
    - `23 03 ...` ( 5B): progress bar update — emitted N times

  Real packet begins at 0x56 (sentinel byte, stripped by the JS configurator):
    56 <body…> CRC_lo CRC_hi 0D 0A

  Body is a sequence of chunks. Each chunk:
    [CRC8] EA <len> <marker> EA EE [payload of (len-3) bytes]

  Markers seen:
    29 EA EE — device info chunk: payload is "model\0module\0…\0<num_settings>"
    2B EA EE — parameter chunk (one setting; may span multiple chunks)

  Parameter payload (after concatenating chunks of the same id in seq desc → 0):
    parent:u8  dataType:u8  name\0  <type-specific fields…>

  dataType: low 7 bits = base type, high bit = hidden flag.
  Base types (per Connection.html parseParamData):
     0 UINT8 / 1 INT8     : value:u8 min:u8 max:u8 def:u8 unit\0
     2 UINT16 / 3 INT16   : same as above but u16 LE
     8 FLOAT              : value:i32 min:i32 max:i32 def:i32 dec:u8 step:i32 unit\0
     9 TEXT_SELECTION     : options\0 value:u8 min:u8 max:u8 def:u8 unit\0
    10 STRING             : maxLen:u8 value\0 def\0
    11 FOLDER             : (just the name — section header)
    12 INFO               : value\0 (display string, e.g. bind UID)
    13 COMMAND            : status:u8 timeout:u8 info\0
  hidden flag on INFO (0x8C) marks a live counter (e.g. Bad/Good).
"""
import argparse, pathlib, serial, sys, time

PORT_DEFAULT = "/dev/cu.usbmodemRADIOMASTER1"
BAUD = 420000
CMD_TX_REFRESH = bytes.fromhex("A5 11 00 0D 0A")

# Per-type base values (per parseParamData in radiomaster-rc/RM-Web-Page)
T_UINT8, T_INT8 = 0, 1
T_UINT16, T_INT16 = 2, 3
T_FLOAT = 8
T_SELECTION = 9
T_STRING = 10
T_FOLDER = 11
T_INFO = 12
T_COMMAND = 13

TYPE_NAMES = {
    T_UINT8: "uint8", T_INT8: "int8",
    T_UINT16: "uint16", T_INT16: "int16",
    T_FLOAT: "float",
    T_SELECTION: "selection", T_STRING: "string",
    T_FOLDER: "folder", T_INFO: "info", T_COMMAND: "command",
}

# Radiomaster's option strings embed `\xc0` for "below mid" (↓) and `\xc1` for
# "above mid" (↑) on switch-based options like Pitmode. Substitute so the
# diff is human-readable instead of full of U+FFFD replacement chars.
OPTION_BYTE_SUBS = {0xC0: "↓", 0xC1: "↑"}


def pull(port: str) -> bytes:
    s = serial.Serial(port, BAUD, timeout=0.1)
    s.dtr = True
    s.rts = True
    time.sleep(0.1)
    while s.in_waiting:
        s.read(s.in_waiting)
        time.sleep(0.02)

    s.write(CMD_TX_REFRESH)
    s.flush()

    out = bytearray()
    deadline = time.time() + 3.0
    last_data = time.time()
    while time.time() < deadline:
        chunk = s.read(4096)
        if chunk:
            out.extend(chunk)
            last_data = time.time()
        elif out and time.time() - last_data > 0.4:
            break
    s.close()
    return bytes(out)


def find_packet(raw: bytes) -> bytes:
    """Skip live-traffic noise until we find the 0x56 sentinel; return body
    between the sentinel and the trailing CRC+CRLF."""
    i = raw.find(b"\x56")
    if i < 0:
        raise ValueError("no 0x56 sentinel found in response")
    if not raw.endswith(b"\r\n"):
        raise ValueError(f"response missing CRLF terminator (tail: {raw[-6:].hex()})")
    # After 0x56: <body…> CRC_lo CRC_hi 0D 0A
    body = raw[i + 1 : -4]
    crc = raw[-4:-2]
    return body, crc


def walk_chunks(body: bytes):
    """Yield (marker_byte, payload_bytes, crc_byte) for each chunk in body.
    Chunk header = [CRC] EA LEN MARKER EA EE; payload follows with (LEN-3) bytes.
    Note: the packet body starts with a 1-byte prefix (packet type), so the
    first chunk begins at body[1]."""
    i = 1
    while i + 6 <= len(body):
        if body[i + 1] == 0xEA and body[i + 4] == 0xEA and body[i + 5] == 0xEE:
            crc = body[i]
            length = body[i + 2]
            marker = body[i + 3]
            payload_start = i + 6
            payload_end = payload_start + length - 4
            yield marker, body[payload_start:payload_end], crc
            i = payload_end
        else:
            i += 1


def parse_device_info(payload: bytes) -> dict:
    """29 EA EE chunk. Payload: model\0module\0...trailing-bytes\0<num_settings>?"""
    parts = payload.split(b"\x00")
    strings = [p.decode("utf-8", errors="replace") for p in parts if p]
    # Last bytes of payload often carry num_settings as the last non-zero byte.
    info = {"strings": strings, "raw_tail_hex": payload[-9:].hex()}
    # Heuristic: num_settings appears as a single byte preceded by zeros.
    nonzero_tail = [b for b in payload[-12:] if b != 0]
    if nonzero_tail:
        info["likely_num_settings"] = nonzero_tail[-1]
    return info


def merge_chunks_by_id(chunks: list) -> list:
    """Chunks for a single parameter share id and use decreasing seq → 0.
    Concatenate their payloads (after stripping id+seq from each)."""
    records: dict[int, dict] = {}
    order: list[int] = []
    for marker, payload, _crc in chunks:
        if marker != 0x2B or len(payload) < 2:
            continue
        pid, seq = payload[0], payload[1]
        rest = payload[2:]
        if pid not in records:
            records[pid] = {"seq_first": seq, "body": bytearray(rest)}
            order.append(pid)
        else:
            records[pid]["body"].extend(rest)
    return [(pid, records[pid]["seq_first"], bytes(records[pid]["body"])) for pid in order]


def decode_options(raw: bytes) -> list[str]:
    """Split a `;`-separated option list, substituting Radiomaster's
    ↓/↑ pitmode marker bytes (\xc0/\xc1) so the text is readable."""
    pieces = raw.split(b";")
    out = []
    for piece in pieces:
        s = ""
        for b in piece:
            s += OPTION_BYTE_SUBS.get(b, chr(b) if 32 <= b < 127 else f"\\x{b:02x}")
        out.append(s)
    return out


def _read_cstr(body: bytes, p: int) -> tuple[str, int]:
    end = body.find(b"\x00", p)
    if end < 0:
        return body[p:].decode("utf-8", errors="replace"), len(body)
    return body[p:end].decode("utf-8", errors="replace"), end + 1


def _read_u8(body: bytes, p: int) -> tuple[int, int]:
    return body[p], p + 1


def _read_u16le(body: bytes, p: int) -> tuple[int, int]:
    return body[p] | (body[p+1] << 8), p + 2


def parse_param(body: bytes) -> dict:
    if len(body) < 3:
        return {"error": f"short body ({len(body)}B): {body.hex()}"}

    parent = body[0]
    data_type = body[1]
    base_type = data_type & 0x7F
    hidden = bool(data_type & 0x80)

    name, p = _read_cstr(body, 2)
    rec = {"parent": parent, "type": base_type, "hidden": hidden, "name": name}

    if base_type in (T_UINT8, T_INT8):
        value, p = _read_u8(body, p)
        mn,    p = _read_u8(body, p)
        mx,    p = _read_u8(body, p)
        df,    p = _read_u8(body, p)
        unit,  p = _read_cstr(body, p)
        rec.update(value=value, min=mn, max=mx, default=df, unit=unit)

    elif base_type in (T_UINT16, T_INT16):
        value, p = _read_u16le(body, p)
        mn,    p = _read_u16le(body, p)
        mx,    p = _read_u16le(body, p)
        df,    p = _read_u16le(body, p)
        unit,  p = _read_cstr(body, p)
        rec.update(value=value, min=mn, max=mx, default=df, unit=unit)

    elif base_type == T_SELECTION:
        opts_end = body.find(b"\x00", p)
        if opts_end < 0:
            rec["error"] = "no options terminator"; return rec
        rec["options"] = decode_options(body[p:opts_end])
        p = opts_end + 1
        if p + 4 > len(body):
            rec["error"] = "truncated selection trailer"; return rec
        value, p = _read_u8(body, p)
        mn,    p = _read_u8(body, p)
        mx,    p = _read_u8(body, p)
        df,    p = _read_u8(body, p)
        unit,  p = _read_cstr(body, p)
        cur = rec["options"][value] if value < len(rec["options"]) else f"<idx {value}>"
        rec.update(value=value, min=mn, max=mx, default=df, unit=unit, current=cur)

    elif base_type == T_STRING:
        max_len, p = _read_u8(body, p)
        value,   p = _read_cstr(body, p)
        df,      p = _read_cstr(body, p)
        rec.update(max_len=max_len, value=value, default=df)

    elif base_type == T_FOLDER:
        # No further payload; the name IS the section heading.
        pass

    elif base_type == T_INFO:
        value, p = _read_cstr(body, p)
        rec["value"] = value
        if hidden:
            rec["live"] = True  # auto-updating counter, not a stored setting

    elif base_type == T_COMMAND:
        status, p = _read_u8(body, p)
        timeout, p = _read_u8(body, p)
        info, p = _read_cstr(body, p)
        rec.update(status=status, timeout=timeout, info=info)

    else:
        rec["error"] = f"unhandled type {base_type}"
        rec["raw_hex"] = body[p:].hex()

    return rec


def render(device_info: dict, params: list[dict]) -> str:
    out = []
    strings = device_info.get("strings", [])
    radio  = strings[0] if len(strings) > 0 else "?"
    module = strings[1] if len(strings) > 1 else "?"
    out.append(f"radio: {radio}")
    out.append(f"module: {module}")
    if "likely_num_settings" in device_info:
        out.append(f"settings_count: {device_info['likely_num_settings']}")
    out.append("")
    out.append("settings:")

    for pid, p in params:
        t = p.get("type")
        label = TYPE_NAMES.get(t, f"type={t}")
        flags = " (live)" if p.get("live") else (" (hidden)" if p.get("hidden") else "")
        out.append(f"  - id: {pid:02d}  parent: {p.get('parent', 0):02d}  type: {label}{flags}")
        out.append(f"    name: {p.get('name', '')}")

        if t in (T_UINT8, T_INT8, T_UINT16, T_INT16):
            out.append(f"    value:   {p.get('value', '?')}{(' ' + p['unit']) if p.get('unit') else ''}")
            out.append(f"    range:   {p.get('min', '?')}..{p.get('max', '?')}")
            out.append(f"    default: {p.get('default', '?')}")

        elif t == T_SELECTION:
            opts = p.get("options", [])
            sel = p.get("value", -1)
            out.append(f"    value:   [{sel}] {p.get('current', '?')}{(' ' + p['unit']) if p.get('unit') else ''}")
            out.append(f"    default: [{p.get('default', '?')}]")
            out.append(f"    options:")
            for i, opt in enumerate(opts):
                marker = "*" if i == sel else " "
                out.append(f"      {marker} [{i}] {opt}")

        elif t == T_STRING:
            out.append(f"    value:   {p.get('value', '')!r}")
            out.append(f"    default: {p.get('default', '')!r}")
            out.append(f"    max_len: {p.get('max_len', '?')}")

        elif t == T_FOLDER:
            pass  # name is the heading; nothing else to emit

        elif t == T_INFO:
            out.append(f"    value:   {p.get('value', '')}")

        elif t == T_COMMAND:
            out.append(f"    status:  {p.get('status', '?')}")
            out.append(f"    timeout: {p.get('timeout', '?')}")
            if p.get("info"):
                out.append(f"    info:    {p['info']}")

        if "error" in p:
            out.append(f"    error: {p['error']}")
            if "raw_hex" in p:
                out.append(f"    raw:   {p['raw_hex']}")
        out.append("")

    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default=PORT_DEFAULT)
    ap.add_argument("--out-dir", default="radios/t8l")
    ap.add_argument("--from-file", help="parse an existing dump instead of pulling fresh")
    args = ap.parse_args()

    if args.from_file:
        raw = pathlib.Path(args.from_file).read_bytes()
    else:
        raw = pull(args.port)
    if not raw:
        print("no response — is the radio in M+power management mode?", file=sys.stderr)
        sys.exit(1)

    body, crc = find_packet(raw)
    chunks = list(walk_chunks(body))
    device_chunks = [c for c in chunks if c[0] == 0x29]
    if not device_chunks:
        print("no device-info chunk (0x29) found", file=sys.stderr)
        sys.exit(1)
    device_info = parse_device_info(device_chunks[0][1])

    merged = merge_chunks_by_id(chunks)
    params = [(pid, parse_param(body)) for pid, _seq, body in merged]

    out_dir = pathlib.Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "tx-settings.bin").write_bytes(raw)
    (out_dir / "tx-settings.txt").write_text(render(device_info, params))
    print(f"wrote {out_dir/'tx-settings.bin'} ({len(raw)} bytes)")
    print(f"wrote {out_dir/'tx-settings.txt'} ({len(params)} parameters)")


if __name__ == "__main__":
    main()
