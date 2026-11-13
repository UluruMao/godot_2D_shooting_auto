"""Fetch only the pinned Windows runtime from the official multi-platform ZIP."""

import argparse
import binascii
import hashlib
import json
import pathlib
import re
import struct
import urllib.request
import zlib

URL = "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--destination", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent.parent / ".godot/windows-templates")
OUT = parser.parse_args().destination
EXPECTED_SHA256 = "d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562"

def fetch(spec):
    request = urllib.request.Request(URL, headers={"Range": spec, "User-Agent": "portfolio-build", "Accept-Encoding": "identity"})
    with urllib.request.urlopen(request, timeout=120) as response:
        if response.status != 206:
            raise RuntimeError("Server did not honor the range; refusing the full multi-platform archive")
        match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", response.headers["Content-Range"])
        start, end, total = map(int, match.groups())
        data = response.read(end - start + 2)
        if len(data) != end - start + 1:
            raise RuntimeError("Truncated or oversized range")
        return data, start, total

ARCHIVE_SIZE = 1281349702
tail, tail_start, total = fetch(f"bytes={ARCHIVE_SIZE - 65557}-{ARCHIVE_SIZE - 1}")
eocd = tail.rfind(b"PK\x05\x06")
if eocd < 0:
    raise RuntimeError("ZIP end record missing")
cd_size, cd_start = struct.unpack_from("<II", tail, eocd + 12)
central = tail[cd_start - tail_start: cd_start - tail_start + cd_size] if cd_start >= tail_start else fetch(f"bytes={cd_start}-{cd_start + cd_size - 1}")[0]
entries = []
cursor = 0
while cursor < len(central):
    if central[cursor:cursor + 4] != b"PK\x01\x02":
        raise RuntimeError("Invalid ZIP central directory")
    method = struct.unpack_from("<H", central, cursor + 10)[0]
    crc, compressed, uncompressed = struct.unpack_from("<III", central, cursor + 16)
    name_len, extra_len, comment_len = struct.unpack_from("<HHH", central, cursor + 28)
    offset = struct.unpack_from("<I", central, cursor + 42)[0]
    name = central[cursor + 46:cursor + 46 + name_len].decode("utf-8")
    if name.endswith("/windows_release_x86_64.exe"):
        entries.append((name, method, crc, compressed, uncompressed, offset))
    cursor += 46 + name_len + extra_len + comment_len
if len(entries) != 1:
    raise RuntimeError("Expected one official Windows x64 release template")
OUT.mkdir(parents=True, exist_ok=True)
for name, method, crc, compressed, uncompressed, offset in entries:
    header = fetch(f"bytes={offset}-{offset + 29}")[0]
    if header[:4] != b"PK\x03\x04":
        raise RuntimeError("Invalid local ZIP header")
    names, extras = struct.unpack_from("<HH", header, 26)
    data_start = offset + 30 + names + extras
    compressed_data = fetch(f"bytes={data_start}-{data_start + compressed - 1}")[0]
    data = zlib.decompress(compressed_data, -15) if method == 8 else compressed_data
    if len(data) != uncompressed or binascii.crc32(data) & 0xffffffff != crc:
        raise RuntimeError("Template CRC/size validation failed")
    if hashlib.sha256(data).hexdigest() != EXPECTED_SHA256:
        raise RuntimeError("Windows runtime SHA-256 differs from the pinned template")
    target = OUT / "windows_release_x86_64.exe"
    target.write_bytes(data)
    report = {"source": URL, "archive_size": total, "entry": name,
              "downloaded_template_bytes": compressed, "size": len(data),
              "sha256": hashlib.sha256(data).hexdigest()}
    (OUT / "provenance.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report))
