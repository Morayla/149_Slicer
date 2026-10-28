# 149 Slicer

面向大线宽颗粒打印的 macOS 建模与切片应用。当前版本：**0.40.2（132）**。

- 参数化造型与实时模型预览
- 底部填充、象脚补偿、材料与打印参数
- STL / OBJ / STEP / STP 导入
- G-code 生成、路径回放与导出
- 校准工作区、打印机控制、打印监控及烘干设备入口

界面为中文，深浅色跟随系统。主界面使用 SwiftUI，几何和切片引擎使用 Swift；模型预览使用 SceneKit，校准页面使用 WebKit / WebGL。应用运行不依赖 Python 或 FreeCAD。

## 目录结构

```text
149-slicer/
├── src/
│   ├── app/                 # SwiftUI 界面与 SceneKit 预览
│   │   └── Engine/          # Swift 几何、切片和导出引擎
│   └── cad/                 # 原生 STEP 导入器 C++ 源码
├── resources/               # Info.plist、图标、默认参数和造型数据
├── web/
│   └── calibration/         # 校准工作区源码、模型数据和依赖锁定文件
├── vendor/
│   └── cad/                 # STEP 导入器、Open CASCADE 库、许可证和校验信息
├── scripts/                 # 应用、校准页面和 CAD 构建入口
├── tools/                   # 图标生成和 CAD 打包工具
├── dist/                    # 本机构建产物，不提交到 Git
└── README.md
```

`resources/calibration.html` 是由校准源码生成的页面，不提交到 Git。构建脚本会在文件缺失或源码更新时重新生成。

## 构建与运行

需要 Apple Silicon Mac、完整 Xcode，以及 Node.js 22 或更高版本。生成的应用支持 macOS 13 或更高版本。

首次准备校准页面的构建工具：

```sh
npm install --global pnpm@11.25.0
```

在项目根目录构建：

```sh
./scripts/build-app.sh
open dist/149.app
```

脚本默认输出到 `dist/149.app`，采用本地签名。输出路径必须尚不存在，避免覆盖正在使用的应用。可以指定其他输出位置：

```sh
./scripts/build-app.sh /private/tmp/149-new.app
```

第一次从 GitHub 克隆后，脚本会通过锁定文件安装校准页面的依赖并生成页面；后续仅修改 Swift 源码时会复用已有页面。Node.js 与 pnpm 仅用于开发，不是应用运行依赖。

## 常用开发入口

```sh
# 单独重建校准工作区
./scripts/build-calibration.sh

# 重建原生 STEP 导入器及 Open CASCADE 库（需要 CMake 和网络）
./scripts/build-cad.sh

# 从矢量标志重建应用图标
swift tools/BuildIcon.swift resources/Logo149VectorWhite.pdf resources/149.icns
```

CAD 构建使用固定的 Open CASCADE 7.9.3 源码并校验下载内容。预编译依赖、来源及文件校验值位于 `vendor/cad/`，对应许可证位于 `vendor/cad/licenses/`。

## 使用流程

1. 在「造型」页设置外形，或从「文件」菜单导入模型；右侧预览自动更新。
2. 在「底部」「补偿」「打印」页调整相应参数。象脚补偿独立显示。
3. 点击「切片」检查打印路径、用料和预计时间，再导出或发送。

选择预设会立即应用；只有明确保存才更新已存预设。项目打开、保存和导出统一放在系统菜单栏。顶部图标分别打开打印机控制、打印监控、颗粒烘干机及 AMS-HT 烘干机。

校准工作区首次打开会加载模型数据并显示进度。设备连接配置和凭据保存在用户本机的应用支持目录中，不放入仓库。设备端桥接服务不包含在此工程内。

## 协作

仓库协作者接受 GitHub 邀请后，可以克隆、拉取和推送。建议每项修改使用独立分支，通过 Pull Request 合并到 `main`：

```sh
git pull --ff-only
git switch -c feature/my-change
# 修改代码并构建验证
git add .
git commit -m "Describe the change"
git push -u origin feature/my-change
```

应用成品、生成的校准页面、依赖安装目录、日志和本机连接配置已加入 `.gitignore`。不要将设备凭据或个人打印文件提交到仓库。
