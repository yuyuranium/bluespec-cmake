#!/usr/bin/env python3
"""Generate Bluespec endpoint artifacts from CMake-built package objects.

CMake owns the component and package graph.  This driver validates the
build-time topology, elaborates the endpoint top module, and produces the
requested Bluesim, Verilog, or SystemC artifact.  It intentionally uses only
the Python standard library.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import shutil
import signal
import shlex
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


class DriverError(RuntimeError):
    pass


_ACTIVE_CHILD: subprocess.Popen[str] | None = None


def _die(message: str) -> "NoReturn":
    raise DriverError(message)


def _canonical(path: str | Path) -> Path:
    return Path(path).expanduser().resolve(strict=False)


def _read_request(path: Path) -> dict[str, object]:
    """Read the small line-oriented request format emitted by CMake."""
    if not path.exists():
        _die(f"request file does not exist: {path}")
    scalar: dict[str, str] = {}
    blocks: dict[str, list[str]] = {}
    active: str | None = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip("\r")
        if not line:
            continue
        if line.endswith("_begin"):
            active = line[:-6]
            blocks.setdefault(active, [])
            continue
        if line.endswith("_end"):
            active = None
            continue
        if active is not None:
            blocks[active].append(line)
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            scalar[key] = value
    result: dict[str, object] = dict(scalar)
    result.update(blocks)
    return result


def _as_list(value: object) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item) for item in value if str(item)]
    if isinstance(value, str) and value:
        return [value]
    return []


def _make_path(path: str | Path) -> str:
    value = str(path)
    value = value.replace("\\", "\\\\").replace(" ", "\\ ")
    value = value.replace("#", "\\#")
    return value


def _run(command: list[str], *, cwd: Path | None = None,
         capture: bool = False, check: bool = True,
         env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    global _ACTIVE_CHILD
    if os.environ.get("BSC_CMAKE_VERBOSE"):
        print("[bluespec-cmake]", " ".join(_shell_quote(x) for x in command), flush=True)

    previous_handlers: dict[int, object] = {}

    def forward(signum: int, frame: object) -> None:
        child = _ACTIVE_CHILD
        if child is not None and child.poll() is None:
            child.send_signal(signum)
            return
        previous = previous_handlers.get(signum)
        if callable(previous):
            previous(signum, frame)

    try:
        child = subprocess.Popen(
            command,
            cwd=str(cwd) if cwd else None,
            env=env,
            text=True,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
        )
        _ACTIVE_CHILD = child
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.getsignal(signum)
            signal.signal(signum, forward)
        stdout, stderr = child.communicate()
        result = subprocess.CompletedProcess(command, child.returncode, stdout, stderr)
        if check and child.returncode:
            raise subprocess.CalledProcessError(
                child.returncode, command, output=stdout, stderr=stderr)
        return result
    except KeyboardInterrupt:
        child = _ACTIVE_CHILD
        if child is not None and child.poll() is None:
            child.send_signal(signal.SIGINT)
            child.wait()
        raise
    except FileNotFoundError as exc:
        _die(f"tool not found while running {command[0]}: {exc}")
    except subprocess.CalledProcessError as exc:
        if exc.stdout:
            sys.stdout.write(exc.stdout)
        if exc.stderr:
            sys.stderr.write(exc.stderr)
        raise DriverError(f"command failed with exit code {exc.returncode}: {command[0]}") from exc
    finally:
        for signum, previous in previous_handlers.items():
            signal.signal(signum, previous)
        _ACTIVE_CHILD = None


def _shell_quote(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_./:+%=-]+", value):
        return value
    return "'" + value.replace("'", "'\\''") + "'"


@dataclass(frozen=True)
class Component:
    name: str
    request: Path
    sources: tuple[Path, ...]
    definitions: tuple[str, ...]
    compile_options: tuple[str, ...]
    native_sources: tuple[Path, ...]
    native_libraries: tuple[str, ...]


@dataclass
class Provider:
    package: str
    source: Path
    component: str


@dataclass
class PackageNode:
    provider: Provider
    imports: set[str] = field(default_factory=set)
    includes: set[Path] = field(default_factory=set)


def _load_component(path: Path) -> Component:
    request = _read_request(path)
    if request.get("kind") != "component":
        _die(f"not a component request: {path}")
    sources = tuple(_canonical(item) for item in _as_list(request.get("sources")))
    native_sources = tuple(_canonical(item) for item in _as_list(request.get("native_sources")))
    return Component(
        name=str(request.get("name", path.stem)),
        request=path,
        sources=sources,
        definitions=tuple(_as_list(request.get("definitions"))),
        compile_options=tuple(_as_list(request.get("compile_options"))),
        native_sources=native_sources,
        native_libraries=tuple(_as_list(request.get("native_libraries"))),
    )


def _enumerate_sources(
    components: Iterable[Component], endpoint_sources: Iterable[Path] = ()
) -> dict[str, list[Provider]]:
    providers: dict[str, list[Provider]] = {}
    seen: set[tuple[str, Path, str]] = set()

    def add(component: str, source: Path) -> None:
        if source.suffix != ".bsv" or not source.exists():
            return
        package = source.stem
        key = (package, source, component)
        if key in seen:
            return
        seen.add(key)
        candidate = Provider(package, source, component)
        if all(existing.source != source for existing in providers.get(package, [])):
            providers.setdefault(package, []).append(candidate)

    for component in components:
        for source in component.sources:
            add(component.name, source)
    for source in endpoint_sources:
        add("__endpoint__", source)
    return providers


def _bsc_flags(definitions: Iterable[str], options: Iterable[str]) -> list[str]:
    flags: list[str] = []
    seen_definitions: set[str] = set()
    for definition in definitions:
        value = definition[2:] if definition.startswith("-D") else definition
        # BSC's -D option takes the following token as its value.  Deduplicate
        # complete definitions, not the individual ``-D`` marker: emitting a
        # single marker for several definitions makes the second definition
        # look like a source file and causes later flags to be rejected as
        # appearing after a source.
        if value not in seen_definitions:
            flags.extend(("-D", value))
            seen_definitions.add(value)
    # Options form an ordered token stream.  Do not deduplicate individual
    # tokens: options such as -Xc and -Xc++ may occur repeatedly, with each
    # occurrence consuming the following token.
    flags.extend(options)
    return flags


def _split_rts_flags(flags: Iterable[str]) -> tuple[list[str], list[str]]:
    """Keep GHC runtime flags after BSC's source-file arguments.

    BSC accepts ``+RTS ... -RTS`` only as a trailing argument group.  The
    public CMake option API keeps the group as ordinary list entries, so the
    driver normalizes it for every compiler invocation.
    """
    regular: list[str] = []
    runtime: list[str] = []
    in_runtime = False
    for flag in flags:
        if flag == "+RTS":
            in_runtime = True
            runtime.append(flag)
        elif in_runtime:
            runtime.append(flag)
            if flag == "-RTS":
                in_runtime = False
        else:
            regular.append(flag)
    if in_runtime:
        _die("BSC runtime flag group is missing -RTS")
    return regular, runtime


def _parse_makedepend(output: str) -> tuple[dict[str, set[str]], set[Path]]:
    """Return target package -> imported package names and source inputs."""
    edges: dict[str, set[str]] = {}
    inputs: set[Path] = set()
    current = ""
    for raw in output.replace("\\\n", " ").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" in line:
            target, deps = line.split(":", 1)
            current = Path(target.strip()).stem
            edges.setdefault(current, set())
            try:
                tokens = shlex.split(deps, comments=False, posix=True)
            except ValueError:
                tokens = deps.split()
        else:
            if not current:
                continue
            try:
                tokens = shlex.split(line, comments=False, posix=True)
            except ValueError:
                tokens = line.split()
        for token in tokens:
            if token.endswith(".bo"):
                edges[current].add(Path(token).stem)
            elif token.endswith(".bsv") or Path(token).exists():
                inputs.add(_canonical(token))
    return edges, inputs


def _scan_package(
    package: Provider,
    component: Component,
    *,
    bluetcl: str,
    scan_dir: Path,
    search_dirs: list[Path],
    backend_flags: list[str],
) -> PackageNode:
    scan_dir.mkdir(parents=True, exist_ok=True)
    path_arg = ":".join(["%/Libraries", *(str(path) for path in search_dirs)])
    regular_flags, runtime_flags = _split_rts_flags(
        _bsc_flags(component.definitions, component.compile_options))
    command = [
        bluetcl,
        "-exec",
        "makedepend",
        *backend_flags,
        *regular_flags,
        "-bdir",
        str(scan_dir),
        "-p",
        path_arg,
        str(package.source),
        *runtime_flags,
    ]
    result = _run(command, capture=True, check=False)
    if result.stderr:
        # BSC emits useful warnings here.  Keep them visible but do not hide
        # the command's normal output; missing providers are diagnosed below.
        sys.stderr.write(result.stderr)
    if result.returncode != 0:
        _die(f"dependency scan failed for package {package.package}")
    edges, includes = _parse_makedepend(result.stdout)
    return PackageNode(package, edges.get(package.package, set()), includes)


def _all_search_dirs(components: Iterable[Component]) -> list[Path]:
    """Return directories containing explicitly owned BSV packages."""
    result: set[Path] = set()
    for component in components:
        for source in component.sources:
            result.add(source.parent)
    return sorted(result)


def _endpoint_flags(endpoint: dict[str, object]) -> tuple[list[str], list[str]]:
    definitions = _as_list(endpoint.get("definitions"))
    return _bsc_flags(definitions, ()), _as_list(endpoint.get("link_options"))


def _write_depfile(
    path: Path, stamp: Path, inputs: Iterable[Path], request: Path
) -> None:
    dependencies = sorted({_canonical(item) for item in inputs} | {request})
    _atomic_write(
        path,
        f"{_make_path(stamp)}: " + " ".join(_make_path(item) for item in dependencies) + "\n",
    )


def _load_graph(
    path: Path,
    providers: dict[str, list[Provider]],
) -> tuple[dict[str, PackageNode], set[Path]]:
    """Load the endpoint topology produced by the CMake graph scanner."""
    if not path.exists():
        _die(f"endpoint package topology does not exist: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        _die(f"cannot read endpoint package topology {path}: {exc}")
    nodes: dict[str, PackageNode] = {}
    inputs: set[Path] = set()
    for item in value.get("packages", []):
        package = str(item.get("name", ""))
        source = _canonical(str(item.get("source", "")))
        candidates = [candidate for candidate in providers.get(package, [])
                      if candidate.source == source]
        if not candidates:
            _die(
                f"package topology provider is not in the endpoint request: "
                f"{package} ({source})"
            )
        imports = {str(imported) for imported in item.get("imports", [])}
        includes = {
            _canonical(str(input_path))
            for input_path in item.get("inputs", [])
            if _canonical(str(input_path)) != source
        }
        nodes[package] = PackageNode(candidates[0], imports, includes)
        inputs.update({source, *includes})
    for package, node in nodes.items():
        for imported in node.imports:
            if imported not in providers:
                _die(
                    f"package topology for '{package}' references missing "
                    f"package '{imported}'"
                )
    return nodes, inputs


def _atomic_write(path: Path, data: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)


def _translate_off(path: Path, output: Path, pattern: str, require: bool) -> None:
    off = re.compile(r"^[ \t]*//[ \t]*(?:synopsys|synthesis)[ \t]+translate_off")
    on = re.compile(r"^[ \t]*//[ \t]*(?:synopsys|synthesis)[ \t]+translate_on")
    matcher = re.compile(pattern)
    lines = path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n").splitlines(True)
    result: list[str] = []
    in_block = False
    start = ""
    body: list[str] = []
    matched = False
    matched_count = 0
    for line in lines:
        if not in_block:
            if off.match(line):
                in_block = True
                start = line
                body = []
                matched = False
            else:
                result.append(line)
        else:
            if matcher.search(line):
                matched = True
            if on.match(line):
                if matched:
                    result.extend(body)
                    matched_count += 1
                else:
                    result.extend([start, *body, line])
                in_block = False
            else:
                body.append(line)
    if in_block:
        result.extend([start, *body])
    if require and matched_count == 0:
        _die(f"no translate_off block matching '{pattern}' was found in {path}")
    _atomic_write(output, "".join(result))


def _jobs(default: int | None = None) -> int:
    value = os.environ.get("BSC_BUILD_JOBS")
    if value:
        try:
            return max(1, int(value))
        except ValueError:
            _die("BSC_BUILD_JOBS must be an integer")
    return default if default is not None else (os.cpu_count() or 1)


def _find_tool(name: str) -> str:
    value = shutil.which(name)
    if not value:
        _die(f"required tool '{name}' was not found")
    return value


def _tool_signature(path: str) -> dict[str, object]:
    try:
        stat = Path(path).stat()
    except OSError:
        return {"path": os.path.realpath(path)}
    return {
        "path": os.path.realpath(path),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
    }


def _context_id(endpoint: dict[str, object], components: dict[str, Component], bsc: str) -> str:
    payload = {
        "backend": endpoint.get("backend"),
        "configuration": endpoint.get("configuration"),
        "top": endpoint.get("top_module"),
        "definitions": endpoint.get("definitions", []),
        "compile_options": endpoint.get("compile_options", []),
        "top_source": endpoint.get("top_source", ""),
        "components": {
            name: {
                "sources": [str(item) for item in component.sources],
                "definitions": component.definitions,
                "compile_options": component.compile_options,
            }
            for name, component in sorted(components.items())
        },
        "tools": {
            "bsc": _tool_signature(bsc),
        },
    }
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()[:20]


def _build(
    request_path: Path,
    stamp: Path,
    depfile: Path,
    artifact_dir: Path,
    bo_dir: Path,
    topology_path: Path,
    package_bo_dirs: list[Path],
) -> None:
    endpoint = _read_request(request_path)
    if endpoint.get("kind") != "endpoint":
        _die(f"not an endpoint request: {request_path}")
    component_paths = [_canonical(item) for item in _as_list(endpoint.get("component_requests"))]
    components_list = [_load_component(path) for path in component_paths]
    components = {component.name: component for component in components_list}

    bsc = str(endpoint.get("bsc") or _find_tool("bsc"))
    ar = str(endpoint.get("ar") or _find_tool("ar"))

    # Native dependencies attached to a component are part of the endpoint's
    # link closure.  Keep the endpoint request's direct values first, then add
    # component values in graph order while preserving uniqueness.
    native_sources: list[str] = []
    native_libraries: list[str] = []
    for value in (*_as_list(endpoint.get("native_sources")),
                  *(str(item) for component in components_list for item in component.native_sources)):
        if value not in native_sources:
            native_sources.append(value)
    for value in (*_as_list(endpoint.get("native_libraries")),
                  *(component.native_libraries for component in components_list)):
        if isinstance(value, tuple):
            for item in value:
                if item not in native_libraries:
                    native_libraries.append(item)
        elif value not in native_libraries:
            native_libraries.append(value)
    endpoint["native_sources"] = native_sources
    endpoint["native_libraries"] = native_libraries

    top_source = endpoint.get("top_source", "")
    top_source_path = _canonical(str(top_source)) if top_source else None

    driver_components = dict(components)
    if top_source_path is not None:
        driver_components["__endpoint__"] = Component(
            "__endpoint__",
            request_path,
            (top_source_path,),
            tuple(_as_list(endpoint.get("definitions"))),
            tuple(_as_list(endpoint.get("compile_options"))),
            tuple(_as_list(endpoint.get("native_sources"))),
            tuple(_as_list(endpoint.get("native_libraries"))),
        )

    endpoint_sources = (top_source_path,) if top_source_path is not None else ()
    providers = _enumerate_sources(components_list, endpoint_sources)

    context = _context_id(endpoint, driver_components, bsc)
    work_directory = _canonical(str(endpoint.get("work_directory") or artifact_dir.parent))
    context_dir = work_directory / "contexts" / context
    bo_dir = _canonical(bo_dir)
    external_bo_dirs = [_canonical(item) for item in package_bo_dirs]
    info_dir = context_dir / "info"
    context_dir.mkdir(parents=True, exist_ok=True)
    bo_dir.mkdir(parents=True, exist_ok=True)
    info_dir.mkdir(parents=True, exist_ok=True)

    lock_path = context_dir / ".lock"
    with lock_path.open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        graph, inputs = _load_graph(topology_path, providers)
        native_inputs = {
            _canonical(value)
            for value in (*native_sources, *native_libraries)
            if value and Path(value).exists()
        }
        _write_depfile(depfile, stamp, {*inputs, *native_inputs}, request_path)

        search_dirs = _all_search_dirs(driver_components.values())
        search_dirs = sorted(set(search_dirs) | set(external_bo_dirs))

        backend = str(endpoint.get("backend", "check"))
        if backend == "check":
            artifact_dir.mkdir(parents=True, exist_ok=True)
        else:
            _generate_endpoint(
                endpoint,
                artifact_dir,
                context_dir,
                bo_dir,
                info_dir,
                search_dirs,
                top_source_path,
                bsc,
                ar,
                jobs=_jobs(1),
            )

        manifest = {
            "schema": 1,
            "endpoint": endpoint,
            "context": context,
            "packages": {
                name: {
                    "source": str(node.provider.source),
                    "imports": sorted(node.imports),
                }
                for name, node in sorted(graph.items())
            },
        }
        _atomic_write(artifact_dir / "manifest.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        _atomic_write(stamp, "success\n")


def _generate_endpoint(
    endpoint: dict[str, object], artifact_dir: Path, context_dir: Path,
    bo_dir: Path, info_dir: Path, search_dirs: list[Path], top_source: Path | None,
    bsc: str, ar: str, *, jobs: int,
) -> None:
    if top_source is None:
        _die("endpoint is missing top source")
    backend = str(endpoint.get("backend"))
    definitions, link_options = _endpoint_flags(endpoint)
    path_arg = ":".join(["%/Libraries", str(bo_dir), *(str(path) for path in search_dirs)])
    top_dir = context_dir / "top"
    sim_dir = context_dir / "sim"
    rtl_dir = artifact_dir / "rtl"
    for directory in (top_dir, sim_dir, rtl_dir, artifact_dir):
        directory.mkdir(parents=True, exist_ok=True)

    if backend in ("bluesim", "systemc"):
        # BSC's backend directories are not content-addressed.  Remove stale
        # native intermediates before a new elaboration so a deleted module
        # cannot accidentally be linked into a later endpoint artifact.
        for old in (*sim_dir.glob("*.o"), *sim_dir.glob("*.a"),
                    *sim_dir.glob("*.cxx"), *sim_dir.glob("*.h")):
            old.unlink()
        compile_flags, runtime_flags = _split_rts_flags([
            *definitions, *(_as_list(endpoint.get("compile_options")))])
        compile_command = [
            bsc, "-sim", "-elab", *compile_flags,
            "-bdir", str(top_dir), "-simdir", str(sim_dir), "-info-dir", str(info_dir),
            "-p", path_arg, "-g", str(endpoint.get("top_module")), str(top_source),
            *runtime_flags,
        ]
        _run(compile_command)
        if backend == "bluesim":
            executable = artifact_dir / str(endpoint.get("target"))
            link_flags, link_runtime_flags = _split_rts_flags(link_options)
            link_command = [
                bsc, "-sim", *link_flags, "-parallel-sim-link", str(jobs),
                "-e", str(endpoint.get("top_module")), "-o", str(executable),
                "-bdir", str(top_dir), "-simdir", str(sim_dir), "-info-dir", str(info_dir),
                "-p", path_arg,
                *_as_list(endpoint.get("native_sources")),
                *_as_list(endpoint.get("native_libraries")),
                *link_runtime_flags,
            ]
            _run(link_command)
            return

        # BSC emits module objects, model objects, and the SystemC wrapper in
        # sim_dir.  Archive only the exact object list observed afterwards.
        link_flags, link_runtime_flags = _split_rts_flags(link_options)
        link_command = [
            bsc, "-systemc", *link_flags, "-parallel-sim-link", str(jobs),
            "-e", str(endpoint.get("top_module")),
            "-bdir", str(top_dir), "-simdir", str(sim_dir), "-info-dir", str(info_dir),
            "-p", path_arg,
            *_as_list(endpoint.get("native_sources")),
            *_as_list(endpoint.get("native_libraries")),
            *link_runtime_flags,
        ]
        _run(link_command)
        objects = sorted(sim_dir.glob("*.o"))
        if not objects:
            _die(f"SystemC endpoint produced no object files for {endpoint.get('top_module')}")
        archive = artifact_dir / f"lib{endpoint.get('target')}.a"
        _run([ar, "rcs", str(archive), *(str(item) for item in objects)], cwd=sim_dir)
        for generated in sim_dir.glob("*.h"):
            shutil.copy2(generated, artifact_dir / generated.name)
        return

    if backend == "verilog":
        rtl_dir.mkdir(parents=True, exist_ok=True)
        # Do not let removed generated modules survive in the public filelist.
        for old in rtl_dir.glob("*.v"):
            old.unlink()
        compile_flags, runtime_flags = _split_rts_flags([
            *definitions, *(_as_list(endpoint.get("compile_options")))])
        command = [
            bsc, "-verilog", "-elab", *compile_flags,
            "-bdir", str(top_dir), "-vdir", str(rtl_dir), "-info-dir", str(info_dir),
            "-p", path_arg, "-g", str(endpoint.get("top_module")), str(top_source),
            *runtime_flags,
        ]
        _run(command)
        generated = sorted(rtl_dir.glob("*.v"))
        if not generated:
            _die(f"Verilog endpoint produced no .v files for {endpoint.get('top_module')}")
        primary = rtl_dir / f"{endpoint.get('top_module')}.v"
        public_primary = artifact_dir / f"{endpoint.get('top_module')}.v"
        if primary.exists():
            regex = str(endpoint.get("translate_off_regex", ""))
            if regex:
                _translate_off(primary, public_primary, regex, str(endpoint.get("require_translate_off_match", "")) == "TRUE")
            else:
                shutil.copy2(primary, public_primary)
        filelist = artifact_dir / f"{endpoint.get('target')}.f"
        filelist_entries = [
            str(public_primary if item == primary and public_primary.exists() else item)
            for item in generated
        ]
        filelist.write_text("\n".join(filelist_entries) + "\n", encoding="utf-8")
        return

    _die(f"unsupported endpoint backend: {backend}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="bsc-cmake-driver")
    subparsers = parser.add_subparsers(dest="command", required=True)
    build = subparsers.add_parser("build")
    build.add_argument("--request", type=Path, required=True)
    build.add_argument("--stamp", type=Path, required=True)
    build.add_argument("--depfile", type=Path, required=True)
    build.add_argument("--artifact-dir", type=Path, required=True)
    build.add_argument("--bo-dir", type=Path, required=True)
    build.add_argument("--package-bo-dir", type=Path, action="append", default=[])
    build.add_argument("--topology", type=Path, required=True)
    args = parser.parse_args(argv)

    try:
        if args.command == "build":
            _build(
                args.request,
                args.stamp,
                args.depfile,
                args.artifact_dir,
                args.bo_dir,
                args.topology,
                args.package_bo_dir,
            )
        return 0
    except DriverError as exc:
        print(f"bsc-cmake-driver: error: {exc}", file=sys.stderr)
        with contextlib.suppress(FileNotFoundError):
            args.stamp.unlink()
        return 1
    except KeyboardInterrupt:
        with contextlib.suppress(FileNotFoundError):
            args.stamp.unlink()
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
