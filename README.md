# 149_Slicer

面向颗粒挤出式 3D 打印的 macOS 建模与切片应用，集成参数化造型、实时预览、打印路径生成和校准工作区。

**macOS 13+ · Apple Silicon · 中文界面**

[下载最新版本](https://github.com/Morayla/149_Slicer/releases/latest) · [版本记录](https://github.com/Morayla/149_Slicer/releases) · [问题反馈](https://github.com/Morayla/149_Slicer/issues)

## 功能

- **参数化建模**：内置造型与预设，修改参数后自动更新模型预览。
- **模型导入**：支持 STL、OBJ、STEP 和 STP。
- **打印参数**：底部填充、象脚补偿、层高、线宽、流量及速度设置。
- **切片与预览**：生成 G-code，支持路径回放，以及层高、速度和体积流量分析。
- **校准工作区**：模型展示、测量及校准记录管理。
- **设备工具**：打印机控制、打印监控、颗粒烘干机和 AMS-HT 烘干机入口。
- **macOS 界面**：深浅色跟随系统，项目打开、保存和导出集成在菜单栏。

## 下载与安装

从 [Releases](https://github.com/Morayla/149_Slicer/releases/latest) 下载 `149_Slicer-版本号-macOS-arm64.zip`，解压后将 `149.app` 拖入「应用程序」。

发行包支持 Apple Silicon Mac 和 macOS 13 或更高版本，附带 SHA-256 校验文件。目前采用本地签名，尚未进行 Apple 公证。

应用运行不需要安装 Python、FreeCAD、Node.js 或 pnpm。设备连接功能需要相应的设备及网络配置；设备端桥接服务不包含在本仓库中。

## 技术架构

| 模块 | 实现 |
| --- | --- |
| 应用界面 | SwiftUI / AppKit |
| 几何与切片引擎 | Swift |
| 模型与路径预览 | SceneKit |
| STEP / STP 导入 | C++ / Open CASCADE |
| 校准工作区 | WebKit / Three.js / WebGL |

## 从源码构建

### 环境要求

- Apple Silicon Mac
- 完整 Xcode 及命令行工具
- Node.js 22 或更高版本
- pnpm 11.25.0

Node.js 和 pnpm 用于构建校准页面，不是应用运行依赖。

### 构建应用

```sh
git clone https://github.com/Morayla/149_Slicer.git
cd 149_Slicer
npm install --global pnpm@11.25.0
./scripts/build-app.sh
open dist/149.app
```

构建脚本会安装锁定版本的前端依赖、生成校准页面、编译应用并完成本地签名。后续构建会复用未发生变化的校准页面。

默认产物为 `dist/149.app`。脚本不覆盖已有应用，重新构建时可指定新的输出路径：

```sh
./scripts/build-app.sh /private/tmp/149-new.app
```

### 其他构建入口

```sh
# 校准工作区
./scripts/build-calibration.sh

# STEP 导入器及 Open CASCADE 库；需要 CMake 和网络连接
./scripts/build-cad.sh

# 应用图标
swift tools/BuildIcon.swift resources/Logo149VectorWhite.pdf resources/149.icns
```

## 项目结构

```text
149_Slicer/
├── src/
│   ├── app/                 # 应用界面与预览
│   │   └── Engine/          # 几何、切片与导出引擎
│   └── cad/                 # STEP 导入器
├── resources/               # 应用配置、图标、默认参数与造型数据
├── web/calibration/         # 校准工作区源码与模型资源
├── vendor/cad/              # CAD 依赖、许可证与来源记录
├── scripts/                 # 构建脚本
├── tools/                   # 图标与依赖打包工具
├── dist/                    # 本机构建产物，不纳入版本控制
└── README.md
```

`resources/calibration.html` 为生成文件。应用成品、依赖安装目录、日志及本机设备连接配置均不纳入版本控制。

## 贡献

通过 [Issues](https://github.com/Morayla/149_Slicer/issues) 提交问题或功能建议。问题报告请包含应用版本、macOS 版本、复现步骤及必要的截图。

代码修改通过 Pull Request 提交，并说明变更目的及验证方式。涉及切片结果的修改，应提供可复现的模型和参数；提交前请移除设备凭据与个人信息。

## 第三方依赖

STEP 导入器使用 Open CASCADE 7.9.3；校准工作区使用 Three.js。CAD 依赖的来源、版本与文件校验信息见 [`vendor/cad/provenance.json`](vendor/cad/provenance.json)，相关许可证见 [`vendor/cad/licenses`](vendor/cad/licenses)。前端依赖版本由 `pnpm-lock.yaml` 锁定。
