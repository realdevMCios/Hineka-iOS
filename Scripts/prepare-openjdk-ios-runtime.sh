#!/usr/bin/env bash
set -euo pipefail

# Prepare a reproducible, experimental OpenJDK Mobile Zero runtime input set.
# The upstream snapshot is pinned by SHA-256. This script does not sign or install an IPA.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.runtime-build"
DOWNLOAD_DIR="${WORK_DIR}/downloads"
EXTRACT_DIR="${WORK_DIR}/extracted"
RESOURCE_DIR="${ROOT_DIR}/App/Runtime/Swift/Resources"

OPENJDK_ZIP="${DOWNLOAD_DIR}/OpenJDK.xcframework.zip"
JAVA_BUNDLE_ZIP="${DOWNLOAD_DIR}/java_bundle-device.zip"

OPENJDK_URL="https://github.com/openjdk-mobile/ios-tools/releases/download/snapshot/OpenJDK.xcframework.zip"
JAVA_BUNDLE_URL="https://github.com/openjdk-mobile/ios-tools/releases/download/snapshot/java_bundle-device.zip"

OPENJDK_SHA256="ae8e22142e45e5c1e9e8e3541829f3cc00584658eb21eeeb0d3612e3fbaf7c9f"
JAVA_BUNDLE_SHA256="37387a48bdd7f1ce1d3a38e88356e61288673c91b42ef27cf1b71d27e05cc54a"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 2
  fi
}

require_command curl
require_command unzip
require_command shasum
require_command javac
require_command jar
require_command python3

mkdir -p "${DOWNLOAD_DIR}" "${EXTRACT_DIR}" "${RESOURCE_DIR}/lib"

download_if_missing() {
  local url="$1"
  local target="$2"
  if [[ ! -s "$target" ]]; then
    echo "Downloading $(basename "$target")..."
    curl --fail --location --retry 3 --retry-all-errors --connect-timeout 30 \
      --output "$target" "$url"
  fi
}

download_if_missing "$OPENJDK_URL" "$OPENJDK_ZIP"
download_if_missing "$JAVA_BUNDLE_URL" "$JAVA_BUNDLE_ZIP"

echo "${OPENJDK_SHA256}  ${OPENJDK_ZIP}" | shasum -a 256 -c -
echo "${JAVA_BUNDLE_SHA256}  ${JAVA_BUNDLE_ZIP}" | shasum -a 256 -c -

rm -rf "${EXTRACT_DIR}/OpenJDK.xcframework" "${EXTRACT_DIR}/java_bundle-device"
unzip -q "$OPENJDK_ZIP" -d "$EXTRACT_DIR"
unzip -q "$JAVA_BUNDLE_ZIP" -d "$EXTRACT_DIR"

FRAMEWORK_DIR="${EXTRACT_DIR}/OpenJDK.xcframework"
MODULES_FILE="${EXTRACT_DIR}/java_bundle-device/lib/modules"

if [[ ! -s "${FRAMEWORK_DIR}/Info.plist" ]]; then
  echo "The pinned OpenJDK archive did not contain OpenJDK.xcframework/Info.plist." >&2
  find "$EXTRACT_DIR" -maxdepth 4 -print | sed -n '1,200p'
  exit 1
fi

if [[ ! -s "$MODULES_FILE" ]]; then
  echo "The pinned Java bundle did not contain lib/modules." >&2
  find "${EXTRACT_DIR}/java_bundle-device" -maxdepth 4 -print | sed -n '1,200p'
  exit 1
fi

python3 - "$FRAMEWORK_DIR/Info.plist" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as stream:
    info = plistlib.load(stream)

libraries = info.get("AvailableLibraries", [])
matches = [
    item for item in libraries
    if item.get("SupportedPlatform") == "ios"
    and "arm64" in item.get("SupportedArchitectures", [])
]
if not matches:
    raise SystemExit("OpenJDK.xcframework has no iOS arm64 device slice.")
print("Verified OpenJDK XCFramework iOS arm64 slice:")
for item in matches:
    print(" -", item.get("LibraryIdentifier"), item.get("LibraryPath"))
PY

# The iOS-tools HelloWorld instructions bundle java.base as <resource>/lib/modules.
cp -f "$MODULES_FILE" "${RESOURCE_DIR}/lib/modules"

if [[ ! -s "${RESOURCE_DIR}/lib/modules" ]]; then
  echo "Failed to stage java.base modules image." >&2
  exit 1
fi

JAVA_SOURCE="${ROOT_DIR}/App/Runtime/SmokeTest/HinekaRuntimeSmokeTest.java"
CLASSES_DIR="${WORK_DIR}/smoke-classes"
JAR_PATH="${RESOURCE_DIR}/HinekaRuntimeSmokeTest.jar"

mkdir -p "$CLASSES_DIR"
rm -rf "${CLASSES_DIR:?}/"*
# Compile Java 17-compatible bytecode so this smoke test also works with the older
# pinned upstream snapshot; the bundle's exact VM version is reported by the test.
javac --release 17 -encoding UTF-8 -d "$CLASSES_DIR" "$JAVA_SOURCE"
jar --create --file "$JAR_PATH" -C "$CLASSES_DIR" .

if [[ ! -s "$JAR_PATH" ]]; then
  echo "Failed to compile the Java smoke-test JAR." >&2
  exit 1
fi

cat > "${RESOURCE_DIR}/openjdk-runtime-manifest.txt" <<EOF
Runtime source: openjdk-mobile/ios-tools snapshot release
OpenJDK XCFramework SHA-256: ${OPENJDK_SHA256}
java_bundle-device SHA-256: ${JAVA_BUNDLE_SHA256}
Runtime mode: OpenJDK Mobile Zero (interpreter / no JIT)
Architecture staged: iOS arm64 device
Java boot/compiler used by CI: $(javac -version 2>&1)
Purpose: experimental HelloWorld/JNI startup test only
Not a complete Minecraft runtime; not an IPA; not signed.
EOF

echo "Prepared pinned OpenJDK inputs:"
ls -lh "${FRAMEWORK_DIR}/Info.plist" "${RESOURCE_DIR}/lib/modules" "$JAR_PATH"
echo "Runtime preparation complete. This does not prove that Hineka can run Minecraft."
