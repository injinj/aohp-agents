#!/bin/sh
# Install the official glibc Node.js build from nodejs.org into /usr/local (verified against SHASUMS256.txt).
# Used by every template Dockerfile (runs inside the image; needs curl, tar, xz, sha256sum).
set -eu
NODE_VERSION=${NODE_VERSION:-v24.21.0}
case "$(uname -m)" in
  x86_64) NODE_ARCH=x64 ;;
  aarch64) NODE_ARCH=arm64 ;;
  *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
esac
TARBALL=node-$NODE_VERSION-linux-$NODE_ARCH.tar.xz
cd /tmp
echo "[node] $NODE_VERSION $NODE_ARCH"
curl -fsSLO "https://nodejs.org/dist/$NODE_VERSION/$TARBALL"
curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" | grep " $TARBALL$" > SHASUMS256.want
sha256sum -c SHASUMS256.want
tar -xJf "$TARBALL" -C /usr/local --strip-components=1 --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE'
rm -f "$TARBALL" SHASUMS256.want
rm -rf /usr/local/include/node /usr/local/share/doc/node   # headers only matter for node-gyp builds (npm installs its own on demand)
node -v; npm -v
