#!/usr/bin/env bash
# FreeCAD 构建/运行脚本(系统工具链,不使用 pixi/conda)
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"   # 保证任意 CWD 下都以仓库根为基准

# ============ 编译配置(需要时手动修改)============
BUILD_TYPE=Debug                     # Release 或 Debug

BUILD_DIR="build/${BUILD_TYPE,,}"
BIN="$BUILD_DIR/bin/FreeCAD"

case "$BUILD_TYPE" in
    Release | Debug) ;;
    *)
        echo "错误: BUILD_TYPE 必须是 Release 或 Debug(当前: $BUILD_TYPE)" >&2
        exit 1
        ;;
esac

usage() {
    cat <<'EOF'
用法:
  ./build.sh          配置并编译 FreeCAD(增量,默认 Release,见脚本开头 BUILD_TYPE)
  ./build.sh run      运行 FreeCAD(不编译;未编译则报错)
  ./build.sh help     显示本帮助
EOF
}

case "${1:-}" in
    "")
        # 每次都跑 configure:幂等,且能拾取新增/删除的源文件(CMakeLists 显式列文件)
        cmake --preset "${BUILD_TYPE,,}" -G Ninja \
            -DBUILD_WITH_CONDA=OFF \
            -DBUILD_GUI=ON \
            -DENABLE_DEVELOPER_TESTS=ON
        cmake --build "$BUILD_DIR"
        ;;
    run)
        shift
        if [[ ! -x "$BIN" ]]; then
            echo "错误: 未找到可执行文件 $BUILD_DIR/bin/FreeCAD —— 尚未编译,请先运行 ./build.sh" >&2
            exit 1
        fi
        exec "$BIN" "$@"
        ;;
    help | -h | --help)
        usage
        ;;
    *)
        echo "未知参数: ${1:-}" >&2
        usage
        exit 1
        ;;
esac
