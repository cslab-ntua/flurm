"""Add a managed release pair to copied Flux recipes without line-number edits."""

import argparse
import ast
import re
import textwrap
from pathlib import Path


def remove_managed_blocks(source, version=None, expected=None):
    def replace(match):
        if version is None:
            return ""
        content = match.group(0)
        if " managed environment" in content.splitlines()[0]:
            return "" if repr("@=" + version) in content else content
        tree = ast.parse(textwrap.dedent(content))
        call = tree.body[0].value
        if ast.literal_eval(call.args[0]) != version:
            return content
        metadata = {keyword.arg: ast.literal_eval(keyword.value) for keyword in call.keywords}
        dependency = None
        if len(tree.body) > 1:
            dependency = ast.literal_eval(tree.body[1].value.args[0])
        if expected and (
            metadata["url"] != expected["url"]
            or metadata["sha256"] != expected["sha256"].lower()
            or (expected.get("core_version") is not None
                and dependency != "flux-core@=" + expected["core_version"])
        ):
            raise ValueError(
                f"Release {version} already exists with different metadata or Core dependency. "
                "Publish a new version instead of changing an existing release."
            )
        return ""

    return re.sub(
        r"(?m)^(?P<indent> *)# BEGIN customflux managed [^\n]+\n"
        r".*?^(?P=indent)# END customflux managed [^\n]+\n",
        replace,
        source,
        flags=re.DOTALL,
    )


def class_node(source, name):
    return next(
        node for node in ast.parse(source).body
        if isinstance(node, ast.ClassDef) and node.name == name
    )


def prepare(path, name, version, url, checksum, core_version=None):
    original = path.read_text()
    source = remove_managed_blocks(original, version, {
        "url": url, "sha256": checksum,
        "core_version": core_version if name == "FluxSched" else None,
    })
    cls = class_node(source, name)
    for node in cls.body:
        if (isinstance(node, ast.Expr) and isinstance(node.value, ast.Call)
                and isinstance(node.value.func, ast.Name)
                and node.value.func.id == "version" and node.value.args
                and isinstance(node.value.args[0], ast.Constant)
                and node.value.args[0].value == version):
            raise ValueError(
                f"{path}: version {version} already has a manual declaration. "
                "Remove that declaration before using automatic configuration."
            )

    if name == "FluxCore":
        method = next(
            node for node in cls.body
            if isinstance(node, ast.FunctionDef)
            and node.name == "setup_build_environment"
        )
        # Insert after any docstring, preserving the original method and annotations.
        first = method.body[0]
        has_docstring = (isinstance(first, ast.Expr)
                         and isinstance(first.value, ast.Constant)
                         and isinstance(first.value.value, str))
        insertion = first.end_lineno if has_docstring else first.lineno - 1
        lines = source.splitlines(keepends=True)
        if not has_docstring:
            # Keep existing managed comment boundaries intact when adding a version.
            while insertion > method.lineno and (
                not lines[insertion - 1].strip()
                or lines[insertion - 1].lstrip().startswith("#")
            ):
                insertion -= 1
        env_name = method.args.args[1].arg
        indent = " " * first.col_offset
        block = [
            f"{indent}# BEGIN customflux managed environment\n",
            f"{indent}if self.spec.satisfies({'@=' + version!r}):\n",
            f"{indent}    {env_name}.set('FLUX_VERSION', {version!r})\n",
            f"{indent}# END customflux managed environment\n",
        ]
        lines[insertion:insertion] = block
        source = "".join(lines)

    # Find the class again because the environment insertion changes line numbers.
    cls = class_node(source, name)
    indent = " " * cls.body[0].col_offset
    statements = [f"version({version!r}, url={url!r}, sha256={checksum.lower()!r})"]
    if name == "FluxCore":
        statements.extend(
            f"depends_on({tool!r}, type='build', when={'@=' + version!r})"
            for tool in ("autoconf", "automake", "libtool")
        )
    else:
        statements.append(
            f"depends_on({'flux-core@=' + core_version!r}, when={'@=' + version!r})"
        )
    block = [f"{indent}# BEGIN customflux managed release\n"]
    block.extend(f"{indent}{statement}\n" for statement in statements)
    block.append(f"{indent}# END customflux managed release\n")
    lines = source.splitlines(keepends=True)
    first = cls.body[0]
    has_docstring = (isinstance(first, ast.Expr)
                     and isinstance(first.value, ast.Constant)
                     and isinstance(first.value.value, str))
    insertion = first.end_lineno if has_docstring else cls.lineno
    lines[insertion:insertion] = block
    result = "".join(lines)
    ast.parse(result, filename=str(path))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    for package in ("core", "sched"):
        for field in ("version", "url", "sha256"):
            parser.add_argument(f"--{package}-{field}", required=True)
    args = parser.parse_args()
    updates = []
    try:
        for package, name in (("core", "FluxCore"), ("sched", "FluxSched")):
            path = args.repo / "packages" / f"flux_{package}" / "package.py"
            result = prepare(
                path, name, getattr(args, f"{package}_version"),
                getattr(args, f"{package}_url"), getattr(args, f"{package}_sha256"),
                args.core_version,
            )
            updates.append((path, result))
    except (ValueError, StopIteration, SyntaxError, OSError) as error:
        parser.exit(1, f"Cannot configure Flux recipes: {error}\n")
    # Validate both recipes before changing either. Preserve originals once.
    for path, result in updates:
        backup = path.with_name("package.py.before-customflux")
        if not backup.exists():
            backup.write_text(path.read_text())
        path.write_text(result)
        print(f"Configured {path}")


if __name__ == "__main__":
    main()
