#!/usr/bin/env python3
"""
GMS Commander - Xcode projesi üreteci.

Bu betik, depodaki kaynak dosyaları tarayarak `GMS_Commander.xcodeproj`
paketini (project.pbxproj + paylaşılan şema) sıfırdan üretir. Böylece proje
dosyası elle düzenlenmez; kaynak ağacı değiştiğinde yeniden çalıştırılır.

Kullanım:
    python3 Scripts/generate_xcodeproj.py

Üretilen proje: macOS 14.0+, arm64, iki hedef (uygulama + birim testleri).
"""

from __future__ import annotations

import hashlib
import os
import shutil
import sys

PROJECT_NAME = "GMS_Commander"
APP_TARGET = "GMS_Commander"
APP_PRODUCT_NAME = "GMS Commander"
TEST_TARGET = "GMSCommanderTests"
BUNDLE_ID = "com.gms.commander"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = "GMS_Commander"
TEST_DIR = "Tests/GMSCommanderTests"

# Simge/varlık kataloğu ve yerelleştirme klasörleri özel işlenir.
ASSET_CATALOG = "Resources/Assets.xcassets"
STRINGS_FILE = "Resources/tr.lproj/Localizable.strings"
INFO_PLIST = "Resources/Info.plist"


def uid(*parts: str) -> str:
    """Kararlı (deterministik) 24 karakterlik nesne kimliği üretir."""
    digest = hashlib.md5("::".join(parts).encode("utf-8")).hexdigest()
    return digest[:24].upper()


def quote(value: str) -> str:
    """OpenStep plist için gerekli olan tırnaklama."""
    if value and all(c.isalnum() or c in "_./" for c in value) and not value[0].isdigit():
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".plist": "text.plist.xml",
    ".strings": "text.plist.strings",
    ".xcassets": "folder.assetcatalog",
    ".md": "net.daringfireball.markdown",
    ".sh": "text.script.sh",
    ".py": "text.script.python",
    ".swift-icon": "image.png",
    ".png": "image.png",
}


def file_type(path: str) -> str:
    if path.endswith(".xcassets"):
        return "folder.assetcatalog"
    return FILE_TYPES.get(os.path.splitext(path)[1], "text")


class Collected:
    """Hedeflere eklenecek dosyaların listesi."""

    def __init__(self) -> None:
        self.sources: list[str] = []
        self.resources: list[str] = []
        self.others: list[str] = []


def collect_app_files() -> Collected:
    collected = Collected()
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, APP_DIR)):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        # Varlık kataloğu tek bir klasör referansı olarak eklenir.
        if "Assets.xcassets" in dirnames:
            dirnames.remove("Assets.xcassets")
        if ".lproj" in "".join(dirnames) or any(d.endswith(".lproj") for d in dirnames):
            # .lproj klasörleri varyant grubu olarak ayrıca ele alınır.
            dirnames[:] = [d for d in dirnames if not d.endswith(".lproj")]

        for filename in sorted(filenames):
            if filename.startswith("."):
                continue
            absolute = os.path.join(dirpath, filename)
            rel = os.path.relpath(absolute, os.path.join(ROOT, APP_DIR))
            if filename.endswith(".swift"):
                collected.sources.append(rel)
            elif rel == INFO_PLIST:
                collected.others.append(rel)
            elif rel == ASSET_CATALOG:
                collected.resources.append(rel)
            elif rel == STRINGS_FILE:
                # Yerelleştirme, varyant grubu olarak ayrıca eklenir.
                collected.others.append(rel)
            elif os.path.splitext(filename)[1] in (".strings", ".plist"):
                collected.resources.append(rel)
            else:
                collected.others.append(rel)

    if os.path.isdir(os.path.join(ROOT, APP_DIR, ASSET_CATALOG)):
        collected.resources.append(ASSET_CATALOG)
    if os.path.isfile(os.path.join(ROOT, APP_DIR, STRINGS_FILE)) and STRINGS_FILE not in collected.others:
        collected.others.append(STRINGS_FILE)
    return collected


def collect_test_files() -> list[str]:
    test_root = os.path.join(ROOT, TEST_DIR)
    files: list[str] = []
    if not os.path.isdir(test_root):
        return files
    for dirpath, dirnames, filenames in os.walk(test_root):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for filename in sorted(filenames):
            if filename.endswith(".swift"):
                files.append(os.path.relpath(os.path.join(dirpath, filename), test_root))
    return files


class ProjectWriter:
    def __init__(self) -> None:
        self.objects: dict[str, str] = {}

    def add(self, object_id: str, body: str) -> str:
        self.objects[object_id] = body
        return object_id

    def render(self) -> str:
        lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {", ""]
        for object_id in sorted(self.objects):
            lines.append(self.objects[object_id])
        lines.append("\t};")
        lines.append("\trootObject = %s /* Project object */;" % uid("project"))
        lines.append("}")
        lines.append("")
        return "\n".join(lines)


def main() -> int:
    app = collect_app_files()
    tests = collect_test_files()

    writer = ProjectWriter()

    # ------------------------------------------------------------------ #
    # Dosya referansları ve derleme girdileri
    # ------------------------------------------------------------------ #
    app_file_refs: dict[str, str] = {}
    app_build_files: dict[str, str] = {}
    for rel in sorted(set(app.sources + app.resources + app.others)):
        ref = uid("fileref", rel)
        app_file_refs[rel] = ref
        writer.add(ref, "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = \"<group>\"; };"
                   % (ref, os.path.basename(rel), file_type(rel), quote(os.path.basename(rel))))

    for rel in sorted(app.sources):
        build_id = uid("build", rel)
        app_build_files[rel] = build_id
        writer.add(build_id, "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
                   % (build_id, os.path.basename(rel), app_file_refs[rel], os.path.basename(rel)))

    for rel in sorted(app.resources):
        build_id = uid("build", rel)
        app_build_files[rel] = build_id
        writer.add(build_id, "\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
                   % (build_id, os.path.basename(rel), app_file_refs[rel], os.path.basename(rel)))

    test_file_refs: dict[str, str] = {}
    test_build_files: dict[str, str] = {}
    for rel in sorted(tests):
        ref = uid("test-fileref", rel)
        build_id = uid("test-build", rel)
        test_file_refs[rel] = ref
        test_build_files[rel] = build_id
        writer.add(ref, "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = \"<group>\"; };"
                   % (ref, os.path.basename(rel), quote(rel)))
        writer.add(build_id, "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
                   % (build_id, os.path.basename(rel), ref, os.path.basename(rel)))

    # ------------------------------------------------------------------ #
    # Yerelleştirme varyant grubu
    # ------------------------------------------------------------------ #
    variant_id = uid("variant", STRINGS_FILE)
    strings_ref = app_file_refs[STRINGS_FILE]
    writer.add(strings_ref, "\t\t%s /* tr */ = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = tr; path = %s; sourceTree = \"<group>\"; };"
               % (strings_ref, quote("tr.lproj/Localizable.strings")))
    writer.add(variant_id, "\t\t%s /* Localizable.strings */ = {isa = PBXVariantGroup; children = (\n\t\t\t\t%s /* tr */,\n\t\t\t); name = Localizable.strings; sourceTree = \"<group>\"; };"
               % (variant_id, strings_ref))
    strings_build_id = uid("build", "Localizable.strings")
    writer.add(strings_build_id, "\t\t%s /* Localizable.strings in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Localizable.strings */; };"
               % (strings_build_id, variant_id))

    # ------------------------------------------------------------------ #
    # Grup ağacı
    # ------------------------------------------------------------------ #
    groups_group = uid("group", "main")

    def make_groups(prefix: str, root_name: str, files: list[str], tree_key: str) -> str:
        """Alt klasörler için iç içe PBXGroup nesneleri üretir."""
        root_id = uid("group", tree_key, prefix or ".")
        children: list[str] = []
        subdirs: dict[str, list[str]] = {}
        direct_files: list[str] = []

        for rel in files:
            if tree_key == "app" and os.path.join(prefix, rel).replace(os.sep, "/") == STRINGS_FILE:
                continue
            parts = rel.split(os.sep)
            if len(parts) == 1:
                direct_files.append(rel)
            else:
                subdirs.setdefault(parts[0], []).append(os.sep.join(parts[1:]))

        for rel in sorted(direct_files):
            ref = test_file_refs[rel] if tree_key == "tests" else app_file_refs[os.path.join(prefix, rel) if prefix else rel]
            children.append(ref)

        for sub in sorted(subdirs):
            sub_prefix = os.path.join(prefix, sub) if prefix else sub
            child_id = make_groups(sub_prefix, sub, subdirs[sub], tree_key)
            children.append(child_id)

        # Kaynak klasöründe yerelleştirme varyantı ve varlık kataloğu
        if tree_key == "app" and prefix == "Resources":
            children.append(variant_id)

        child_lines = "".join("\t\t\t\t%s,\n" % c for c in children)
        name_line = " name = %s;" % quote(root_name) if prefix else ""
        path_line = " path = %s;" % quote(root_name)
        writer.add(root_id, "\t\t%s /* %s */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\t\t\t);%s%s sourceTree = \"<group>\";\n\t\t};"
                   % (root_id, root_name, child_lines, path_line, name_line))
        return root_id

    # Uygulama grubu: GMS_Commander/ kökü
    app_all = sorted(set(app.sources + app.resources + app.others))
    app_group_id = make_groups("", APP_DIR, app_all, "app")

    tests_group_id = uid("group", "tests")
    test_children = "".join("\t\t\t\t%s,\n" % test_file_refs[rel] for rel in sorted(tests))
    writer.add(tests_group_id, "\t\t%s /* %s */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\t\t\t);\n\t\t\tpath = %s;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
               % (tests_group_id, TEST_TARGET, test_children, quote(TEST_DIR)))

    product_ref = uid("product", APP_PRODUCT_NAME)
    writer.add(product_ref, "\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = %s; sourceTree = BUILT_PRODUCTS_DIR; };"
               % (product_ref, APP_PRODUCT_NAME, quote(APP_PRODUCT_NAME + ".app")))

    test_product_ref = uid("product", TEST_TARGET)
    writer.add(test_product_ref, "\t\t%s /* %s.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = %s; sourceTree = BUILT_PRODUCTS_DIR; };"
               % (test_product_ref, TEST_TARGET, quote(TEST_TARGET + ".xctest")))

    products_group = uid("group", "Products")
    writer.add(products_group, "\t\t%s /* Products */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t%s /* %s.app */,\n\t\t\t\t%s /* %s.xctest */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
               % (products_group, product_ref, APP_PRODUCT_NAME, test_product_ref, TEST_TARGET))

    writer.add(groups_group, "\t\t%s = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t%s /* %s */,\n\t\t\t\t%s /* %s */,\n\t\t\t\t%s /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
               % (groups_group, app_group_id, APP_DIR, tests_group_id, TEST_TARGET, products_group))

    # ------------------------------------------------------------------ #
    # Derleme aşamaları
    # ------------------------------------------------------------------ #
    app_sources_phase = uid("phase", "app-sources")
    app_frameworks_phase = uid("phase", "app-frameworks")
    app_resources_phase = uid("phase", "app-resources")

    app_source_items = "".join("\t\t\t\t%s /* %s in Sources */,\n" % (app_build_files[rel], os.path.basename(rel)) for rel in sorted(app.sources))
    writer.add(app_sources_phase, "\t\t%s /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
               % (app_sources_phase, app_source_items))

    writer.add(app_frameworks_phase, "\t\t%s /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
               % app_frameworks_phase)

    resource_items = "".join("\t\t\t\t%s /* %s in Resources */,\n" % (app_build_files[rel], os.path.basename(rel)) for rel in sorted(app.resources))
    resource_items += "\t\t\t\t%s /* Localizable.strings in Resources */,\n" % strings_build_id
    writer.add(app_resources_phase, "\t\t%s /* Resources */ = {\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
               % (app_resources_phase, resource_items))

    test_sources_phase = uid("phase", "test-sources")
    test_frameworks_phase = uid("phase", "test-frameworks")
    test_resources_phase = uid("phase", "test-resources")
    test_source_items = "".join("\t\t\t\t%s /* %s in Sources */,\n" % (test_build_files[rel], os.path.basename(rel)) for rel in sorted(tests))
    writer.add(test_sources_phase, "\t\t%s /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
               % (test_sources_phase, test_source_items))
    writer.add(test_frameworks_phase, "\t\t%s /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
               % test_frameworks_phase)
    writer.add(test_resources_phase, "\t\t%s /* Resources */ = {\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
               % test_resources_phase)

    # ------------------------------------------------------------------ #
    # Hedefler
    # ------------------------------------------------------------------ #
    app_target_id = uid("target", APP_TARGET)
    test_target_id = uid("target", TEST_TARGET)

    app_config_list = uid("configlist", "app")
    test_config_list = uid("configlist", "tests")
    project_config_list = uid("configlist", "project")

    container_proxy = uid("proxy", TEST_TARGET)
    target_dependency = uid("dependency", TEST_TARGET)

    writer.add(container_proxy, "\t\t%s /* PBXContainerItemProxy */ = {\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = %s /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = %s;\n\t\t\tremoteInfo = %s;\n\t\t};"
               % (container_proxy, uid("project"), app_target_id, APP_TARGET))
    writer.add(target_dependency, "\t\t%s /* PBXTargetDependency */ = {\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = %s /* %s */;\n\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;\n\t\t};"
               % (target_dependency, app_target_id, APP_TARGET, container_proxy))

    writer.add(app_target_id, """\t\t%s /* %s */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%s" */;
\t\t\tbuildPhases = (
\t\t\t\t%s /* Sources */,
\t\t\t\t%s /* Frameworks */,
\t\t\t\t%s /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = %s;
\t\t\tproductName = %s;
\t\t\tproductReference = %s /* %s.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t};""" % (app_target_id, APP_TARGET, app_config_list, APP_TARGET,
                app_sources_phase, app_frameworks_phase, app_resources_phase,
                APP_TARGET, APP_TARGET, product_ref, APP_PRODUCT_NAME))

    writer.add(test_target_id, """\t\t%s /* %s */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%s" */;
\t\t\tbuildPhases = (
\t\t\t\t%s /* Sources */,
\t\t\t\t%s /* Frameworks */,
\t\t\t\t%s /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t%s /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = %s;
\t\t\tproductName = %s;
\t\t\tproductReference = %s /* %s.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t};""" % (test_target_id, TEST_TARGET, test_config_list, TEST_TARGET,
                test_sources_phase, test_frameworks_phase, test_resources_phase,
                target_dependency, TEST_TARGET, TEST_TARGET, test_product_ref, TEST_TARGET))

    # ------------------------------------------------------------------ #
    # Proje nesnesi
    # ------------------------------------------------------------------ #
    writer.add(uid("project"), """\t\t%s /* Project object */ = {
\t\t\tisa = PBXProject;
\t\t\tattributes = {
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {
\t\t\t\t\t%s = {
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t};
\t\t\t\t\t%s = {
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t\tTestTargetID = %s;
\t\t\t\t\t};
\t\t\t\t};
\t\t\t};
\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject "%s" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = tr;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ttr,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = %s;
\t\t\tproductRefGroup = %s /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t%s /* %s */,
\t\t\t\t%s /* %s */,
\t\t\t);
\t\t};""" % (uid("project"), app_target_id, test_target_id, app_target_id,
                project_config_list, PROJECT_NAME, groups_group, products_group,
                app_target_id, APP_TARGET, test_target_id, TEST_TARGET))

    # ------------------------------------------------------------------ #
    # Derleme yapılandırmaları
    # ------------------------------------------------------------------ #
    def settings_block(config_id: str, name: str, settings: dict[str, str], label: str) -> None:
        items = "".join("\t\t\t\t%s = %s;\n" % (k, quote(v)) for k, v in settings.items())
        writer.add(config_id, "\t\t%s /* %s */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\t\t\t};\n\t\t\tname = %s;\n\t\t};"
                   % (config_id, name, items, name))

    common_project = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "SDKROOT": "macosx",
        "SWIFT_VERSION": "5.0",
        "ARCHS": "arm64",
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "NO",
    }

    project_debug = dict(common_project)
    project_debug.update({
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    })

    project_release = dict(common_project)
    project_release.update({
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
        "VALIDATE_PRODUCT": "YES",
    })

    settings_block(uid("config", "project", "Debug"), "Debug", project_debug, PROJECT_NAME)
    settings_block(uid("config", "project", "Release"), "Release", project_release, PROJECT_NAME)

    app_common = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "COMBINE_HIDPI_IMAGES": "YES",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_HARDENED_RUNTIME": "YES",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "GMS_Commander/Resources/Info.plist",
        "INFOPLIST_KEY_NSHumanReadableCopyright": "Copyright © 2025 GMS. Tüm hakları saklıdır.",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
        "MARKETING_VERSION": "1.0.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_MODULE_NAME": APP_TARGET,
        "PRODUCT_NAME": APP_PRODUCT_NAME,
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "SWIFT_STRICT_CONCURRENCY": "minimal",
    }

    app_debug = dict(app_common)
    app_debug.update({"CODE_SIGN_IDENTITY": "-", "SWIFT_OPTIMIZATION_LEVEL": "-Onone"})
    app_release = dict(app_common)
    app_release.update({"CODE_SIGN_IDENTITY": "-", "SWIFT_OPTIMIZATION_LEVEL": "-Owholemodule"})

    settings_block(uid("config", "app", "Debug"), "Debug", app_debug, APP_TARGET)
    settings_block(uid("config", "app", "Release"), "Release", app_release, APP_TARGET)

    test_common = {
        "BUNDLE_LOADER": "$(TEST_HOST)",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_TESTING_SEARCH_PATHS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "MARKETING_VERSION": "1.0.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".tests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_STRICT_CONCURRENCY": "minimal",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/%s.app/Contents/MacOS/%s" % (APP_PRODUCT_NAME, APP_PRODUCT_NAME),
    }
    test_debug = dict(test_common)
    test_debug.update({"CODE_SIGN_IDENTITY": "-", "SWIFT_OPTIMIZATION_LEVEL": "-Onone"})
    test_release = dict(test_common)
    test_release.update({"CODE_SIGN_IDENTITY": "-", "SWIFT_OPTIMIZATION_LEVEL": "-Owholemodule"})

    settings_block(uid("config", "tests", "Debug"), "Debug", test_debug, TEST_TARGET)
    settings_block(uid("config", "tests", "Release"), "Release", test_release, TEST_TARGET)

    def list_block(list_id: str, label: str, debug_id: str, release_id: str) -> None:
        writer.add(list_id, "\t\t%s /* Build configuration list for %s */ = {\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};"
                   % (list_id, label, debug_id, release_id))

    list_block(project_config_list, 'PBXProject "%s"' % PROJECT_NAME,
               uid("config", "project", "Debug"), uid("config", "project", "Release"))
    list_block(app_config_list, 'PBXNativeTarget "%s"' % APP_TARGET,
               uid("config", "app", "Debug"), uid("config", "app", "Release"))
    list_block(test_config_list, 'PBXNativeTarget "%s"' % TEST_TARGET,
               uid("config", "tests", "Debug"), uid("config", "tests", "Release"))

    # ------------------------------------------------------------------ #
    # Yazma
    # ------------------------------------------------------------------ #
    project_dir = os.path.join(ROOT, PROJECT_NAME + ".xcodeproj")
    if os.path.isdir(project_dir):
        shutil.rmtree(project_dir)
    os.makedirs(project_dir)

    with open(os.path.join(project_dir, "project.pbxproj"), "w", encoding="utf-8") as handle:
        handle.write(writer.render())

    scheme_dir = os.path.join(project_dir, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir)
    with open(os.path.join(scheme_dir, APP_TARGET + ".xcscheme"), "w", encoding="utf-8") as handle:
        handle.write(SCHEME % {
            "project": PROJECT_NAME,
            "app_target": APP_TARGET,
            "test_target": TEST_TARGET,
            "app_target_id": app_target_id,
            "test_target_id": test_target_id,
            "product": APP_PRODUCT_NAME,
        })

    print("✓ %s.xcodeproj üretildi" % PROJECT_NAME)
    print("  Kaynak dosya: %d" % len(app.sources))
    print("  Kaynak (resource): %d" % len(app.resources))
    print("  Test dosyası: %d" % len(tests))
    return 0


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%(app_target_id)s"
               BuildableName = "%(product)s.app"
               BlueprintName = "%(app_target)s"
               ReferencedContainer = "container:%(project)s.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "NO" buildForProfiling = "NO" buildForArchiving = "NO" buildForAnalyzing = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%(test_target_id)s"
               BuildableName = "%(test_target)s.xctest"
               BlueprintName = "%(test_target)s"
               ReferencedContainer = "container:%(project)s.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%(test_target_id)s"
               BuildableName = "%(test_target)s.xctest"
               BlueprintName = "%(test_target)s"
               ReferencedContainer = "container:%(project)s.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%(app_target_id)s"
            BuildableName = "%(product)s.app"
            BlueprintName = "%(app_target)s"
            ReferencedContainer = "container:%(project)s.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%(app_target_id)s"
            BuildableName = "%(product)s.app"
            BlueprintName = "%(app_target)s"
            ReferencedContainer = "container:%(project)s.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


if __name__ == "__main__":
    sys.exit(main())
