#!/usr/bin/env python3
"""Prüft die Struktur des Repos, ohne WoW und ohne Lua:

  * jede TOC hat Interface, Title und eine Version im Format x.y.z
  * jede in einer TOC oder XML genannte Datei existiert (Groß-/Kleinschreibung zählt, wie unter Linux)
  * jede XML-Datei ist wohlgeformt
  * mit --tag vX.Y.Z: alle TOC-Versionen und der CHANGELOG passen zum Tag
  * mit --tag vX.Y.Z-beta.N (Vorabversion): die TOC-Version muss X.Y.Z sein, im CHANGELOG reicht
    "## [Unreleased]" statt eines Abschnitts für X.Y.Z
  * mit --version: gibt die gemeinsame TOC-Version aus (Fehler, wenn die TOCs abweichen)

Aufruf aus dem Hauptordner des Repos:  python3 tools/check.py [--tag v0.1.0 | --version]
"""
import argparse
import os
import re
import sys
from xml.dom import minidom

SKIP_DIRS = {".git", ".github", "Libs", "tests", "tools"}
errors = []


def error(message):
    errors.append(message)
    print("FEHLER:", message)


def walk(root):
    for folder, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            yield os.path.join(folder, name)


def exists(path):
    """Existenz mit exakter Schreibweise (der Client ist unter Windows egal, Linux-Packager nicht)."""
    folder, name = os.path.split(os.path.normpath(path))
    return os.path.isdir(folder or ".") and name in os.listdir(folder or ".")


def check_toc(path):
    fields = {}
    files = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            match = re.match(r"^##\s*([^:]+):\s*(.*)$", line)
            if match:
                fields[match.group(1).strip()] = match.group(2).strip()
            elif line and not line.startswith("#"):
                files.append(line)

    for field in ("Interface", "Title", "Version"):
        if not fields.get(field):
            error(f"{path}: Feld '## {field}' fehlt")
    version = fields.get("Version", "")
    if version and not re.fullmatch(r"\d+\.\d+\.\d+", version):
        error(f"{path}: Version '{version}' ist nicht im Format x.y.z")

    base = os.path.dirname(path)
    for name in files:
        if not exists(os.path.join(base, name.replace("\\", "/"))):
            error(f"{path}: Datei '{name}' fehlt")
    return version


def check_xml(path):
    try:
        document = minidom.parse(path)
    except Exception as exc:  # noqa: BLE001 - jede Parser-Meldung ist ein Fehler
        error(f"{path}: kein gültiges XML ({exc})")
        return

    base = os.path.dirname(path)
    for tag in ("Script", "Include"):
        for node in document.getElementsByTagName(tag):
            name = node.getAttribute("file")
            if name and not exists(os.path.join(base, name.replace("\\", "/"))):
                error(f"{path}: Datei '{name}' fehlt")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", help="Release-Tag, z. B. v0.1.0")
    parser.add_argument("--version", action="store_true", help="gemeinsame TOC-Version ausgeben")
    args = parser.parse_args()

    versions = {}
    for path in walk("."):
        if path.endswith(".toc"):
            versions[path] = check_toc(path)
        elif path.endswith(".xml"):
            check_xml(path)

    if not versions:
        error("keine TOC-Datei gefunden")

    if args.version:
        found = set(versions.values())
        if errors or len(found) != 1:
            if len(found) > 1:
                error("die TOC-Dateien haben unterschiedliche Versionen: " + ", ".join(sorted(found)))
            sys.exit(1)
        print(found.pop())
        return

    if args.tag:
        wanted = args.tag.lstrip("v")
        base, _, prerelease = wanted.partition("-")
        for path, version in versions.items():
            if version != base:
                error(f"{path}: Version {version} passt nicht zum Tag {args.tag}")
        try:
            with open("CHANGELOG.md", encoding="utf-8") as handle:
                changelog = handle.read()
            if not re.search(r"^##\s*\[?" + re.escape(base) + r"\]?", changelog, re.M):
                if not (prerelease and re.search(r"^##\s*\[?Unreleased\]?", changelog, re.M | re.I)):
                    error(f"CHANGELOG.md hat keinen Abschnitt für {base}")
        except OSError:
            error("CHANGELOG.md fehlt")

    if errors:
        print(f"{len(errors)} Fehler")
        sys.exit(1)
    print(f"OK: {len(versions)} TOC-Datei(en) geprüft")


if __name__ == "__main__":
    main()
