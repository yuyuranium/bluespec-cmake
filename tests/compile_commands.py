"""Integration check: run with python3 tests/compile_commands.py."""
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run(args, check=True)


with tempfile.TemporaryDirectory(prefix="bsc-database-") as temporary:
    source = Path(temporary) / "source"
    build = Path(temporary) / "build"
    (source / "lib").mkdir(parents=True)
    (source / "lib/Base.bsv").write_text("package Base; endpackage\n")
    (source / "Top.bsv").write_text("package Top; import Base::*; endpackage\n")
    (source / "lib/CMakeLists.txt").write_text('''
bsc_add_library(base SOURCES Base.bsv)
bsc_target_compile_definitions(base PUBLIC WIDTH=8 PRIVATE BASE_ONLY)
bsc_target_compile_options(base PRIVATE -suppress-warnings S0001 -suppress-warnings S0080)
''')
    cmake = f'''cmake_minimum_required(VERSION 3.30)
project(DatabaseTest LANGUAGES NONE)
include("{ROOT}/BluespecCMake.cmake")
add_subdirectory(lib)
bsc_add_bluesim_executable(sim TOP mkTop SOURCE Top.bsv)
bsc_target_link_libraries(sim PRIVATE base)
bsc_target_compile_definitions(sim PRIVATE "$<$<CONFIG:Debug>:SIMULATION>")
'''
    (source / "CMakeLists.txt").write_text(cmake)
    run("cmake", "-S", str(source), "-B", str(build), "-G", "Ninja")
    # The script is usable before Ninja scans or builds anything.
    run("cmake", "-P", str(build / "bsc_compile_commands.cmake"))
    assert not list(build.rglob("component.request"))
    run("cmake", "--build", str(build), "--target", "bsc_compile_commands")
    database = build / "bsc_compile_commands.json"
    entries = {Path(entry["file"]).name: entry for entry in json.loads(database.read_text())}
    assert set(entries) == {"Base.bsv", "Top.bsv"}
    base, top = entries["Base.bsv"], entries["Top.bsv"]
    assert base["directory"] == str(build / "lib")
    assert top["directory"] == str(build)
    assert "WIDTH=8" in base["arguments"] and "WIDTH=8" in top["arguments"]
    assert "BASE_ONLY" in base["arguments"] and "BASE_ONLY" not in top["arguments"]
    assert "SIMULATION" in top["arguments"] and "SIMULATION" not in base["arguments"]
    assert base["arguments"].count("-suppress-warnings") == 2
    assert str(source / "lib") in top["arguments"][top["arguments"].index("-p") + 1].split(":")
    assert not list(build.rglob("*.bo"))
    assert not (source / "bsc_compile_commands.json").exists()
    timestamp = database.stat().st_mtime_ns
    run("cmake", "--build", str(build), "--target", "bsc_compile_commands")
    assert database.stat().st_mtime_ns == timestamp
    # Reconfigure must remove stale entries, including a removed endpoint.
    (source / "CMakeLists.txt").write_text(cmake[:cmake.index("bsc_add_bluesim")])
    run("cmake", "-S", str(source), "-B", str(build))
    run("cmake", "--build", str(build), "--target", "clean")
    assert not database.exists()
    # A normal build automatically recreates the database.
    run("cmake", "--build", str(build))
    assert [Path(e["file"]).name for e in json.loads(database.read_text())] == ["Base.bsv"]
    # Broken sources and paths with spaces must not prevent direct export.
    spaced = source / "space dir"
    spaced.mkdir()
    (spaced / "Broken.bsv").write_text("not valid BSV")
    (source / "CMakeLists.txt").write_text(cmake[:cmake.index("bsc_add_bluesim")] +
        '\nbsc_add_library(broken SOURCES "space dir/Broken.bsv")\n' +
        'bsc_target_compile_definitions(broken PRIVATE [=[LABEL="hello world"]=])\n')
    run("cmake", "-S", str(source), "-B", str(build))
    run("cmake", "-P", str(build / "bsc_compile_commands.cmake"))
    broken = next(e for e in json.loads(database.read_text()) if e["file"].endswith("Broken.bsv"))
    assert 'LABEL="hello world"' in broken["arguments"]
    assert str(spaced) in broken["arguments"][-1].split(":")
print("Compilation database integration check passed")
