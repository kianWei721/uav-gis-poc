#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""比较生产 Jar 与 GIS staging Jar，拒绝夹带非 GIS 业务类变更。"""

import hashlib
import sys
import zipfile


EXPECTED_PREFIXES = (
    "BOOT-INF/classes/me/zhengjie/modules/smart/gis/",
    "BOOT-INF/classes/mapper/gis/",
)
EXPECTED_FILES = {
    "BOOT-INF/classes/config/application.yml",
}


def expected(name):
    return name in EXPECTED_FILES or name.startswith(EXPECTED_PREFIXES)


def digest(archive, name):
    return hashlib.sha256(archive.read(name)).hexdigest()


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("compare_gis_deployment_jars.py OLD_JAR NEW_JAR\n")
        return 2

    with zipfile.ZipFile(sys.argv[1]) as old_jar, zipfile.ZipFile(sys.argv[2]) as new_jar:
        old_names = {name for name in old_jar.namelist() if not name.endswith("/")}
        new_names = {name for name in new_jar.namelist() if not name.endswith("/")}

        unexpected_added = sorted(name for name in new_names - old_names if not expected(name))
        unexpected_missing = sorted(name for name in old_names - new_names if not expected(name))
        unexpected_changed = []
        for name in sorted(old_names & new_names):
            if not expected(name) and digest(old_jar, name) != digest(new_jar, name):
                unexpected_changed.append(name)

        gis_added = sorted(name for name in new_names - old_names if expected(name))
        print("expected_gis_added={0}".format(len(gis_added)))
        print("unexpected_added={0}".format(len(unexpected_added)))
        print("unexpected_missing={0}".format(len(unexpected_missing)))
        print("unexpected_changed={0}".format(len(unexpected_changed)))
        for category, names in (
            ("UNEXPECTED_ADDED", unexpected_added),
            ("UNEXPECTED_MISSING", unexpected_missing),
            ("UNEXPECTED_CHANGED", unexpected_changed),
        ):
            for name in names:
                print("{0}:{1}".format(category, name))
        return 1 if unexpected_added or unexpected_missing or unexpected_changed else 0


if __name__ == "__main__":
    sys.exit(main())
