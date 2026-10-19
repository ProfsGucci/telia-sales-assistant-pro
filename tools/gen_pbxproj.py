#!/usr/bin/env python3
"""Generates TeliaSalesAssistantPro.xcodeproj/project.pbxproj + shared scheme.

Zero external dependencies. Deterministic output: object UUIDs are derived
from stable path/name strings so re-running produces byte-identical files.

Target layout
-------------
- TeliaCore               static library  (TeliaSalesAssistantPro/Core/**)
- TeliaSalesAssistantPro  app             (App/DesignSystem/Services/Features)
  links libTeliaCore.a + system Charts.framework, bundles Resources/
- TeliaCoreTests          unit test bundle (Tests/CoreTests/**), hosted in app

Run from repo root:  python3 tools/gen_pbxproj.py
"""

import hashlib
import re
import io
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_DIR = ROOT / "TeliaSalesAssistantPro"

PROJECT_NAME = "TeliaSalesAssistantPro"
DEPLOYMENT_TARGET = "16.0"
BUNDLE_ID = "se.sthlm.teliacoachpro"

CORE_SOURCES = sorted(str(p.relative_to(ROOT)) for p in (APP_DIR / "Core").rglob("*.swift"))
APP_SOURCES = sorted(
    str(p.relative_to(ROOT))
    for d in ("App", "DesignSystem", "Services", "Features")
    for p in (APP_DIR / d).rglob("*.swift")
)
TEST_SOURCES = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Tests" / "CoreTests").glob("*.swift"))
RESOURCES = [
    "TeliaSalesAssistantPro/Resources/Assets.xcassets",
    "TeliaSalesAssistantPro/Resources/SeedCatalog.json",
    "TeliaSalesAssistantPro/Resources/CampaignSeed.json",
    "TeliaSalesAssistantPro/Resources/LearningContent.json",
    "TeliaSalesAssistantPro/Resources/PlaybookContent.json",
]
INFOPLIST = "TeliaSalesAssistantPro/Info.plist"

FILETYPE = {
    ".swift": "sourcecode.swift",
    ".json": "text.json",
    ".plist": "text.plist.xml",
    ".xcassets": "folder.assetcatalog",
}


def uuid_for(seed: str) -> str:
    digest = hashlib.md5(f"tsap/{seed}".encode()).hexdigest()[:24].upper()
    return digest


class Obj:
    def __init__(self, uuid, isa, **fields):
        self.uuid = uuid
        self.isa = isa
        self.fields = fields

    def render(self, out):
        out.write(f"\t\t{self.uuid} /* {self.isa} */ = {{\n")
        out.write(f"\t\t\tisa = {self.isa};\n")
        for key, value in self.fields.items():
            out.write(f"\t\t\t{key} = {value};\n")
        out.write("\t\t};\n")


def q(path: str) -> str:
    return f'"{path}"'


def qlist(items) -> str:
    return "(" + ", ".join(items) + ")"


# ---------------------------------------------------------------- objects

objects: list[Obj] = []


def add(seed: str, isa: str, **fields) -> str:
    uuid = uuid_for(seed)
    objects.append(Obj(uuid, isa, **fields))
    return uuid


def build_file(path: str, target: str, file_ref: str, settings: str | None = None) -> str:
    fields = {"fileRef": file_ref}
    if settings:
        fields["settings"] = settings
    return add(f"buildfile:{target}:{path}", "PBXBuildFile", **fields)


def file_ref(path: str, filetype: str | None = None, extra: dict | None = None) -> str:
    ft = filetype or FILETYPE[Path(path).suffix]
    name = Path(path).name
    fields = {"lastKnownFileType": q(ft), "path": q(name), "sourceTree": '"<group>"'}
    if extra:
        fields.update(extra)
    return add(f"fileref:{path}", "PBXFileReference", **fields)


# Product file references
APP_PRODUCT = add(
    "product:app", "PBXFileReference",
    explicitFileType=q("wrapper.application"), includeInIndex="0",
    path=q(f"{PROJECT_NAME}.app"), sourceTree=q("BUILT_PRODUCTS_DIR"),
)
CORE_PRODUCT = add(
    "product:core", "PBXFileReference",
    explicitFileType=q("archive.ar"), includeInIndex="0",
    path=q("libTeliaCore.a"), sourceTree=q("BUILT_PRODUCTS_DIR"),
)
TESTS_PRODUCT = add(
    "product:tests", "PBXFileReference",
    explicitFileType=q("wrapper.cfbundle"), includeInIndex="0",
    path=q("TeliaCoreTests.xctest"), sourceTree=q("BUILT_PRODUCTS_DIR"),
)

CHARTS_REF = add(
    "fileref:charts", "PBXFileReference",
    lastKnownFileType=q("wrapper.framework"), name=q("Charts"),
    path=q("System/Library/Frameworks/Charts.framework"), sourceTree=q("SDKROOT"),
)

# Source/resource file references
core_refs = {p: file_ref(p) for p in CORE_SOURCES}
app_refs = {p: file_ref(p) for p in APP_SOURCES}
test_refs = {p: file_ref(p) for p in TEST_SOURCES}
resource_refs = {p: file_ref(p) for p in RESOURCES}
infoplist_ref = file_ref(INFOPLIST)

# Build files
core_build_files = [build_file(p, "TeliaCore", core_refs[p]) for p in CORE_SOURCES]
app_build_files = [build_file(p, PROJECT_NAME, app_refs[p]) for p in APP_SOURCES]
test_build_files = [build_file(p, "TeliaCoreTests", test_refs[p]) for p in TEST_SOURCES]
resource_build_files = [build_file(p, PROJECT_NAME, resource_refs[p]) for p in RESOURCES]
core_lib_in_app = build_file("libTeliaCore.a", PROJECT_NAME, CORE_PRODUCT)
core_lib_in_tests = build_file("libTeliaCore.a", "TeliaCoreTests", CORE_PRODUCT)
charts_in_app = build_file("Charts.framework", PROJECT_NAME, CHARTS_REF)

# Build phases
core_sources_phase = add(
    "phase:sources:TeliaCore", "PBXSourcesBuildPhase",
    buildActionMask="2147483647", files=qlist([q(u) for u in core_build_files]),
    runOnlyForDeploymentPostprocessing="0",
)
app_sources_phase = add(
    "phase:sources:app", "PBXSourcesBuildPhase",
    buildActionMask="2147483647", files=qlist([q(u) for u in app_build_files]),
    runOnlyForDeploymentPostprocessing="0",
)
test_sources_phase = add(
    "phase:sources:tests", "PBXSourcesBuildPhase",
    buildActionMask="2147483647", files=qlist([q(u) for u in test_build_files]),
    runOnlyForDeploymentPostprocessing="0",
)
core_frameworks_phase = add(
    "phase:frameworks:TeliaCore", "PBXFrameworksBuildPhase",
    buildActionMask="2147483647", files=qlist([]),
    runOnlyForDeploymentPostprocessing="0",
)
app_frameworks_phase = add(
    "phase:frameworks:app", "PBXFrameworksBuildPhase",
    buildActionMask="2147483647", files=qlist([q(core_lib_in_app), q(charts_in_app)]),
    runOnlyForDeploymentPostprocessing="0",
)
test_frameworks_phase = add(
    "phase:frameworks:tests", "PBXFrameworksBuildPhase",
    buildActionMask="2147483647", files=qlist([q(core_lib_in_tests)]),
    runOnlyForDeploymentPostprocessing="0",
)
app_resources_phase = add(
    "phase:resources:app", "PBXResourcesBuildPhase",
    buildActionMask="2147483647", files=qlist([q(u) for u in resource_build_files]),
    runOnlyForDeploymentPostprocessing="0",
)

# Groups (mirrors the on-disk tree)
def group(name: str, children: list[str], path: str | None = None, is_main: bool = False):
    fields = {"children": qlist([q(c) for c in children])}
    if not is_main:
        fields["path"] = q(path or name)
    fields["sourceTree"] = '"<group>"'
    return add(f"group:{name}:{path or ''}", "PBXGroup", **fields)


def subtree(dirs_root: Path, relative: str):
    """Recursively build groups for a directory of sources."""
    children = []
    root = dirs_root / relative
    for entry in sorted(root.iterdir()):
        rel = str(entry.relative_to(ROOT))
        if entry.is_dir():
            sub_refs = [str(p.relative_to(ROOT)) for p in entry.rglob("*.swift")]
            children.append(subtree(dirs_root, str(entry.relative_to(dirs_root))))
            del sub_refs
        else:
            if str(entry.relative_to(ROOT)) in core_refs:
                children.append(core_refs[rel])
            elif str(entry.relative_to(ROOT)) in app_refs:
                children.append(app_refs[rel])
    # Group paths are relative to the PARENT group — use the basename only,
    # otherwise the parent's path component gets prepended twice.
    return group(relative, children, path=Path(relative).name)


core_group = subtree(APP_DIR, "Core")
app_group = group("App", [app_refs[p] for p in APP_SOURCES if p.startswith("TeliaSalesAssistantPro/App/")], path="App")
design_group = group("DesignSystem", [app_refs[p] for p in APP_SOURCES if "/DesignSystem/" in p], path="DesignSystem")
services_group = group("Services", [app_refs[p] for p in APP_SOURCES if "/Services/" in p], path="Services")

feature_children = []
features_root = APP_DIR / "Features"
for entry in sorted(features_root.iterdir()):
    if entry.is_dir():
        files = [app_refs[str(p.relative_to(ROOT))] for p in sorted(entry.glob("*.swift"))]
        feature_children.append(group(f"Features/{entry.name}", files, path=entry.name))
features_group = group("Features", feature_children, path="Features")

# Info.plist is NOT a bundled resource — it lives at the app source root and
# is referenced by INFOPLIST_FILE. Keep it out of the Resources group.
resources_group = group(
    "Resources",
    [resource_refs[p] for p in RESOURCES],
    path="Resources",
)
tests_group = group("CoreTests", [test_refs[p] for p in TEST_SOURCES], path="CoreTests")
tests_root_group = group("Tests", [tests_group], path="Tests")
frameworks_group = group("Frameworks", [CHARTS_REF], path=None)
products_group = group("Products", [APP_PRODUCT, CORE_PRODUCT, TESTS_PRODUCT], path="Products")
main_group_children = [  # first child is the app source root
    group("TeliaSalesAssistantPro",
          [app_group, core_group, design_group, features_group, services_group, resources_group, infoplist_ref],
          path="TeliaSalesAssistantPro"),
    frameworks_group, tests_root_group, products_group,
]
main_group = group("main", main_group_children, is_main=True)

# Project object + targets
project_uuid = uuid_for("project")
CORE_TARGET = add("target:TeliaCore", "PBXNativeTarget")  # placeholder replaced below


def native_target(seed, name, product_ref, product_type, phases, dependencies, config_list):
    return add(seed, "PBXNativeTarget",
               buildConfigurationList=config_list,
               buildPhases=qlist([q(p) for p in phases]),
               buildRules=qlist([]),
               dependencies=qlist([q(d) for d in dependencies]),
               name=q(name),
               productName=q(name),
               productReference=q(product_ref),
               productType=q(product_type))


def container_proxy(target_uuid, name):
    return add(f"proxy:{name}", "PBXContainerItemProxy",
               containerPortal=q(project_uuid),
               proxyType="1",
               remoteGlobalIDString=q(target_uuid),
               remoteInfo=q(name))


def target_dependency(target_uuid, name):
    proxy = container_proxy(target_uuid, name)
    return add(f"dependency:{name}", "PBXTargetDependency",
               target=q(target_uuid), targetProxy=q(proxy))


def build_settings(base: dict, extra: dict) -> str:
    merged = {**base, **extra}
    return "{\n" + "".join(
        f"\t\t\t\t\t\t{k} = {v};\n" for k, v in merged.items()
    ) + "\t\t\t\t\t}"


BASE_SETTINGS = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "DEAD_CODE_STRIPPING": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "SDKROOT": q("iphoneos"),
    "SWIFT_VERSION": "5.0",
}
DEBUG_SETTINGS = {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "\"$(inherited) DEBUG\"",
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}
RELEASE_SETTINGS = {
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
    "VALIDATE_PRODUCT": "YES",
}


def config_list(seed, name, debug_uuid, release_uuid):
    return add(f"configlist:{seed}", "XCConfigurationList",
               buildConfigurations=qlist([q(debug_uuid), q(release_uuid)]),
               defaultConfigurationIsVisible="0",
               defaultConfigurationName=q("Release"))


def configs(seed, debug_extra: dict, release_extra: dict, base: dict | None = None):
    base = base or {}
    dbg = add(f"config:{seed}:debug", "XCBuildConfiguration",
              buildSettings=build_settings({**BASE_SETTINGS, **DEBUG_SETTINGS}, {**base, **debug_extra}),
              name=q("Debug"))
    rel = add(f"config:{seed}:release", "XCBuildConfiguration",
              buildSettings=build_settings({**BASE_SETTINGS, **RELEASE_SETTINGS}, {**base, **release_extra}),
              name=q("Release"))
    return dbg, rel


# --- configurations
proj_dbg, proj_rel = configs("project", {}, {
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
})
proj_config_list = config_list("project", PROJECT_NAME, proj_dbg, proj_rel)

core_dbg, core_rel = configs("TeliaCore", {"ENABLE_TESTABILITY": "YES"}, {}, {
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.core",
    "SKIP_INSTALL": "YES",
})
core_config_list = config_list("TeliaCore", "TeliaCore", core_dbg, core_rel)

APP_BASE = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": q("AppIcon"),
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": q("AccentColor"),
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "6",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": q(INFOPLIST),
    "LD_RUNPATH_SEARCH_PATHS": qlist(['"$(inherited)"', '"@executable_path/Frameworks"']),
    "MARKETING_VERSION": "1.5",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": q("1,2"),
}
app_dbg, app_rel = configs("app", {}, {}, APP_BASE)
app_config_list = config_list("app", PROJECT_NAME, app_dbg, app_rel)

TESTS_BASE = {
    "BUNDLE_LOADER": '"$(TEST_HOST)"',
    "GENERATE_INFOPLIST_FILE": "YES",
    "LD_RUNPATH_SEARCH_PATHS": qlist(['"$(inherited)"', '"@executable_path/Frameworks"', '"@loader_path/Frameworks"']),
    "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.tests",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/TeliaSalesAssistantPro.app/TeliaSalesAssistantPro"',
}
tests_dbg, tests_rel = configs("tests", {}, {}, TESTS_BASE)
tests_config_list = config_list("tests", "TeliaCoreTests", tests_dbg, tests_rel)

# --- native targets (order matters for object file: core, app, tests)
# The placeholder registered earlier keeps UUID stability.
objects[:] = [o for o in objects if o.uuid != CORE_TARGET]

CORE_TARGET_UUID = uuid_for("target:TeliaCore")
APP_TARGET_UUID = uuid_for("target:TeliaSalesAssistantPro")
TESTS_TARGET_UUID = uuid_for("target:TeliaCoreTests")

core_dep_for_app = target_dependency(CORE_TARGET_UUID, "TeliaCore")
core_dep_for_tests = target_dependency(CORE_TARGET_UUID, "TeliaCore")
app_dep_for_tests = target_dependency(APP_TARGET_UUID, PROJECT_NAME)

core_target = native_target("target:TeliaCore", "TeliaCore", CORE_PRODUCT,
                            "com.apple.product-type.library.static",
                            [core_sources_phase, core_frameworks_phase], [], core_config_list)
app_target = native_target("target:TeliaSalesAssistantPro", PROJECT_NAME, APP_PRODUCT,
                           "com.apple.product-type.application",
                           [app_sources_phase, app_frameworks_phase, app_resources_phase],
                           [core_dep_for_app], app_config_list)
tests_target = native_target("target:TeliaCoreTests", "TeliaCoreTests", TESTS_PRODUCT,
                             "com.apple.product-type.bundle.unit-test",
                             [test_sources_phase, test_frameworks_phase],
                             [core_dep_for_tests, app_dep_for_tests], tests_config_list)

project = add("project", "PBXProject",
              attributes=(
                  "{\n"
                  "\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
                  f"\t\t\t\tLastSwiftUpdateCheck = 1600;\n"
                  f"\t\t\t\tLastUpgradeCheck = 1600;\n"
                  "\t\t\t\tTargetAttributes = {\n"
                  f"\t\t\t\t\t{CORE_TARGET_UUID} = {{CreatedOnToolsVersion = 16.0; }};\n"
                  f"\t\t\t\t\t{APP_TARGET_UUID} = {{CreatedOnToolsVersion = 16.0; }};\n"
                  f"\t\t\t\t\t{TESTS_TARGET_UUID} = {{CreatedOnToolsVersion = 16.0; TestTargetID = {APP_TARGET_UUID}; }};\n"
                  "\t\t\t\t};\n"
                  "\t\t\t}"
              ),
              buildConfigurationList=q(proj_config_list),
              compatibilityVersion=q("Xcode 14.0"),
              developmentRegion=q("sv"),
              hasScannedForEncodings="0",
              knownRegions=qlist([q("sv"), q("en"), q("Base")]),
              mainGroup=q(main_group),
              productRefGroup=q(products_group),
              projectDirPath=q(""),
              projectRoot=q(""),
              targets=qlist([q(CORE_TARGET_UUID), q(APP_TARGET_UUID), q(TESTS_TARGET_UUID)]))


# ---------------------------------------------------------------- render

def render(objects_list: list[Obj]) -> str:
    by_isa: dict[str, list[Obj]] = {}
    for o in objects_list:
        by_isa.setdefault(o.isa, []).append(o)

    out = io.StringIO()
    out.write("// !$*UTF8*$!\n")
    out.write("{\n")
    out.write("\tarchiveVersion = 1;\n")
    out.write("\tobjectVersion = 56;\n")
    out.write("\tclasses = {\n\t};\n")
    out.write("\tobjects = {\n")
    for isa in ("PBXBuildFile", "PBXContainerItemProxy", "PBXFileReference",
                "PBXFrameworksBuildPhase", "PBXGroup", "PBXNativeTarget",
                "PBXProject", "PBXResourcesBuildPhase", "PBXSourcesBuildPhase",
                "PBXTargetDependency", "XCBuildConfiguration", "XCConfigurationList"):
        out.write(f"/* Begin {isa} section */\n")
        for o in by_isa.get(isa, []):
            o.render(out)
        out.write(f"/* End {isa} section */\n")
    out.write("\t};\n")
    out.write(f"\trootObject = {project_uuid} /* Project object */;\n")
    out.write("}\n")
    return out.getvalue()


xcodeproj = ROOT / f"{PROJECT_NAME}.xcodeproj"
(xcodeproj / "project.pbxproj").write_text(render(objects))
# NOTE: no shared scheme is written on purpose. xcodebuild auto-creates schemes
# from the targets (including wiring hosted tests via TEST_HOST), which avoids
# Xcode's very particular scheme unarchiver crashing on hand-written XML.


def validate_group_paths(objects_list: list[Obj], main_group_uuid: str) -> None:
    """Resolve every group-relative PBXFileReference against SRCROOT and verify
    the file exists. Catches path-doubling bugs before Xcode ever sees them."""
    groups: dict[str, tuple[str | None, list[str]]] = {}
    filerefs: dict[str, str] = {}
    for o in objects_list:
        if o.isa == "PBXGroup":
            raw_path = o.fields.get("path")
            path = raw_path.strip('"') if raw_path else None
            children = re.findall(r"([0-9A-F]{24})", o.fields.get("children", "()"))
            groups[o.uuid] = (path, children)
        elif o.isa == "PBXFileReference":
            if o.fields.get("sourceTree", '"<group>"').strip('"') == "<group>":
                filerefs[o.uuid] = o.fields.get("path", '""').strip('"')

    parent: dict[str, str] = {}
    for guuid, (_, children) in groups.items():
        for child in children:
            parent[child] = guuid

    def full_path(uuid: str) -> str:
        parts: list[str] = []
        current = uuid
        while current in parent:
            group_path = groups[parent[current]][0]
            if group_path:
                parts.append(group_path)
            current = parent[current]
        return "/".join(reversed(parts))

    errors = []
    for uuid, filename in filerefs.items():
        relative_dir = full_path(uuid)
        absolute = ROOT / relative_dir / filename if relative_dir else ROOT / filename
        if not absolute.exists():
            errors.append(f"  {uuid} -> {relative_dir}/{filename} (missing)")
    if errors:
        raise SystemExit("group path validation FAILED:\n" + "\n".join(errors))
    print(f"Group path validation OK ({len(filerefs)} file references resolve on disk)")


validate_group_paths(objects, main_group)
print(f"Wrote {xcodeproj / 'project.pbxproj'}")
print(f"  Targets: TeliaCore ({len(CORE_SOURCES)} files), "
      f"{PROJECT_NAME} ({len(APP_SOURCES)} files, {len(RESOURCES)} resources), "
      f"TeliaCoreTests ({len(TEST_SOURCES)} files)")
