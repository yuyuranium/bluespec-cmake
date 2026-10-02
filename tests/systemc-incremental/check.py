#!/usr/bin/env python3
"""Check that one incremental build recompiles users of regenerated headers."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--systemc-dir", type=Path, required=True)
args = parser.parse_args()
fixture = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="bsc-systemc-incremental-") as temporary:
    source = Path(temporary) / "source"
    build = Path(temporary) / "build"
    shutil.copytree(fixture, source)
    subprocess.run([
        "cmake", "-S", str(source), "-B", str(build), "-G", "Ninja",
        f"-DSystemCLanguage_DIR={args.systemc_dir.resolve()}",
        f"-DBLUESPEC_CMAKE_SOURCE_DIR={fixture.parent.parent}",
    ], check=True)
    command = ["cmake", "--build", str(build), "--target", "consumer"]
    subprocess.run(command, check=True)
    obj = build / "CMakeFiles/consumer.dir/consumer.cc.o"
    before = obj.read_bytes()
    bsv = source / "Incremental.bsv"
    bsv.write_text(bsv.read_text().replace("Bit#(8)", "Bit#(256)"))
    subprocess.run(command, check=True)
    assert obj.read_bytes() != before, (
        "One incremental build left the C++ consumer using the old model layout"
    )
    print("PASS: one incremental build refreshed the native model consumer")
