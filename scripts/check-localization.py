#!/usr/bin/env python3
"""Static checks for the in-app language switch (see Shared/Localization.swift).

The repository has no Swift unit-test target, so these checks stand in for the compiler when
copy is wrapped in ``t(...)``. Run from the repository root:

    python scripts/check-localization.py

What is checked
  1. Every Swift file still parses (tree-sitter; multi-line literals are masked first because
     the bundled grammar cannot parse their escapes).
  2. Every string literal that contains Chinese is wrapped in ``t(...)`` -- except the files
     that legitimately hold Chinese as data (the lookup tables and Localization.swift itself).
  3. Every ``t(...)`` call has a plain literal key (no interpolation) and that key exists in
     exactly one Shared/L10n*.swift table.
  4. Keys and English values carry the same ``%@``/``%%`` placeholders, in the same order, and
     English values contain no Chinese characters.
  5. Table keys are unique across all tables (duplicates silently shadow each other when the
     tables are merged).

Exit code is 1 when an error is found; warnings do not fail the run.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

import tree_sitter_swift
from tree_sitter import Language, Parser

LANGUAGE = Language(tree_sitter_swift.language())
PARSER = Parser(LANGUAGE)

SOURCE_GLOBS = (
    "iPhoneUse/**/*.swift",
    "Shared/*.swift",
    "AgentWidget/*.swift",
    "TunnelProvider/*.swift",
)

# Files that hold Chinese on purpose: the tables are data, Localization.swift names the language.
CJK_EXEMPT = {"Shared/Localization.swift"}

CJK = re.compile(r"[\u3000-\u303f\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff01-\uff60\uffe0-\uffe6\u2018\u2019\u201c\u201d]")
IDEOGRAPH = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
MULTILINE = re.compile(r'"""[\s\S]*?"""')
TABLE_ENTRY = re.compile(r'"((?:[^"\\\n]|\\.)*)"\s*:\s*"((?:[^"\\\n]|\\.)*)"')
PLACEHOLDER = re.compile(r"%(?:@|%)")
STRAY_PERCENT = re.compile(r"%(?![@%])")

# Strings that are allowed to stay Chinese because they are not shown in the app UI. None for
# now; add the literal text here only with a comment explaining why.
ALLOWED_KEYS: set[str] = set()

errors: list[str] = []
warnings: list[str] = []


def error(where: str, message: str) -> None:
    errors.append(f"{where}: {message}")


def warn(where: str, message: str) -> None:
    warnings.append(f"{where}: {message}")


def read(path: str) -> str:
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def mask_multiline(source: str) -> str:
    """Replace every multi-line literal with a placeholder, keeping line numbers stable."""

    def repl(match: re.Match[str]) -> str:
        return '"x"' + "\n" * match.group(0).count("\n")

    return MULTILINE.sub(repl, source)


def parse(source: str):
    return PARSER.parse(source.encode("utf-8"))


def walk(node):
    yield node
    for child in node.children:
        yield from walk(child)


def node_text(raw: bytes, node) -> str:
    return raw[node.start_byte : node.end_byte].decode("utf-8")


def unescape_swift(text: str) -> str:
    out: list[str] = []
    index = 0
    while index < len(text):
        char = text[index]
        if char != "\\":
            out.append(char)
            index += 1
            continue
        index += 1
        if index >= len(text):
            out.append("\\")
            break
        escape = text[index]
        if escape == "\\":
            out.append("\\")
        elif escape == '"':
            out.append('"')
        elif escape == "'":
            out.append("'")
        elif escape == "n":
            out.append("\n")
        elif escape == "t":
            out.append("\t")
        elif escape == "r":
            out.append("\r")
        elif escape == "0":
            out.append("\0")
        elif escape == "u" and index + 1 < len(text) and text[index + 1] == "{":
            end = text.index("}", index)
            out.append(chr(int(text[index + 2 : end], 16)))
            index = end
        else:
            out.append(escape)
        index += 1
    return "".join(out)


def literal_value(raw: bytes, node) -> str:
    text = node_text(raw, node)
    start = text.find('"')
    end = text.rfind('"')
    if start < 0 or end <= start:
        return ""
    return unescape_swift(text[start + 1 : end])


def enclosing_call(node):
    parent = node.parent
    while parent is not None:
        if parent.type == "call_expression":
            return parent
        parent = parent.parent
    return None


def call_name(raw: bytes, call) -> str:
    for child in call.children:
        if child.type == "simple_identifier":
            return node_text(raw, child)
        if child.type in ("member_expression", "navigation_expression"):
            return node_text(raw, child)
    return ""


def is_t_argument(raw: bytes, node) -> bool:
    """True when the literal is the first argument of a `t(...)` call."""
    current = node
    parent = current.parent
    while parent is not None:
        if parent.type == "value_argument":
            holder = parent.parent
            if holder is None or holder.type != "value_arguments":
                return False
            arguments = [child for child in holder.children if child.type == "value_argument"]
            if not arguments:
                return False
            first = arguments[0]
            if (first.start_byte, first.end_byte) != (parent.start_byte, parent.end_byte):
                return False
            suffix = holder.parent
            if suffix is None or suffix.type != "call_suffix":
                return False
            call = suffix.parent
            if call is None or call.type != "call_expression":
                return False
            return call_name(raw, call) == "t"
        current, parent = parent, parent.parent
    return False


def has_interpolation(node) -> bool:
    return any(child.type == "interpolated_expression" for child in node.children)


def swift_files(root: str) -> list[str]:
    found: list[str] = []
    for pattern in SOURCE_GLOBS:
        found.extend(glob.glob(os.path.join(root, pattern), recursive=True))
    return sorted(set(found))


def relative(root: str, path: str) -> str:
    return os.path.relpath(path, root).replace("\\", "/")


def check_syntax(root: str, path: str, masked: str) -> None:
    raw = masked.encode("utf-8")
    tree = parse(masked)
    reported = 0
    for node in walk(tree.root_node):
        if node.type == "ERROR" or node.is_missing:
            if node.parent is not None and node.parent.type == "ERROR" and node.type == "ERROR":
                continue
            snippet = node_text(raw, node)[:60].replace("\n", " ")
            error(f"{relative(root, path)}:{node.start_point[0] + 1}", f"parse error near `{snippet}`")
            reported += 1
            if reported >= 5:
                break


def keep_lines(source: str) -> set[int]:
    """Lines opted out with `// l10n:keep <reason>` -- model-facing copy that must not switch."""
    return {
        number
        for number, line in enumerate(source.splitlines(), start=1)
        if "l10n:keep" in line
    }


def check_literals(root: str, path: str, masked: str) -> set[tuple[str, int]]:
    """Return the (key, line) pairs used by `t(...)` and flag unwrapped Chinese literals."""
    rel = relative(root, path)
    raw = masked.encode("utf-8")
    tree = parse(masked)
    keys: set[tuple[str, int]] = set()
    exempt = rel in CJK_EXEMPT or os.path.basename(rel).startswith("L10n")
    keep = keep_lines(masked)

    for node in walk(tree.root_node):
        if node.type != "line_string_literal":
            continue
        value = literal_value(raw, node)
        line = node.start_point[0] + 1
        wrapped = is_t_argument(raw, node)
        if wrapped and has_interpolation(node):
            error(f"{rel}:{line}", "t(...) key must be a literal without interpolation")
            continue
        if wrapped:
            if has_interpolation(node):
                continue
            keys.add((value, line))
            continue
        if exempt or line in keep or (line - 1) in keep:
            continue
        if value in ALLOWED_KEYS:
            continue
        if CJK.search(value):
            error(f"{rel}:{line}", f'unwrapped Chinese string literal: "{value[:60]}"')

    # Catch t(...) calls whose key is not a plain literal at all.
    for node in walk(tree.root_node):
        if node.type != "call_expression" or call_name(raw, node) != "t":
            continue
        suffix = next((child for child in node.children if child.type == "call_suffix"), None)
        if suffix is None:
            continue
        arguments = next((child for child in suffix.children if child.type == "value_arguments"), None)
        if arguments is None:
            continue
        values = [child for child in arguments.children if child.type == "value_argument"]
        if not values:
            error(f"{rel}:{node.start_point[0] + 1}", "t(...) needs a source-text key")
            continue
        literal = next((child for child in values[0].children if child.type == "line_string_literal"), None)
        if literal is None:
            error(f"{rel}:{node.start_point[0] + 1}", "t(...) key must be a plain string literal")
            continue
        check_argument_count(f"{rel}:{node.start_point[0] + 1}", raw, values, literal)
    return keys


def check_argument_count(where: str, raw: bytes, values: list, literal) -> None:
    """A key with N `%@` must be called with N extra arguments, or String(format:) misreads them."""
    key = literal_value(raw, literal)
    if key in ("x", ""):
        return  # multi-line literal masked away by mask_multiline
    placeholders = key.count("%@")
    passed = 0
    for value in values[1:]:
        # Labelled arguments (`language: .chinese`) are not format arguments.
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*\s*:", node_text(raw, value)):
            continue
        passed += 1
    if placeholders != passed:
        error(
            where,
            f"t(...) key `{key}` has {placeholders} `%@` placeholder(s) but the call passes {passed} argument(s)",
        )


def check_placeholders(where: str, key: str, value: str) -> None:
    for match in STRAY_PERCENT.finditer(key):
        error(f"{where}: key `{key}`", f"unsupported format specifier `{match.group(0)}` (use %@ or %%)")
    key_tokens = PLACEHOLDER.findall(key)
    value_tokens = PLACEHOLDER.findall(value)
    if key_tokens != value_tokens:
        error(
            f"{where}: `{key}`",
            f"placeholders differ: key {key_tokens} vs English {value_tokens}",
        )


def check_tables(root: str) -> tuple[dict[str, tuple[str, str]], set[str]]:
    """Return key -> (English, table file) and the set of table file paths."""
    tables: dict[str, tuple[str, str]] = {}
    table_files: set[str] = set()
    for path in sorted(glob.glob(os.path.join(root, "Shared", "L10n*.swift"))):
        rel = relative(root, path)
        table_files.add(rel)
        source = read(path)
        for match in TABLE_ENTRY.finditer(source):
            key = unescape_swift(match.group(1))
            value = unescape_swift(match.group(2))
            where = f"{rel}:{source[: match.start()].count(chr(10)) + 1}"
            if key in tables:
                error(where, f"duplicate key `{key}` (also in {tables[key][1]})")
                continue
            if not value.strip():
                error(where, f"empty English value for `{key}`")
                continue
            if IDEOGRAPH.search(value):
                error(where, f"English value for `{key}` still contains Chinese: {value!r}")
            check_placeholders(rel, key, value)
            tables[key] = (value, rel)
    return tables, table_files


def check_imports(root: str, path: str, source: str) -> None:
    """A view that renders `t(...)` needs an observer so a language flip redraws it."""
    rel = relative(root, path)
    if rel in CJK_EXEMPT or os.path.basename(rel).startswith("L10n"):
        return
    if re.search(r"\bt\(", source) and ": View" in source and "LanguageStore.shared" not in source:
        warn(rel, "renders t(...) but has no `LanguageStore.shared` observer")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="repository root (default: current directory)")
    args = parser.parse_args()
    root = os.path.abspath(args.root)

    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass

    used: dict[str, tuple[str, int]] = {}
    for path in swift_files(root):
        source = read(path)
        masked = mask_multiline(source)
        rel = relative(root, path)
        check_syntax(root, path, masked)
        for key, line in sorted(check_literals(root, path, masked)):
            used.setdefault(key, (rel, line))
        check_imports(root, path, source)

    tables, _table_files = check_tables(root)

    for key, (rel, line) in sorted(used.items()):
        if key not in tables:
            error(f"{rel}:{line}", f"no English translation for `{key}`")

    for key in sorted(set(tables) - set(used)):
        warn(tables[key][1], f"unused translation key `{key}`")

    for line in errors:
        print(f"ERROR  {line}")
    for line in warnings:
        print(f"WARN   {line}")
    print(
        f"\nchecked {len(swift_files(root))} Swift files, {len(used)} used keys, "
        f"{len(tables)} translations -> {len(errors)} error(s), {len(warnings)} warning(s)"
    )
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
