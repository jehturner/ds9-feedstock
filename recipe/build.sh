#!/usr/bin/env bash

set -eu

if [[ "$target_platform" == osx-* ]]; then
  # Needed for conda-forge clang 20 to build some source bundled in v8.6:
  export CFLAGS="-std=gnu11 ${CFLAGS}"
  export CXXFLAGS="-std=gnu++11 ${CXXFLAGS}"

  # Remove internal codesign; we will do it manually at the end:
  sed -i -e '/codesign/d' ds9/unix/Makefile.in
fi

# Dynamically patch several Makefiles that dubiously pass CFLAGS instead of
# CXXFLAGS to the C++ compiler (for historical reasons), causing failures when
# C++ therefore gets passed the C "-std" option above:
find . -name "Makefile.in" -exec sed -ie '/COMPILE_CXX[[:space:]]*=/s|\$(CFLAGS)|\$(CXXFLAGS)|g' {} \;

# Needed to find xorgproto (which replaces xproto) during the build:
PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${PREFIX}/share/pkgconfig"

# Patches are applied in meta.yaml so that everything can be built against
# conda's X11 libs and the latest ds9 Makefile won't override TKFLAGS below.

# Make sure patched files are newer than their sources, so they won't get
# regenerated/overwritten by autotools:
touch unix/configure unix/Makefile.in tkimg/libtiff/configure

# Build for X11 (irrespective of the platform):
./unix/configure \
  --prefix="${PREFIX}" \
  --x-includes="${PREFIX}/include" \
  --x-libraries="${PREFIX}/lib" \
  TKFLAGS="--disable-xss"  # not really needed & sometimes unavailable

make -j${CPU_COUNT}

mkdir -p "$PREFIX/bin"
cp -a bin/ds9* bin/x* "$PREFIX/bin/"

# Ad-hoc signing is good practice on newer MacOS versions and avoids
# "Killed: 9" on ARM. It's safest to do explicitly at the very end (including
# xpa helper executables, to avoid broken communications). Conda-build repeats
# this step after editing binary paths, but only if a signature already exists:
if [[ "$target_platform" == osx-* ]]; then
  codesign -s - -f "${PREFIX}/bin/ds9" "${PREFIX}"/bin/xpa*
fi
