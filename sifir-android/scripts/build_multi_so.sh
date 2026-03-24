#!/bin/bash
set -e

# Ensure we use rustup cargo, not MacPorts
export PATH="$HOME/.cargo/bin:$PATH"

# Use ANDROID_NDK_HOME if ANDROID_NDK_ROOT is not set
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$ANDROID_NDK_HOME}"

cd ..

# Patch libz-sys to build vendored zlib on Android instead of assuming
# system zlib exists. The stock libz-sys short-circuits on Android with
# just `println!("cargo:rustc-link-lib=z")` which means DEP_Z_ROOT is
# never set, causing libtor-sys's configure to fail with:
#   "You must specify an explicit --with-zlib-dir=x option"
LIBZ_BUILD_RS=$(find "$HOME/.cargo/registry/src" -path "*/libz-sys-1.1.3/build.rs" 2>/dev/null | head -1)
if [ -n "$LIBZ_BUILD_RS" ]; then
    if grep -q 'target.contains("android")' "$LIBZ_BUILD_RS"; then
        echo "Patching libz-sys build.rs to build vendored zlib on Android..."
        sed -i.bak 's/if target.contains("android") || target.contains("haiku") {/if !want_static \&\& (target.contains("android") || target.contains("haiku")) {/' "$LIBZ_BUILD_RS"
    fi
fi

OS=$(uname)
if [ "$OS" = "Darwin" ]; then
    echo "building apple darwin x86_64 lib"
    cargo build --target x86_64-apple-darwin -p sifir-android --release
    retVal=$?
    [ ! $retVal -eq 0 ] && exit 1
elif [ "$OS" = "Linux" ]; then
    echo "building linux x86_64 lib"
    cargo build --target x86_64-unknown-linux-gnu -p sifir-android --release
    retVal=$?
    [ ! $retVal -eq 0 ] && exit 1
fi

cargo ndk --platform 30 --target x86_64-linux-android build -p sifir-android --release
retVal=$?
[ ! $retVal -eq 0 ] && exit 1
cargo ndk --platform 30 --target aarch64-linux-android build -p sifir-android --release
retVal=$?
[ ! $retVal -eq 0 ] && exit 1
cargo ndk --platform 30 --target armv7-linux-androideabi build -p sifir-android --release
retVal=$?
[ ! $retVal -eq 0 ] && exit 1
cargo ndk --platform 30 --target i686-linux-android build -p sifir-android --release
retVal=$?
[ ! $retVal -eq 0 ] && exit 1

echo "Done!"
