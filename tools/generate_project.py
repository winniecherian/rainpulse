#!/usr/bin/env python3
"""
Generates RainPulse.xcodeproj (project.pbxproj + shared scheme) from the folder layout.
Re-run after adding or removing source files:   python3 tools/generate_project.py
Works on any machine with Python 3 — no Xcode needed.
"""
import hashlib
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = os.path.join(ROOT, "RainPulse.xcodeproj")
APP, WIDGET, UITESTS = "RainPulse", "RainPulseWidget", "RainPulseUITests"


def oid(*parts):
    return hashlib.md5("|".join(parts).encode()).hexdigest()[:24].upper()


def q(v):
    if isinstance(v, (list, tuple)):
        return "(" + "".join(f"\n\t\t\t\t{q(x)}," for x in v) + "\n\t\t\t)"
    s = str(v)
    if s and re.fullmatch(r"[A-Za-z0-9_./]+", s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def files_in(folder, exts):
    out = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, folder)):
        dirnames[:] = sorted(d for d in dirnames if not d.endswith((".xcassets", ".xcodeproj")))
        for f in sorted(filenames):
            if os.path.splitext(f)[1] in exts:
                out.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
    return out


FILETYPES = {
    ".swift": "sourcecode.swift", ".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements",
    ".xcassets": "folder.assetcatalog", ".xcprivacy": "text.xml", ".xcstrings": "text.json.xcstrings", ".xcconfig": "text.xcconfig",
    ".storekit": "text.json", ".md": "net.daringfireball.markdown", ".sh": "text.script.sh",
}

objects = {}   # id -> (isa, dict)


def add(id_, isa, **fields):
    objects[id_] = (isa, fields)
    return id_


# ---------- file references ----------
shared_swift = files_in("Shared", {".swift"})
app_swift = files_in(APP, {".swift"})
widget_swift = files_in(WIDGET, {".swift"})
uitest_swift = files_in(UITESTS, {".swift"})
other_files = [
    f"{APP}/Info.plist", f"{APP}/{APP}.entitlements", f"{APP}/PrivacyInfo.xcprivacy", f"{APP}/Assets.xcassets",
    f"{WIDGET}/Info.plist", f"{WIDGET}/{WIDGET}.entitlements", f"{WIDGET}/PrivacyInfo.xcprivacy",
    "Config/Base.xcconfig", "Config/Secrets.example.xcconfig", "Products.storekit", "README.md",
    "ci_scripts/ci_post_clone.sh", "Shared/Localizable.xcstrings",
]
all_files = shared_swift + app_swift + widget_swift + uitest_swift + [f for f in other_files if os.path.exists(os.path.join(ROOT, f))]

fileref = {}
for path in all_files:
    name = os.path.basename(path)
    ext = os.path.splitext(name)[1]
    fileref[path] = add(oid("ref", path), "PBXFileReference",
                        lastKnownFileType=FILETYPES.get(ext, "text"), path=name, sourceTree="<group>")

app_product = add(oid("product", APP), "PBXFileReference", explicitFileType="wrapper.application",
                  includeInIndex="0", path=f"{APP}.app", sourceTree="BUILT_PRODUCTS_DIR")
widget_product = add(oid("product", WIDGET), "PBXFileReference", explicitFileType="wrapper.app-extension",
                     includeInIndex="0", path=f"{WIDGET}.appex", sourceTree="BUILT_PRODUCTS_DIR")

# ---------- groups (mirror folders) ----------
groups = {}


def group_for(folder):
    if folder in groups:
        return groups[folder]
    gid = oid("group", folder)
    groups[folder] = gid
    add(gid, "PBXGroup", children=[], path=os.path.basename(folder), sourceTree="<group>")
    parent = os.path.dirname(folder)
    if parent:
        objects[group_for(parent)][1]["children"].append(gid)
    else:
        top_children.append(gid)
    return gid


top_children = []
root_files = []
for path in all_files:
    folder = os.path.dirname(path)
    if folder:
        objects[group_for(folder)][1]["children"].append(fileref[path])
    else:
        root_files.append(fileref[path])

uitest_product = add(oid("product", UITESTS), "PBXFileReference", explicitFileType="wrapper.cfbundle",
                     includeInIndex="0", path=f"{UITESTS}.xctest", sourceTree="BUILT_PRODUCTS_DIR")
products_group = add(oid("group", "Products"), "PBXGroup", children=[app_product, widget_product, uitest_product],
                     name="Products", sourceTree="<group>")
order = ["Shared", APP, WIDGET, UITESTS, "Config", "ci_scripts"]
top_children.sort(key=lambda g: next((i for i, n in enumerate(order) if groups.get(n) == g), 99))
main_group = add(oid("group", "main"), "PBXGroup", children=root_files + top_children + [products_group],
                 sourceTree="<group>")


# ---------- build phases ----------
def build_files(target, paths, phase):
    return [add(oid("bf", target, phase, p), "PBXBuildFile", fileRef=fileref[p]) for p in paths]


app_sources = add(oid("phase", APP, "sources"), "PBXSourcesBuildPhase", buildActionMask="2147483647",
                  files=build_files(APP, shared_swift + app_swift, "src"), runOnlyForDeploymentPostprocessing="0")
app_resources = add(oid("phase", APP, "res"), "PBXResourcesBuildPhase", buildActionMask="2147483647",
                    files=build_files(APP, [f"{APP}/Assets.xcassets", f"{APP}/PrivacyInfo.xcprivacy", "Shared/Localizable.xcstrings"], "res"),
                    runOnlyForDeploymentPostprocessing="0")
app_frameworks = add(oid("phase", APP, "fw"), "PBXFrameworksBuildPhase", buildActionMask="2147483647",
                     files=[], runOnlyForDeploymentPostprocessing="0")
embed_bf = add(oid("bf", APP, "embed", WIDGET), "PBXBuildFile", fileRef=widget_product,
               settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
app_embed = add(oid("phase", APP, "embed"), "PBXCopyFilesBuildPhase", buildActionMask="2147483647",
                dstPath="", dstSubfolderSpec="13", files=[embed_bf], name="Embed Foundation Extensions",
                runOnlyForDeploymentPostprocessing="0")

w_sources = add(oid("phase", WIDGET, "sources"), "PBXSourcesBuildPhase", buildActionMask="2147483647",
                files=build_files(WIDGET, shared_swift + widget_swift, "src"), runOnlyForDeploymentPostprocessing="0")
w_resources = add(oid("phase", WIDGET, "res"), "PBXResourcesBuildPhase", buildActionMask="2147483647",
                  files=build_files(WIDGET, [f"{WIDGET}/PrivacyInfo.xcprivacy", "Shared/Localizable.xcstrings"], "res"),
                  runOnlyForDeploymentPostprocessing="0")
w_frameworks = add(oid("phase", WIDGET, "fw"), "PBXFrameworksBuildPhase", buildActionMask="2147483647",
                   files=[], runOnlyForDeploymentPostprocessing="0")

t_sources = add(oid("phase", UITESTS, "sources"), "PBXSourcesBuildPhase", buildActionMask="2147483647",
                files=build_files(UITESTS, uitest_swift, "src"), runOnlyForDeploymentPostprocessing="0")
t_frameworks = add(oid("phase", UITESTS, "fw"), "PBXFrameworksBuildPhase", buildActionMask="2147483647",
                   files=[], runOnlyForDeploymentPostprocessing="0")
t_resources = add(oid("phase", UITESTS, "res"), "PBXResourcesBuildPhase", buildActionMask="2147483647",
                  files=[], runOnlyForDeploymentPostprocessing="0")

# ---------- build configurations ----------
base_xcconfig = fileref["Config/Base.xcconfig"]
project_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES", "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20", "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES", "CLANG_ENABLE_OBJC_WEAK": "YES", "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES", "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES", "SDKROOT": "iphoneos",
    "MTL_FAST_MATH": "YES", "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
}
project_debug = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0", "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE", "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
project_release = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO", "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES",
})

app_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": f"{APP}/{APP}.entitlements", "CODE_SIGN_STYLE": "Automatic", "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": f"{APP}/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_BASE)", "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}
widget_settings = {
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "CODE_SIGN_ENTITLEMENTS": f"{WIDGET}/{WIDGET}.entitlements", "CODE_SIGN_STYLE": "Automatic",
    "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": f"{WIDGET}/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_BASE).widget", "PRODUCT_NAME": "$(TARGET_NAME)",
    "SKIP_INSTALL": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES",
}


uitest_settings = {
    "CODE_SIGN_STYLE": "Automatic", "GENERATE_INFOPLIST_FILE": "YES",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_BASE).uitests", "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO", "TEST_TARGET_NAME": APP,
}


def config_list(owner, debug, release, base=None):
    ids = []
    for name, settings in (("Debug", debug), ("Release", release)):
        fields = {"buildSettings": settings, "name": name}
        if base:
            fields = {"baseConfigurationReference": base, **fields}
        ids.append(add(oid("cfg", owner, name), "XCBuildConfiguration", **fields))
    return add(oid("cfglist", owner), "XCConfigurationList", buildConfigurations=ids,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")


project_cfg = config_list("project", project_debug, project_release, base_xcconfig)
app_cfg = config_list(APP, app_settings, app_settings)
widget_cfg = config_list(WIDGET, widget_settings, widget_settings)
uitest_cfg = config_list(UITESTS, uitest_settings, uitest_settings)

# ---------- targets ----------
project_id = oid("project")
widget_target = add(oid("target", WIDGET), "PBXNativeTarget", buildConfigurationList=widget_cfg,
                    buildPhases=[w_sources, w_frameworks, w_resources], buildRules=[], dependencies=[],
                    name=WIDGET, productName=WIDGET, productReference=widget_product,
                    productType="com.apple.product-type.app-extension")
proxy = add(oid("proxy", WIDGET), "PBXContainerItemProxy", containerPortal=project_id, proxyType="1",
            remoteGlobalIDString=widget_target, remoteInfo=WIDGET)
dep = add(oid("dep", WIDGET), "PBXTargetDependency", target=widget_target, targetProxy=proxy)
app_target = add(oid("target", APP), "PBXNativeTarget", buildConfigurationList=app_cfg,
                 buildPhases=[app_sources, app_frameworks, app_resources, app_embed], buildRules=[],
                 dependencies=[dep], name=APP, productName=APP, productReference=app_product,
                 productType="com.apple.product-type.application")

t_proxy = add(oid("proxy", UITESTS), "PBXContainerItemProxy", containerPortal=project_id, proxyType="1",
              remoteGlobalIDString=app_target, remoteInfo=APP)
t_dep = add(oid("dep", UITESTS), "PBXTargetDependency", target=app_target, targetProxy=t_proxy)
uitest_target = add(oid("target", UITESTS), "PBXNativeTarget", buildConfigurationList=uitest_cfg,
                    buildPhases=[t_sources, t_frameworks, t_resources], buildRules=[], dependencies=[t_dep],
                    name=UITESTS, productName=UITESTS, productReference=uitest_product,
                    productType="com.apple.product-type.bundle.ui-testing")

add(project_id, "PBXProject",
    attributes={"BuildIndependentTargetsInParallel": "1", "LastSwiftUpdateCheck": "2600", "LastUpgradeCheck": "2600",
                "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "26.0"},
                                     widget_target: {"CreatedOnToolsVersion": "26.0"},
                                     uitest_target: {"CreatedOnToolsVersion": "26.0", "TestTargetID": app_target}}},
    buildConfigurationList=project_cfg, compatibilityVersion="Xcode 14.0", developmentRegion="en",
    hasScannedForEncodings="0", knownRegions=["en", "Base", "es", "pt-BR", "hi", "id", "ja", "de", "fr", "ar", "ta", "vi"], mainGroup=main_group,
    productRefGroup=products_group, projectDirPath="", projectRoot="", targets=[app_target, widget_target, uitest_target])


# ---------- serialize ----------
def ser(value, indent):
    tab = "\t" * indent
    if isinstance(value, dict):
        inner = "".join(f"{tab}\t{q(k)} = {ser(v, indent + 1)};\n" for k, v in value.items())
        return "{\n" + inner + tab + "}"
    if isinstance(value, list):
        inner = "".join(f"{tab}\t{ser(v, indent + 1)},\n" for v in value)
        return "(\n" + inner + tab + ")"
    return q(value)


ISA_ORDER = ["PBXBuildFile", "PBXContainerItemProxy", "PBXCopyFilesBuildPhase", "PBXFileReference",
             "PBXFrameworksBuildPhase", "PBXGroup", "PBXNativeTarget", "PBXProject", "PBXResourcesBuildPhase",
             "PBXSourcesBuildPhase", "PBXTargetDependency", "XCBuildConfiguration", "XCConfigurationList"]
out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {"]
for isa in ISA_ORDER:
    ids = sorted(i for i, (t, _) in objects.items() if t == isa)
    if not ids:
        continue
    out.append(f"\n/* Begin {isa} section */")
    for i in ids:
        body = ser({"isa": isa, **objects[i][1]}, 2)
        out.append(f"\t\t{i} = {body};")
    out.append(f"/* End {isa} section */")
out += ["\t};", f"\trootObject = {project_id};", "}", ""]

os.makedirs(PROJ, exist_ok=True)
with open(os.path.join(PROJ, "project.pbxproj"), "w") as f:
    f.write("\n".join(out))

# ---------- shared scheme (Xcode Cloud needs a shared scheme) ----------
ref_xml = f'''<BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:{APP}.xcodeproj">
         </BuildableReference>'''
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
         {ref_xml}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO" parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{uitest_target}"
               BuildableName = "{UITESTS}.xctest"
               BlueprintName = "{UITESTS}"
               ReferencedContainer = "container:{APP}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref_xml}
      </BuildableProductRunnable>
      <StoreKitConfigurationFileReference identifier = "../../Products.storekit">
      </StoreKitConfigurationFileReference>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref_xml}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
sdir = os.path.join(PROJ, "xcshareddata", "xcschemes")
os.makedirs(sdir, exist_ok=True)
with open(os.path.join(sdir, f"{APP}.xcscheme"), "w") as f:
    f.write(scheme)
wdir = os.path.join(PROJ, "project.xcworkspace")
os.makedirs(wdir, exist_ok=True)
with open(os.path.join(wdir, "contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n'
            '   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')
print(f"Generated {PROJ} with {len(objects)} objects")
