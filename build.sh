#!/usr/bin/env bash
# FreeCAD 构建/运行脚本(系统工具链,默认 clang,不使用 pixi/conda)
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"   # 保证任意 CWD 下都以仓库根为基准

# ============ 编译配置(需要时手动修改)============
BUILD_TYPE=Debug                     # Release 或 Debug
TOOLCHAIN=clang                      # clang 或 gcc(切换编译器需删除 build/<type> 后全新构建)

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
  ./build.sh          配置并编译 FreeCAD(增量;构建类型/编译器见脚本开头 BUILD_TYPE/TOOLCHAIN)
  ./build.sh run      运行 FreeCAD(不编译;未编译则报错)
  ./build.sh help     显示本帮助
EOF
}

case "${1:-}" in
    "")
        case "$TOOLCHAIN" in
            clang)
                CC_BIN=clang
                CXX_BIN=clang++
                ;;
            gcc)
                CC_BIN=gcc
                CXX_BIN=g++
                ;;
            *)
                echo "错误: TOOLCHAIN 必须是 clang 或 gcc(当前: $TOOLCHAIN)" >&2
                exit 1
                ;;
        esac

        command -v "$CC_BIN"  >/dev/null || { echo "错误: 未找到编译器 $CC_BIN(Fedora 安装: sudo dnf install clang 或 gcc)" >&2; exit 1; }
        command -v "$CXX_BIN" >/dev/null || { echo "错误: 未找到编译器 $CXX_BIN(Fedora 安装: sudo dnf install clang 或 gcc)" >&2; exit 1; }

        # 防止在旧编译器配置过的构建目录上直接换编译器(CMake 缓存与新编译器不匹配会导致报错)
        CACHE="$BUILD_DIR/CMakeCache.txt"
        if [[ -f "$CACHE" ]]; then
            CACHED_CXX=$(grep -E '^CMAKE_CXX_COMPILER:FILEPATH=' "$CACHE" | cut -d= -f2)
            if [[ -n "$CACHED_CXX" ]] \
                && { [[ "$TOOLCHAIN" == clang && "$CACHED_CXX" != *clang* ]] \
                  || [[ "$TOOLCHAIN" == gcc  && "$CACHED_CXX" == *clang* ]]; }; then
                echo "错误: $BUILD_DIR 已由 $CACHED_CXX 配置,与 TOOLCHAIN=$TOOLCHAIN 不一致。" >&2
                echo "      切换编译器需要全新构建:删除 $BUILD_DIR 后重新运行 ./build.sh" >&2
                exit 1
            fi
        fi

        # 每次都跑 configure:幂等,且能拾取新增/删除的源文件(CMakeLists 显式列文件)
        cmake --preset "${BUILD_TYPE,,}" -G Ninja \
            -DCMAKE_C_COMPILER="$CC_BIN" \
            -DCMAKE_CXX_COMPILER="$CXX_BIN" \
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
