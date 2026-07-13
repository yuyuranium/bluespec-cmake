#!/usr/bin/env python3
"""CMake package graph adapter.

This tool discovers imports with bluetcl and compiles the individual package
requested by one of CMake's custom commands.  It never invokes Ninja itself.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

from bsc_cmake_driver import (
    Component,
    DriverError,
    PackageNode,
    Provider,
    _all_search_dirs,
    _as_list,
    _canonical,
    _enumerate_sources,
    _load_component,
    _run,
    _scan_package,
    _split_rts_flags,
    _bsc_flags,
    _read_request,
)


def _file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _replace_if_different(path: Path, content: str) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        if path.exists() and path.read_text(encoding="utf-8") == content:
            os.unlink(temporary)
            return False
        os.replace(temporary, path)
        return True
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _verbose_summary(**values: object) -> None:
    if os.environ.get("BSC_CMAKE_VERBOSE"):
        print(json.dumps(values, sort_keys=True), flush=True)


def _load_endpoint(request_path: Path) -> tuple[
    dict[str, object], list[Component], dict[str, Component], dict[str, list[Provider]],
    Component | None, Path | None
]:
    endpoint = _read_request(request_path)
    if endpoint.get("kind") != "endpoint":
        raise DriverError(f"not an endpoint request: {request_path}")
    component_paths = [
        _canonical(item) for item in _as_list(endpoint.get("component_requests"))
    ]
    components_list = [_load_component(path) for path in component_paths]
    components = {component.name: component for component in components_list}
    missing_sources = [
        source
        for component in components_list
        for source in component.sources
        if not source.exists()
    ]
    top_source_value = str(endpoint.get("top_source") or "")
    top_source = _canonical(top_source_value) if top_source_value else None
    if top_source is not None and not top_source.exists():
        missing_sources.append(top_source)
    if missing_sources:
        details = "\n".join(f"  {item}" for item in sorted(set(missing_sources)))
        raise DriverError(f"explicit BSV source(s) do not exist:\n{details}")
    if top_source is not None:
        components["__endpoint__"] = Component(
            "__endpoint__",
            request_path,
            (top_source,),
            tuple(_as_list(endpoint.get("definitions"))),
            tuple(_as_list(endpoint.get("compile_options"))),
            tuple(_as_list(endpoint.get("native_sources"))),
            tuple(_as_list(endpoint.get("native_libraries"))),
        )
    endpoint_sources = (top_source,) if top_source is not None else ()
    providers = _enumerate_sources(components_list, endpoint_sources)
    if top_source is not None:
        candidates = providers.setdefault(top_source.stem, [])
        if not any(
            item.source == top_source and item.component == "__endpoint__"
            for item in candidates
        ):
            candidates.append(Provider(top_source.stem, top_source, "__endpoint__"))
    return (
        endpoint,
        components_list,
        components,
        providers,
        components.get("__endpoint__"),
        top_source,
    )


def _provider_map(providers: dict[str, list[Provider]]) -> dict[str, Provider]:
    result: dict[str, Provider] = {}
    for package, candidates in sorted(providers.items()):
        distinct = {item.source for item in candidates}
        if len(distinct) > 1:
            details = "\n".join(
                f"  {item.component}: {item.source}" for item in candidates
            )
            raise DriverError(
                f"package provider conflict for '{package}':\n{details}"
            )
        if candidates:
            result[package] = candidates[0]
    return result


def _load_component_context(
    request_path: Path,
    dependency_paths: list[Path],
) -> tuple[Component, list[Component], dict[str, Component], dict[str, Provider]]:
    owner = _load_component(_canonical(request_path))
    components_list = [owner]
    seen_requests = {owner.request}
    for raw_path in dependency_paths:
        path = _canonical(raw_path)
        if path in seen_requests:
            continue
        seen_requests.add(path)
        components_list.append(_load_component(path))
    missing_sources = [
        source
        for component in components_list
        for source in component.sources
        if not source.exists()
    ]
    if missing_sources:
        details = "\n".join(f"  {item}" for item in sorted(set(missing_sources)))
        raise DriverError(f"explicit BSV source(s) do not exist:\n{details}")
    components = {component.name: component for component in components_list}
    if len(components) != len(components_list):
        raise DriverError("component closure contains duplicate target names")
    ownership: dict[str, Component] = {}
    for component in components_list:
        for source in component.sources:
            previous = ownership.get(source.stem)
            if previous is not None and previous.name != component.name:
                raise DriverError(
                    f"package '{source.stem}' is owned by both "
                    f"'{previous.name}' and '{component.name}'"
                )
            ownership[source.stem] = component
    providers = _provider_map(_enumerate_sources(components_list))
    return owner, components_list, components, providers


def _component_context_key(
    request_path: Path,
    components: dict[str, Component],
    bsc: str,
    bluetcl: str,
) -> str:
    payload = {
        "owner": str(request_path),
        "components": {
            name: {
                "request": str(component.request),
                "request_digest": (
                    _file_digest(component.request)
                    if component.request.exists() else "missing"
                ),
            }
            for name, component in sorted(components.items())
        },
        "bsc": str(bsc),
        "bluetcl": str(bluetcl),
    }
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True).encode("utf-8")
    ).hexdigest()


def _context_key(
    request_path: Path,
    endpoint: dict[str, object],
    components: dict[str, Component],
    bsc: str,
    bluetcl: str,
) -> str:
    payload = {
        "request": str(request_path),
        "request_digest": _file_digest(request_path),
        "endpoint": {
            "definitions": endpoint.get("definitions", []),
            "compile_options": endpoint.get("compile_options", []),
        },
        "components": {
            name: {
                "request": str(component.request),
                "request_digest": (
                    _file_digest(component.request)
                    if component.request.exists() else "missing"
                ),
            }
            for name, component in sorted(components.items())
        },
        "bsc": str(bsc),
        "bluetcl": str(bluetcl),
    }
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True).encode("utf-8")
    ).hexdigest()


def _load_cache(path: Path, context: str) -> dict[str, dict]:
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if value.get("context") != context:
        return {}
    packages = value.get("packages", {})
    return packages if isinstance(packages, dict) else {}


def _cached_node(
    provider: Provider,
    cached: dict[str, object] | None,
) -> PackageNode | None:
    if not cached:
        return None
    fingerprints = cached.get("fingerprints", {})
    if not isinstance(fingerprints, dict) or not fingerprints:
        return None
    for raw_path, expected in fingerprints.items():
        path = Path(str(raw_path))
        if not path.exists() or _file_digest(path) != str(expected):
            return None
    imports = {str(item) for item in cached.get("imports", [])}
    includes = {Path(str(item)) for item in cached.get("includes", [])}
    return PackageNode(provider, imports, includes)


def scan_component(
    request_path: Path,
    dependency_paths: list[Path],
    output: Path,
    cache_path: Path,
    scan_dir: Path,
    bsc: str,
    bluetcl: str,
) -> None:
    owner, components_list, components, provider_by_name = _load_component_context(
        request_path, dependency_paths
    )
    search_dirs = _all_search_dirs(components_list)
    context = _component_context_key(
        _canonical(request_path), components, bsc, bluetcl
    )
    cached = _load_cache(cache_path, context)
    owner_packages = {source.stem: source for source in owner.sources}
    nodes: dict[str, PackageNode] = {}
    cache_entries: dict[str, dict[str, object]] = {}
    cache_hits: list[str] = []
    rescanned: list[str] = []
    for package, source in sorted(owner_packages.items()):
        provider = provider_by_name.get(package)
        if provider is None or provider.source != source:
            raise DriverError(
                f"component '{owner.name}' does not uniquely provide '{package}'"
            )
        node = _cached_node(provider, cached.get(package))
        if node is not None:
            cache_hits.append(package)
        else:
            node = _scan_package(
                provider,
                owner,
                bluetcl=bluetcl,
                scan_dir=scan_dir / package,
                search_dirs=search_dirs,
                backend_flags=[],
            )
            rescanned.append(package)
        for imported in node.imports:
            if imported not in provider_by_name:
                raise DriverError(
                    f"package '{package}' imports '{imported}', but no provider was found"
                )
        nodes[package] = node
        inputs = {provider.source, *node.includes}
        cache_entries[package] = {
            "fingerprints": {
                str(item): _file_digest(item)
                for item in sorted(inputs)
                if item.exists()
            },
            "imports": sorted(node.imports),
            "includes": sorted(str(item) for item in node.includes),
        }
    topology = {
        "component": owner.name,
        "packages": [
            {
                "imports": sorted(node.imports),
                "inputs": sorted(
                    str(item) for item in {node.provider.source, *node.includes}
                ),
                "name": package,
                "source": str(node.provider.source),
            }
            for package, node in sorted(nodes.items())
        ],
        "schema": 2,
    }
    changed = _replace_if_different(
        output, json.dumps(topology, indent=2, sort_keys=True) + "\n"
    )
    _replace_if_different(
        cache_path,
        json.dumps(
            {"context": context, "packages": cache_entries, "schema": 1},
            indent=2,
            sort_keys=True,
        )
        + "\n",
    )
    _verbose_summary(
        cache_hits=cache_hits,
        changed=changed,
        component=owner.name,
        rescanned=rescanned,
    )


def scan_endpoint(
    request_path: Path,
    output: Path,
    cache_path: Path,
    scan_dir: Path,
) -> None:
    endpoint, _, components, providers, endpoint_component, top_source = (
        _load_endpoint(request_path)
    )
    if endpoint_component is None or top_source is None:
        raise DriverError("endpoint dependency scan requires a top source")
    provider_by_name = _provider_map(providers)
    top_provider = Provider(top_source.stem, top_source, "__endpoint__")
    search_dirs = _all_search_dirs(components.values())
    bsc = str(endpoint.get("bsc") or "bsc")
    bluetcl = str(endpoint.get("bluetcl") or "bluetcl")
    context = _context_key(request_path, endpoint, components, bsc, bluetcl)
    cached = _load_cache(cache_path, context)
    node = _cached_node(top_provider, cached.get(top_provider.package))
    cache_hit = node is not None
    if node is None:
        backend = str(endpoint.get("backend") or "")
        backend_flags = ["-sim"] if backend in ("bluesim", "systemc") else []
        if backend == "verilog":
            backend_flags = ["-verilog"]
        node = _scan_package(
            top_provider,
            endpoint_component,
            bluetcl=bluetcl,
            scan_dir=scan_dir / top_provider.package,
            search_dirs=search_dirs,
            backend_flags=backend_flags,
        )
    for imported in node.imports:
        if imported not in provider_by_name:
            raise DriverError(
                f"endpoint package '{top_provider.package}' imports '{imported}', "
                "but no linked component provides it"
            )
    inputs = {top_provider.source, *node.includes}
    topology = {
        "endpoint": str(endpoint.get("target") or ""),
        "packages": [
            {
                "imports": sorted(node.imports),
                "inputs": sorted(str(item) for item in inputs),
                "name": top_provider.package,
                "source": str(top_provider.source),
            }
        ],
        "schema": 2,
    }
    changed = _replace_if_different(
        output, json.dumps(topology, indent=2, sort_keys=True) + "\n"
    )
    _replace_if_different(
        cache_path,
        json.dumps(
            {
                "context": context,
                "packages": {
                    top_provider.package: {
                        "fingerprints": {
                            str(item): _file_digest(item)
                            for item in sorted(inputs)
                            if item.exists()
                        },
                        "imports": sorted(node.imports),
                        "includes": sorted(str(item) for item in node.includes),
                    }
                },
                "schema": 1,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
    )
    _verbose_summary(
        cache_hit=cache_hit,
        changed=changed,
        endpoint=endpoint.get("target", ""),
    )


def init_topology(output: Path, sources: list[Path]) -> None:
    packages = [
        {
            "imports": [],
            "inputs": [str(source)],
            "name": source.stem,
            "source": str(source),
        }
        for source in sorted(sources)
    ]
    changed = _replace_if_different(
        output,
        json.dumps({"packages": packages, "schema": 1}, indent=2, sort_keys=True)
        + "\n",
    )
    # The configure-time placeholder must be rebuilt once by Ninja.  Give it
    # an old timestamp so the first scanner edge is dirty; subsequent scans
    # preserve the timestamp when the canonical topology is unchanged.
    if changed:
        os.utime(output, (0, 0))


def compile_component_package(
    request_path: Path,
    dependency_paths: list[Path],
    dependency_bo_dirs: list[Path],
    source: Path,
    output: Path,
    bo_dir: Path,
    info_dir: Path,
    bsc: str,
) -> None:
    owner, components_list, _, provider_by_name = _load_component_context(
        request_path, dependency_paths
    )
    source = _canonical(source)
    if source not in owner.sources:
        raise DriverError(
            f"package source is not owned by component '{owner.name}': {source}"
        )
    provider = provider_by_name.get(source.stem)
    if provider is None or provider.source != source:
        raise DriverError(f"package source is not in the component inventory: {source}")
    search_dirs = _all_search_dirs(components_list)
    regular_flags, runtime_flags = _split_rts_flags(
        _bsc_flags(owner.definitions, owner.compile_options)
    )
    # A component-level dependency does not imply that every package in the
    # consumer imports a package from that dependency.  With package-granular
    # outer build edges, unrelated consumer packages may therefore compile
    # before the dependency's output directory has been created.  Do not pass
    # those not-yet-materialized directories to BSC: it removes them from -p
    # anyway, but emits S0091 for every package invocation.  When an import
    # actually needs a dependency package, the generated custom command has a
    # file-level dependency on that package's .bo, so its directory exists by
    # the time this command runs.
    package_paths = [
        *(
            path
            for item in dependency_bo_dirs
            if (path := _canonical(item)).is_dir()
        ),
        *search_dirs,
    ]
    unique_paths: list[Path] = []
    for path in package_paths:
        if path not in unique_paths:
            unique_paths.append(path)
    path_arg = ":".join(["%/Libraries", *(str(item) for item in unique_paths)])
    bo_dir.mkdir(parents=True, exist_ok=True)
    info_dir.mkdir(parents=True, exist_ok=True)
    command = [
        bsc,
        *regular_flags,
        "-bdir",
        str(bo_dir),
        "-info-dir",
        str(info_dir),
        "-p",
        path_arg,
        str(source),
        *runtime_flags,
    ]
    _run(command)
    if not output.exists():
        raise DriverError(f"BSC did not produce expected package object: {output}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="bsc_graph")
    subparsers = parser.add_subparsers(dest="command", required=True)
    scan_component_parser = subparsers.add_parser("scan-component")
    scan_component_parser.add_argument("--request", type=Path, required=True)
    scan_component_parser.add_argument(
        "--dependency-request", type=Path, action="append", default=[]
    )
    scan_component_parser.add_argument("--output", type=Path, required=True)
    scan_component_parser.add_argument("--cache", type=Path, required=True)
    scan_component_parser.add_argument("--scan-dir", type=Path, required=True)
    scan_component_parser.add_argument("--bsc", required=True)
    scan_component_parser.add_argument("--bluetcl", required=True)
    scan_endpoint_parser = subparsers.add_parser("scan-endpoint")
    scan_endpoint_parser.add_argument("--request", type=Path, required=True)
    scan_endpoint_parser.add_argument("--output", type=Path, required=True)
    scan_endpoint_parser.add_argument("--cache", type=Path, required=True)
    scan_endpoint_parser.add_argument("--scan-dir", type=Path, required=True)
    init_parser = subparsers.add_parser("init")
    init_parser.add_argument("--output", type=Path, required=True)
    init_parser.add_argument("--source", type=Path, action="append", required=True)
    compile_component_parser = subparsers.add_parser("compile-component")
    compile_component_parser.add_argument("--request", type=Path, required=True)
    compile_component_parser.add_argument(
        "--dependency-request", type=Path, action="append", default=[]
    )
    compile_component_parser.add_argument(
        "--dependency-bo-dir", type=Path, action="append", default=[]
    )
    compile_component_parser.add_argument("--source", type=Path, required=True)
    compile_component_parser.add_argument("--output", type=Path, required=True)
    compile_component_parser.add_argument("--bo-dir", type=Path, required=True)
    compile_component_parser.add_argument("--info-dir", type=Path, required=True)
    compile_component_parser.add_argument("--bsc", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "scan-component":
            scan_component(
                args.request,
                args.dependency_request,
                args.output,
                args.cache,
                args.scan_dir,
                args.bsc,
                args.bluetcl,
            )
        elif args.command == "scan-endpoint":
            scan_endpoint(args.request, args.output, args.cache, args.scan_dir)
        elif args.command == "init":
            init_topology(args.output, [_canonical(item) for item in args.source])
        else:
            compile_component_package(
                args.request,
                args.dependency_request,
                args.dependency_bo_dir,
                args.source,
                args.output,
                args.bo_dir,
                args.info_dir,
                args.bsc,
            )
        return 0
    except DriverError as exc:
        print(f"bsc_graph: error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
