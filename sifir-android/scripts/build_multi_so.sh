#!/bin/bash
set -e

# Ensure we use rustup cargo, not MacPorts
export PATH="$HOME/.cargo/bin:$PATH"

# Use ANDROID_NDK_HOME if ANDROID_NDK_ROOT is not set
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$ANDROID_NDK_HOME}"

if [ -z "$ANDROID_NDK_ROOT" ]; then
    echo "ERROR: ANDROID_NDK_ROOT or ANDROID_NDK_HOME must be set"
    exit 1
fi

cd ..

# ---------------------------------------------------------------------------
# Patch upstream crate build scripts for Android cross-compilation
# These patches fix issues in vendored/dependency crates that don't
# handle Android JNI builds correctly.
# ---------------------------------------------------------------------------

# 1) libz-sys: build vendored zlib on Android when static feature is set.
#    Stock libz-sys short-circuits on Android with just `cargo:rustc-link-lib=z`
#    assuming system zlib exists, which means DEP_Z_ROOT is never set.
#    libtor-sys needs DEP_Z_ROOT to pass --with-zlib-dir to Tor's configure.
LIBZ_BUILD_RS=$(find "$HOME/.cargo/registry/src" -path "*/libz-sys-1.1.3/build.rs" 2>/dev/null | head -1)
if [ -n "$LIBZ_BUILD_RS" ]; then
    if grep -q '^    if target.contains("android") || target.contains("haiku") {' "$LIBZ_BUILD_RS"; then
        echo "Patching libz-sys: build vendored zlib on Android when static..."
        sed -i.bak 's/if target.contains("android") || target.contains("haiku") {/if !want_static \&\& (target.contains("android") || target.contains("haiku")) {/' "$LIBZ_BUILD_RS"
    fi
fi

# 2) libtor-sys: two fixes for Android builds with dynamic libc.
LIBTOR_BUILD_RS=$(find "$HOME/.cargo/registry/src" -path "*/libtor-sys-*/build.rs" 2>/dev/null | head -1)
if [ -n "$LIBTOR_BUILD_RS" ]; then
    # 2a) Remove fake-stdio compilation. fake-stdio/stdio.c defines
    #     `int stdin = 0; int stderr = 2;` which shadow libc's FILE* pointers.
    #     With dynamic libc (--exclude-libs,libc.a), Tor code calling
    #     fprintf(stderr,...) dereferences 0x2 as a FILE*, corrupting the heap.
    if grep -q 'fake-stdio/stdio.c' "$LIBTOR_BUILD_RS"; then
        echo "Patching libtor-sys: remove fake-stdio compilation..."
        sed -i.bak '/\/\/ provides stdin and stderr/,/\.compile("libfakestdio\.a");/d' "$LIBTOR_BUILD_RS"
    fi

    # 2b) Use DEP_Z_ROOT for zlib on Android instead of sysroot clang hack.
    #     The original code uses `clang --print-file-name libz.a` to find
    #     the NDK sysroot zlib, but we build vendored zlib via libz-sys.
    if grep -q 'print-file-name.*libz.a' "$LIBTOR_BUILD_RS"; then
        echo "Patching libtor-sys: use DEP_Z_ROOT on Android..."
        # Replace the android-specific zlib block with just the android config flag,
        # and make the DEP_Z_ROOT block unconditional
        python3 -c "
import re, sys
with open('$LIBTOR_BUILD_RS', 'r') as f:
    content = f.read()

# Replace the if/else block for android vs non-android zlib handling
old = r'''    if target.contains\(\"android\"\) \{
.*?\.with\(\"zlib-dir\", Some\(\&sysroot_lib\)\);

        println!\(\"cargo:rustc-link-search=native=\{\}\", sysroot_lib\);
    \} else \{'''

new = '''    if target.contains(\"android\") {
        config.enable(\"android\", None);
    }

    {'''

content = re.sub(old, new, content, flags=re.DOTALL)

with open('$LIBTOR_BUILD_RS', 'w') as f:
    f.write(content)
print('  Applied DEP_Z_ROOT patch')
"
    fi
fi

echo "--- Dependency patches applied ---"
echo ""

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

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
