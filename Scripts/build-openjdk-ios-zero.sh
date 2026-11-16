#!/usr/bin/env bash
set -euo pipefail

# Exploratory OpenJDK Mobile Zero VM build for physical iOS ARM64.
# This produces a static libjvm.a only; it is NOT a complete runtime or an IPA.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.runtime-build"
OPENJDK_DIR="${WORK_DIR}/openjdk-mobile"
SUPPORT_ZIP="${WORK_DIR}/mobile-support.zip"
SUPPORT_DIR="${WORK_DIR}/mobile-support"
OUTPUT_DIR="${ROOT_DIR}/artifacts/openjdk-ios-zero"

OPENJDK_MOBILE_COMMIT="c13417aa36f8f44755d0984b58aa735d0b41f233"
SUPPORT_URL="https://download2.gluonhq.com/mobile/mobile-support-20250106.zip"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script requires macOS with Xcode and the iPhoneOS SDK." >&2
  exit 2
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Xcode command-line tools are required." >&2
  exit 2
fi

if ! command -v autoconf >/dev/null 2>&1; then
  echo "Missing autoconf. Install it with: brew install autoconf" >&2
  exit 2
fi

JAVA_HOME_PATH="${JAVA_HOME:-}"
if [[ -z "${JAVA_HOME_PATH}" || ! -x "${JAVA_HOME_PATH}/bin/java" ]]; then
  JAVA_HOME_PATH="$(/usr/libexec/java_home -v 24)"
fi
if [[ ! -x "${JAVA_HOME_PATH}/bin/java" ]]; then
  echo "A macOS JDK 24 boot JDK is required." >&2
  exit 2
fi

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

if [[ ! -d "${OPENJDK_DIR}/.git" ]]; then
  git init "${OPENJDK_DIR}"
  git -C "${OPENJDK_DIR}" remote add origin https://github.com/openjdk/mobile.git
fi

git -C "${OPENJDK_DIR}" fetch --depth=1 origin "${OPENJDK_MOBILE_COMMIT}"
git -C "${OPENJDK_DIR}" checkout --detach FETCH_HEAD

if [[ ! -d "${SUPPORT_DIR}/libffi" || ! -d "${SUPPORT_DIR}/cups-2.3.6" ]]; then
  curl --fail --location --retry 3 --output "${SUPPORT_ZIP}" "${SUPPORT_URL}"
  rm -rf "${SUPPORT_DIR}"
  mkdir -p "${SUPPORT_DIR}"
  unzip -q "${SUPPORT_ZIP}" -d "${SUPPORT_DIR}"
fi

cd "${OPENJDK_DIR}"
sh configure \
  --disable-warnings-as-errors \
  --openjdk-target=aarch64-macos-ios \
  --with-jvm-variants=zero \
  --with-boot-jdk="${JAVA_HOME_PATH}" \
  --with-libffi-include="${SUPPORT_DIR}/libffi/include" \
  --with-libffi-lib="${SUPPORT_DIR}/libffi/libs" \
  --with-cups-include="${SUPPORT_DIR}/cups-2.3.6" \
  --with-sysroot="${IOS_SDK}"

make CONF=ios-aarch64-zero-release static-libs-image

LIBJVM="${OPENJDK_DIR}/build/ios-aarch64-zero-release/images/static-libs/lib/zero/libjvm.a"
if [[ ! -s "${LIBJVM}" ]]; then
  echo "Expected static JVM library was not produced: ${LIBJVM}" >&2
  exit 1
fi

cp "${LIBJVM}" "${OUTPUT_DIR}/libjvm.a"
for license_file in LICENSE ASSEMBLY_EXCEPTION ADDITIONAL_LICENSE_INFO; do
  if [[ -f "${OPENJDK_DIR}/${license_file}" ]]; then
    cp "${OPENJDK_DIR}/${license_file}" "${OUTPUT_DIR}/${license_file}"
  fi
done
printf '%s\n' "${OPENJDK_MOBILE_COMMIT}" > "${OUTPUT_DIR}/OPENJDK_COMMIT.txt"
printf '%s\n' "$("${JAVA_HOME_PATH}/bin/java" -version 2>&1 | head -n 1)" > "${OUTPUT_DIR}/BOOT_JDK.txt"
printf '%s\n' "Zero VM static library only; no Java class library image, JLI launcher, JNI bridge, or game runtime is included." > "${OUTPUT_DIR}/STATUS.txt"

echo "Built exploratory iOS ARM64 Zero VM static library:"
ls -lh "${OUTPUT_DIR}/libjvm.a"
