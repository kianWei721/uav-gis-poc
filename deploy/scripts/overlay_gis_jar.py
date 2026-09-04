#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""以生产 Jar 为基线，仅追加 GIS class 与 Mapper XML。"""

import shutil
import sys
import zipfile


GIS_PREFIXES = (
    "BOOT-INF/classes/me/zhengjie/modules/smart/gis/",
    "BOOT-INF/classes/mapper/gis/",
)


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("overlay_gis_jar.py OLD_JAR GIS_JAR OUTPUT_JAR\n")
        return 2

    old_jar, gis_jar, output_jar = sys.argv[1:]
    shutil.copy2(old_jar, output_jar)
    count = 0
    with zipfile.ZipFile(gis_jar, "r") as source:
        with zipfile.ZipFile(output_jar, "a") as target:
            for info in source.infolist():
                if info.filename.endswith("/"):
                    continue
                if not info.filename.startswith(GIS_PREFIXES):
                    continue
                target.writestr(info, source.read(info.filename))
                count += 1
    if count < 1:
        sys.stderr.write("GIS staging Jar 中没有可叠加文件\n")
        return 3
    print("overlay_files={0}".format(count))
    return 0


if __name__ == "__main__":
    sys.exit(main())
