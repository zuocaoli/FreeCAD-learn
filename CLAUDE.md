# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

FreeCAD 是开源参数化 3D CAD(LGPL-2.1+):C++ 核心 + Python API、Qt6 GUI、OpenCASCADE(OCCT)几何内核、Coin3D 场景图。PR 一律发往 `main`;本仓库当前检出于本地 `dev` 分支。

## 构建

- 本机已有配置好的构建树 `build/debug`(Ninja、系统 GCC、Debug、`BUILD_WITH_CONDA=OFF`、`BUILD_GUI=ON`、`ENABLE_DEVELOPER_TESTS=ON`)。增量构建:
  - `cmake --build build/debug`(或 `ninja -C build/debug`)
- 产物:`build/debug/bin/FreeCAD`(GUI)与 `build/debug/bin/FreeCADCmd`(无界面控制台版,适合无显示环境跑脚本)。
- pixi(pixi.toml)提供 conda-forge 依赖环境,任务走 debug 变体:`pixi run configure-debug` / `build-debug` / `test-debug` / `freecad-debug`(release 同理)。`initialize` 任务负责 `git submodule update --init --recursive`。
  - **注意**:pixi 任务与现有 `build/debug` 共用同一构建目录(CMakePresets 的 `conda-linux-debug` 预设 binaryDir 就是 `build/debug`)。当前该目录用系统编译器配置,若执行 `pixi run configure-debug` 会用 conda 环境重新配置并覆盖现有配置,两者不要混用。
- CMakePresets.json:`conda-linux-*`/`conda-macos-*`/`conda-windows-*` 走 pixi/conda 环境(默认 clang + mold,含 OCCT/SMESH);裸 `debug`/`release` 预设用系统依赖。
- 子模块:`src/3rdParty`(OndselSolver、GSL、coin、pivy)、`src/Mod/AddonManager`。
- 源文件均在 CMakeLists.txt 中显式列出,新增/删除文件后需重新运行 cmake 配置。

## 测试

- C++ 单测用 GoogleTest,可执行文件在 `build/debug/tests/<模块>_tests_run`(`Base_tests_run`、`App_tests_run`、`Gui_tests_run` 及各工作台),经 `gtest_discover_tests` 注册进 CTest(测试发现发生在 test 阶段前,改测试后直接 `ctest` 即可)。
  - 全部:`ctest --test-dir build/debug`
  - 按名称过滤:`ctest --test-dir build/debug -R <SuiteName>`
  - 单测直跑:`build/debug/tests/Base_tests_run --gtest_filter=Suite.Test`
- GUI 相关测试(如 `InventorBuilder_Tests_run`)用 QtTest,CTest 强制 `QT_QPA_PLATFORM=offscreen`。
- Python 测试:unittest 风格,核心套件在 `src/Mod/Test`(通过 GUI 的 Test 工作台或 `FreeCADCmd` 运行),各工作台另有 `Test<Mod>App.py` / `Test<Mod>Gui.py`。

## Lint 与格式

- 格式由 pre-commit 管理(`.pre-commit-config.yaml`):clang-format(固定 22.1.5)、black(`--line-length 100`)、trailing-whitespace、行尾/大文件等;`files` 正则限定覆盖范围(src 核心 + 多数 Mod + tests/src)。按改动文件跑:`pre-commit run --files <file>`。
- `.clang-format`:LLVM 基底、4 空格缩进、ColumnLimit 100、函数/类大括号换行(Qt 风格)。
- CI(sub_lint.yml)用 `tools/lint/` 下脚本:pylint.py、clang_tidy.py、clang_format.py、qt_connections.py、codespell.py、python_stubs.py(生成绑定存根冒烟检查)。
- 版本一致性:`version.json` 是唯一版本来源;CI 跑 `python src/Tools/sync_version.py --check`,改版本后需 `--update` 同步 pixi.toml / recipe / 打包脚本。

## 架构

### 分层(链接依赖严格单向)

- `src/Base` → `FreeCADBase`:不依赖其他层。控制台、参数系统(Parameter)、单位(Quantity/Unit)、zipios、异常、字符串/流等基础工具。
- `src/App` → `FreeCADApp`(链 FreeCADBase):文档模型。Application、Document、DocumentObject(Feature)与 Property 体系、对象依赖图与 recompute、Expression 引擎。
- `src/Gui` → `FreeCADGui`(链 FreeCADApp):Qt 主窗口 + Coin3D 三维视图(View3DInventor)。ViewProvider 与 App 对象一一对应;Command / Workbench 是菜单与工具条的动作模型。Qt6 优先,仍支持 Qt5(`FREECAD_QT_VERSION`)。
- `src/Main`:仅两个入口——`MainGui.cpp`(FreeCAD 可执行)与 `MainCmd.cpp`(FreeCADCmd 控制台)。用 `FreeCAD.GuiUp` 判断 GUI 是否可用,控制台代码不要无条件 import FreeCADGui。

### 工作台模块 `src/Mod/<Name>/`

每个工作台是一个运行时加载的模块,典型结构(样板见 Part、Sketcher、PartDesign):

- `App/` → 共享库 `<Name>`(如 `Part`),链 FreeCADApp,同时注册为 Python 扩展模块(含模块级 Python API);
- `Gui/` → 共享库 `<Name>Gui`,链 FreeCADGui;
- 模块根下 Python 文件:控制台启动执行 `Init.py`,GUI 启动执行 `InitGui.py`(GUI 侧扫描逻辑在 `src/Gui/Application.cpp` / `StartupProcess.cpp`);`<Name>.dox` 是模块文档;
- 纯 Python 工作台(如 Draft、CAM 的 Python 部分)只有 Python 文件与 `.ui` 资源。

各工作台可用 `BUILD_<MOD>` 开关裁剪(如 `BUILD_PART`、`BUILD_ASSEMBLY`、`BUILD_GUI`)。

### Python 绑定

- `.pyi` 存根是绑定的事实来源。CMake 宏 `generate_from_py(X)` / `generate_module_from_py()`(cMake/FreeCadMacros.cmake)用 `src/Tools/bindings/generate.py` 在构建目录生成 `XPy.cpp/.h`,手写的 `XPyImp.cpp` 提供方法实现。
- 改 API = 改 `.pyi` + 对应 `PyImp.cpp`;生成的 `XPy.cpp` 勿手改。`python_stubs.py` lint 检查存根一致性。
- pybind11 仅用于 CAM 的 flat-mesh 特性(`FREECAD_USE_PYBIND11`,conda 预设默认开),核心类绑定走 `.pyi` 生成器。

### 生成/派生源码(勿手改)

- `src/App/Expression.tab.c` / `Expression.lex.c`:bison/flex 预生成并入库,经 `ExpressionParser.sh` 重新生成(pre-commit 已排除)。
- `src/3rdParty`:vendored 三方代码(coin、pivy、zipios++、PyCXX、salomesmesh 等),不直接修改。

### 关键第三方

- OpenCASCADE(OCCT):几何内核,所有建模操作与 TopoDS 数据结构的来源。
- Coin3D / Quarter:3D 场景图;Python 侧用 pivy。
- 翻译:`.ts` 文件在 `src/*/Resources/translations/` 及各 Mod 目录,由 Crowdin 同步,勿手改其他语言变体。

## 贡献约定(来自 CONTRIBUTING.md / AI_POLICY.md)

- 提交与 PR 标题用 `模块前缀: 描述` 形式(如 `Gui: Sync zoom with spacemouse...`)。PR 内每个提交都应能独立编译,checkpoint 提交应 squash。
- AI_POLICY:PR 描述须披露 AI 协助,提交信息须加 trailer,如 `Assisted-by: <Model-Family> (<Version/ID>)`。
- 所有源文件以 LGPL-2.1-or-later 头开头(SPDX 行 `LGPL-2.1-or-later`)。
- 不得破坏 Python API(扩展/addon 依赖它);确需破坏时必须在 PR 中描述迁移方式,并搜索会受影响的 addon。
