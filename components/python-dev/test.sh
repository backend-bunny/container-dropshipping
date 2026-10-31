#!/usr/bin/env bash
# Smoke test for python-dev: as uid 65532, build a C extension into a venv
# with pip (offline, no build isolation), check uv, and run the result.
# Usage: test.sh IMAGE (with $VERSION = expected Python version)
set -euo pipefail
image=${1:?usage: test.sh IMAGE}
: "${VERSION:?VERSION (expected Python version) is required}"

src=$(mktemp -d)
trap 'rm -rf "$src"' EXIT
mkdir -p "$src/hello"
cat >"$src/hello/pyproject.toml" <<'EOF'
[build-system]
requires = ["setuptools"]
build-backend = "setuptools.build_meta"

[project]
name = "hello"
version = "0.1"
EOF
cat >"$src/hello/setup.py" <<'EOF'
from setuptools import Extension, setup
setup(ext_modules=[Extension("hello", ["hello.c"])])
EOF
cat >"$src/hello/hello.c" <<'EOF'
#include <Python.h>
static PyObject *hi(PyObject *self, PyObject *args) { return PyUnicode_FromString("hi"); }
static PyMethodDef methods[] = {{"hi", hi, METH_NOARGS, NULL}, {NULL}};
static struct PyModuleDef mod = {PyModuleDef_HEAD_INIT, "hello", NULL, -1, methods};
PyMODINIT_FUNC PyInit_hello(void) { return PyModule_Create(&mod); }
EOF
chmod -R a+rX "$src"

script='
test "$(id -u)" = 65532
python --version | grep -qx "Python $VERSION"
pip --version
uv --version
git --version
cc --version
python3-config --includes

# setuptools comes from the image (no index, no build isolation).
python -m venv --system-site-packages /tmp/venv
# pip builds in-tree, so build from a writable copy.
cp -r /src/hello /tmp/hello
/tmp/venv/bin/pip install --no-index --no-build-isolation /tmp/hello
test "$(/tmp/venv/bin/python -c "import hello; print(hello.hi())")" = hi

uv venv -q --python /usr/bin/python /tmp/uv
test "$(/tmp/uv/bin/python --version)" = "Python $VERSION"
'
docker run --rm -i --cap-drop ALL --security-opt no-new-privileges \
  --entrypoint /bin/sh --volume "$src:/src:ro" --env VERSION="$VERSION" \
  "$image" -eux <<<"$script"
echo "C extension built and imported"
