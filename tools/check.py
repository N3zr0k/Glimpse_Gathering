#!/usr/bin/env python3
"""Prüft die Struktur des Repos, ohne WoW und ohne Lua:

  * jede TOC hat Interface, Title und eine Version im Format x.y.z
  * jede in einer TOC oder XML genannte Datei existiert (Groß-/Kleinschreibung zählt, wie unter Linux)
  * jede XML-Datei ist wohlgeformt
  * mit --tag vX.Y.Z: alle TOC-Versionen und der CHANGELOG passen zum Tag
  * mit --tag vX.Y.Z-beta.N (Beta): die TOC-Version muss X.Y.Z sein, im CHANGELOG muss ein Abschnitt
    "## [X.Y.Z]" stehen (ein richtiges Release, nur als Vorabversion veröffentlicht)
  * mit --tag vX.Y.Z-alpha.N (Alpha): wie Beta, es reicht aber auch "## [Unreleased]"
  * mit --version: gibt die gemeinsame TOC-Version aus (Fehler, wenn die TOCs abweichen)
  * mit --current-tag: gibt das vorhandene Tag der höchsten Stufe zur TOC-Version aus (nichts, wenn es keins gibt)
  * mit --next-tag: gibt das Tag aus, das zur TOC-Version und zum CHANGELOG gehört und noch nicht
    existiert (nichts, wenn es keins anzulegen gibt). Die Stufe steht im CHANGELOG:
      "## [Unreleased]" allein                 -> Alpha  (vX.Y.Z-alpha.1)
      "## [X.Y.Z] - Datum (beta)"              -> Beta   (vX.Y.Z-beta.1), richtiges Release als Vorabversion
      "## [X.Y.Z] - Datum (beta.2)"            -> Beta   (vX.Y.Z-beta.2), jede weitere Beta mit ihrer Nummer
      "## [X.Y.Z] - Datum"                     -> final  (vX.Y.Z)
    Es entsteht kein Tag, wenn es für die Version schon eines höherer Stufe gibt (Alpha < Beta < final)
    oder eines derselben Stufe mit gleicher oder höherer Nummer.

Aufruf aus dem Hauptordner des Repos:  python3 tools/check.py [--tag v0.1.0 | --version | --next-tag | --current-tag]
"""
import argparse
import os
import re
import subprocess
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


STAGES = ("alpha", "beta", "final")


def read_changelog():
    try:
        with open("CHANGELOG.md", encoding="utf-8") as handle:
            return handle.read()
    except OSError:
        error("CHANGELOG.md fehlt")
        return ""


def stage_of(version, changelog):
    """Stufe und Nummer der Version laut CHANGELOG: ("alpha", 1), ("beta", N) oder ("final", 0). Final auch,
    wenn nichts passt: check.py --tag meldet dann den fehlenden Abschnitt."""
    heading = re.search(r"^##\s*\[?" + re.escape(version) + r"\]?(.*)$", changelog, re.M)
    if heading:
        beta = re.search(r"\bbeta(?:[. ]?(\d+))?\b", heading.group(1), re.I)
        if beta:
            return "beta", int(beta.group(1) or 1)
        return "final", 0
    if re.search(r"^##\s*\[?Unreleased\]?", changelog, re.M | re.I):
        return "alpha", 1
    return "final", 0


def existing_tags(version):
    """Die Tags zur Version als Liste von (Stufe, Nummer, Tag)."""
    out = subprocess.run(["git", "tag", "-l", f"v{version}", f"v{version}-*"],
                         capture_output=True, text=True, check=False).stdout.split()
    found = []
    for tag in out:
        if tag == f"v{version}":
            found.append(("final", 0, tag))
        else:
            match = re.fullmatch(re.escape(f"v{version}") + r"-(alpha|beta)\.(\d+)", tag)
            if match:
                found.append((match.group(1), int(match.group(2)), tag))
    return found


def current_tag(version):
    """Das vorhandene Tag der höchsten Stufe (bei gleicher Stufe die höchste Nummer), sonst ""."""
    found = existing_tags(version)
    if not found:
        return ""
    return max(found, key=lambda item: (STAGES.index(item[0]), item[1]))[2]


def next_tag(version, changelog):
    """Das Tag, das jetzt angelegt werden soll, oder "" wenn keins fällig ist."""
    stage, number = stage_of(version, changelog)
    for other, other_number, _ in existing_tags(version):
        if STAGES.index(other) > STAGES.index(stage):
            return ""
        if other == stage and other_number >= number:
            return ""
    return f"v{version}" if stage == "final" else f"v{version}-{stage}.{number}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", help="Release-Tag, z. B. v0.1.0")
    parser.add_argument("--version", action="store_true", help="gemeinsame TOC-Version ausgeben")
    parser.add_argument("--next-tag", action="store_true", help="das jetzt fällige Tag ausgeben (leer: keins)")
    parser.add_argument("--current-tag", action="store_true", help="das vorhandene Tag der höchsten Stufe ausgeben")
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

    if args.current_tag:
        found = set(versions.values())
        if errors or len(found) != 1:
            sys.exit(1)
        print(current_tag(found.pop()))
        return

    if args.next_tag:
        found = set(versions.values())
        if errors or len(found) != 1:
            if len(found) > 1:
                error("die TOC-Dateien haben unterschiedliche Versionen: " + ", ".join(sorted(found)))
            sys.exit(1)
        changelog = read_changelog()
        if errors:
            sys.exit(1)
        print(next_tag(found.pop(), changelog))
        return

    if args.tag:
        wanted = args.tag.lstrip("v")
        base, _, prerelease = wanted.partition("-")
        kind = None
        if prerelease:
            match = re.fullmatch(r"(alpha|beta)\.\d+", prerelease)
            if match:
                kind = match.group(1)
            else:
                error(f"Tag {args.tag}: Vorabversion muss alpha.N oder beta.N heißen")
        for path, version in versions.items():
            if version != base:
                error(f"{path}: Version {version} passt nicht zum Tag {args.tag}")
        changelog = read_changelog()
        if changelog and not re.search(r"^##\s*\[?" + re.escape(base) + r"\]?", changelog, re.M):
            if not (kind == "alpha" and re.search(r"^##\s*\[?Unreleased\]?", changelog, re.M | re.I)):
                error(f"CHANGELOG.md hat keinen Abschnitt für {base}")

    if errors:
        print(f"{len(errors)} Fehler")
        sys.exit(1)
    print(f"OK: {len(versions)} TOC-Datei(en) geprüft")


if __name__ == "__main__":
    main()
