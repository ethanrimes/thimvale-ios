#!/usr/bin/env python3
"""Check ELF load segments in every packaged 64-bit native library."""
import struct
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as apk:
    libraries = [name for name in apk.namelist() if name.startswith(("lib/arm64-v8a/", "lib/x86_64/")) and name.endswith(".so")]
    assert libraries, "No 64-bit native libraries found"
    for name in libraries:
        data = apk.read(name)
        assert data[:6] == b"\x7fELF\x02\x01", f"Expected little-endian ELF64: {name}"
        table = struct.unpack_from("<Q", data, 32)[0]
        stride, count = struct.unpack_from("<HH", data, 54)
        loads = []
        for index in range(count):
            entry = table + index * stride
            if struct.unpack_from("<I", data, entry)[0] == 1:
                loads.append(struct.unpack_from("<Q", data, entry + 48)[0])
        assert loads and all(value >= 16384 for value in loads), f"Not 16 KB aligned: {name}: {loads}"
        print(f"16 KB aligned: {name}")
