"""Merge Localizable.xcstrings key by key.

Git merges text, and this file is one sorted JSON object, so two commits that
only add keys near each other conflict although nothing actually clashes. Run
this as a merge driver, registered once per clone:

    git config merge.xcstrings.driver 'python3 helpers/merge-xcstrings.py %O %A %B'
"""

import json
import sys


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def dump(catalog):
    # The format xcstringstool writes, so its next sync does not rewrite the file.
    return json.dumps(
        catalog, indent=2, sort_keys=True, ensure_ascii=False, separators=(",", " : ")
    ) + "\n"


def merge_strings(base, ours, theirs):
    # Anything only they touched, including keys they deleted, is already right.
    merged = dict(theirs)
    clashes = []
    for key, our in ours.items():
        if key not in base:
            merged[key] = our
        elif our != base[key]:
            if key not in theirs or theirs[key] != base[key]:
                # Edited on both sides, or edited there and dropped here.
                clashes.append(key)
            else:
                merged[key] = our
    for key, their in theirs.items():
        if key in base and key not in ours:
            if their != base[key]:
                clashes.append(key)
            else:
                merged.pop(key)
    return merged, sorted(set(clashes))


def merge(base, ours, theirs):
    strings, clashes = merge_strings(
        base.get("strings", {}), ours.get("strings", {}), theirs.get("strings", {})
    )
    if clashes:
        return None, clashes
    merged = dict(theirs)
    for field in set(base) | set(ours):
        if field != "strings" and ours.get(field) != base.get(field):
            merged[field] = ours.get(field)
    merged["strings"] = strings
    return merged, []


def main(argv):
    # %O is the common ancestor, %A the result and the file to write, %B the other side.
    base, result, theirs = (load(path) for path in argv[1:4])
    merged, clashes = merge(base, result, theirs)
    if clashes:
        for key in clashes:
            print(f"merge-xcstrings: {key!r} changed on both sides", file=sys.stderr)
        return 1
    with open(argv[2], "w", encoding="utf-8") as handle:
        handle.write(dump(merged))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
