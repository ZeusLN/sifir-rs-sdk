# Building sifir-rs-sdk for Android

## Prerequisites

- **Rust** via rustup (not system/MacPorts): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- **Android NDK** r28+ (set `ANDROID_NDK_HOME` or `ANDROID_NDK_ROOT`)
- **cargo-ndk**: `cargo install cargo-ndk`
- **Rust Android targets**:
  ```
  rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
  ```

## Build

```bash
cd sifir-android/scripts
./build_multi_so.sh
```

The script automatically patches upstream dependency build scripts before compiling. See below for details.

## Packaging the AAR

After building all targets:

```bash
cd sifir-android/scripts
./build_aar_from_so.sh
```

The AAR is output to `sifir-android/outputs/aar/`.

## What the build does differently

### 1. Dynamic libc linking (`--exclude-libs,libc.a`)

Configured in `.cargo/config.toml`. Without this, the `.so` statically links Android's bionic libc, embedding its own `pthread_create`, `__libc_shared_globals`, etc. These static copies don't work in a JNI context because:
- `__libc_shared_globals` is never initialized by the dynamic linker
- Thread Control Block layout offsets default to -1
- `pthread_create` places the TCB at invalid memory → SIGSEGV

The `--exclude-libs,libc.a` flag makes all symbols from the static `libc.a` local/hidden, so the dynamic linker resolves them from the system's `libc.so` at runtime.

### 2. Patched `libz-sys` (vendored zlib on Android)

Stock `libz-sys` v1.1.3 short-circuits on Android with `cargo:rustc-link-lib=z`, assuming system zlib exists. This means `DEP_Z_ROOT` is never set, and `libtor-sys`'s configure fails with:
```
You must specify an explicit --with-zlib-dir=x option when using --enable-static-zlib
```

The build script patches `libz-sys` to build vendored zlib from source when the `static` feature is enabled (which `libtor-sys` requests).

### 3. Patched `libtor-sys` (no fake-stdio, vendored zlib path)

Two fixes:

- **Removed `fake-stdio`**: `libtor-sys` compiles `fake-stdio/stdio.c` which defines `int stdin = 0; int stderr = 2;`. These shadow libc's `FILE*` pointers. With dynamic libc, Tor code calling `fprintf(stderr, ...)` dereferences `0x2` as a `FILE*`, corrupting the Java heap.

- **Use `DEP_Z_ROOT` on Android**: The original code uses `clang --print-file-name libz.a` to find NDK sysroot zlib. Since we now build vendored zlib via `libz-sys`, we use `DEP_Z_ROOT` (set automatically by cargo) to point Tor's configure at the vendored build.
