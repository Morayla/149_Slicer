# 149_Slicer

面向颗粒挤出式 3D 打印的原生 macOS 建模与切片工具。参数化造型、打印路径生成和设备工具在同一应用内完成；测量与校准由独立的 **149 Calibration** 提供。

**macOS 13+ · Apple Silicon · 简体中文 / English**

[下载](https://github.com/Morayla/149_Slicer/releases/latest) · [版本记录](https://github.com/Morayla/149_Slicer/releases) · [问题反馈](https://github.com/Morayla/149_Slicer/issues)

## 149 Slicer

- **参数化建模**：内置造型与预设，修改参数后自动更新模型。
- **模型导入**：STL、OBJ、STEP 和 STP。
- **打印参数**：底部填充、象脚补偿、层高、线宽、流量和速度。
- **切片预览**：保留实际料道形状和打印纹路，支持路径回放及角色、流量、层高、速度和透视显示。
- **设备工具**：打印机控制、打印监控、颗粒烘干机和 AMS-HT 烘干机。
- **项目管理**：通过 macOS 菜单栏打开、保存项目及导出打印文件。

## 149 Calibration

独立运行的原生测量工具，不需要启动切片应用。

- 完整装置 CAD 场景，提供素模、线稿和 X 光显示。
- 样件测量演示、扫描设备连接、实时读数和相机画面。
- 测量记录的保存、回放、筛选及 CSV 导出。
- 根据测量结果生成补偿预设，导出后可在 Slicer 中导入。
- 参数与结果侧栏平滑展开和收起，并遵循系统“减少动态效果”设置。

两个应用均提供语言和三维预览画质设置，深浅色跟随系统。语言更改在重新打开对应应用后生效；“流畅”画质只降低边缘采样，保留完整几何。

## 下载与安装

在 [Releases](https://github.com/Morayla/149_Slicer/releases/latest) 下载对应应用：

| 文件 | 内容 |
| --- | --- |
| `149_Slicer-版本号-macOS-arm64.zip` | 建模、切片与打印设备工具 |
| `149_Calibration-版本号-macOS-arm64.zip` | 独立测量与校准工具 |
| `SHA256SUMS.txt` | 下载文件校验值 |

解压后将应用移入“应用程序”目录。发行包支持 Apple Silicon Mac 和 macOS 13 或更高版本；目前采用本地签名，尚未进行 Apple 公证。

使用拓竹机型导出打印包时，还需安装 Bambu Studio，以生成对应的官方启动和结束流程。

## 技术架构

| 模块 | 实现 |
| --- | --- |
| 界面与窗口 | SwiftUI / AppKit |
| 几何与切片引擎 | Swift |
| 三维预览 | SceneKit，显式使用 Metal 后端 |
| 校准与测量图表 | Swift / Swift Charts |
| STEP / STP 导入 | C++ / Open CASCADE |

校准 CAD 网格在构建时转换为压缩的 SceneKit 资源，运行时直接载入。静态预览按需渲染。打印机控制窗口使用 WebKit 显示设备自身的网页。

## 从源码构建

需要 Apple Silicon Mac、完整 Xcode 及命令行工具。应用和资源构建无需 Python、Node.js 或 JavaScript 运行时。

```sh
git clone https://github.com/Morayla/149_Slicer.git
cd 149_Slicer

# 切片应用
./scripts/build-app.sh
open dist/149.app

# 独立校准应用
./scripts/build-calibration.sh
open "dist/149 Calibration.app"
```

脚本不会覆盖已有应用。再次构建时指定新的输出路径：

```sh
./scripts/build-app.sh /private/tmp/149-new.app
./scripts/build-calibration.sh "/private/tmp/149 Calibration-new.app"
```

校准构建会自动生成或更新 CAD 场景资源，切片应用不包含这些资源。其他构建入口：

```sh
# 单独编译校准 CAD 资源
./scripts/build-calibration-assets.sh

# 重建 STEP 导入器与 Open CASCADE 库；需要 CMake 和网络连接
./scripts/build-cad.sh

# 应用图标
swift tools/BuildIcon.swift resources/Logo149VectorWhite.pdf resources/149.icns
```

Swift 格式配置位于 `.swift-format`。

## 项目结构

```text
149_Slicer/
├── src/
│   ├── slicer/              # 切片应用、参数界面与三维预览
│   │   └── Engine/          # 几何、切片与导出引擎
│   ├── calibration/         # 独立校准应用、测量与装置渲染
│   ├── shared/              # 设置、界面样式、翻译与补偿交换格式
│   └── cad/                 # STEP 导入器
├── resources/
│   ├── definitions/         # 默认参数、材料及造型数据
│   ├── calibration/         # 校准应用配置与生成的场景资源
│   └── en.lproj/            # 英文翻译
├── assets/calibration/      # 完整装置 CAD 网格与机构数据
├── vendor/cad/              # CAD 依赖、许可证与来源记录
├── scripts/                 # 构建入口
├── tools/                   # 资源编译与依赖打包工具
├── dist/                    # 本机构建产物，不纳入版本控制
└── README.md
```

生成的场景资源、应用成品、日志和本机设备连接配置不纳入版本控制。两个应用通过补偿预设文件交换数据，分别保存工作区状态。
