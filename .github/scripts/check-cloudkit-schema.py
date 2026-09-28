#!/usr/bin/env python3
"""Fail if the Production CloudKit schema lacks a field the app writes.

Shared by both distribution workflows. Takes the committed schema
(`cloudkit/schema.ckdb`) and a fresh `cktool export-schema` of Production,
and checks the committed file is a subset of Production: every record type
and every `CD_` field in it must exist in Production with the same type.

Extra fields in Production are fine. Deployed fields can never be removed,
so Production keeps fields the models retired long ago.

Only `CD_` fields are compared. They are the ones SwiftData's CloudKit
mirroring writes; the `___` system fields and the `Users` type are
CloudKit's own. Indexes (QUERYABLE and so on) are not compared either: a
missing index does not reject uploads the way a missing field does.

Exit status 0 when Production has everything, 1 when it does not, and 2
when either file does not parse into anything, so a format change in
cktool's output fails loudly instead of passing an empty comparison.
"""

import re
import sys

RECORD = re.compile(r'^\s*RECORD TYPE\s+"?(\w+)"?\s*\(')
# A field line: name, then type (which may be LIST<...>), then optional
# index keywords, then a trailing comma unless it is the last line.
FIELD = re.compile(r'^\s*"?(\w+)"?\s+([A-Z0-9_]+(?:<[A-Z0-9_]+>)?)[\s,]')


def parse(path):
    """Map each record type to {field name: type} for its CD_ fields."""
    types, current = {}, None
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if match := RECORD.match(line):
                current = types.setdefault(match.group(1), {})
            elif line.strip().startswith(")"):
                current = None
            elif current is not None and (match := FIELD.match(line + "\n")):
                name, field_type = match.groups()
                if name.startswith("CD_"):
                    current[name] = field_type
    return types


def main(expected_path, production_path):
    expected, production = parse(expected_path), parse(production_path)
    expected_count = sum(map(len, expected.values()))
    if expected_count == 0:
        print(f"::error title=CloudKit schema check::No CD_ fields found in {expected_path}.")
        return 2
    if not production:
        print("::error title=CloudKit schema check::No record types found in the Production export.")
        return 2

    problems = []
    for record_type, fields in sorted(expected.items()):
        if record_type not in production:
            problems.append(f"Record type {record_type} is missing from Production.")
            continue
        for name, field_type in sorted(fields.items()):
            actual = production[record_type].get(name)
            if actual is None:
                problems.append(f"{record_type}.{name} ({field_type}) is missing from Production.")
            elif actual != field_type:
                problems.append(
                    f"{record_type}.{name} is {actual} in Production but {field_type} in {expected_path}."
                )

    for problem in problems:
        print(f"::error title=CloudKit Production schema::{problem}")
    if problems:
        print(
            "Production is missing part of the committed schema, so this build's uploads would be "
            "rejected. In CloudKit Console, Deploy Schema Changes (Development -> Production), "
            "then re-run the failed jobs."
        )
        return 1

    print(f"Production has all {expected_count} expected fields across {len(expected)} record types.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} <committed schema.ckdb> <production export.ckdb>")
    sys.exit(main(sys.argv[1], sys.argv[2]))
