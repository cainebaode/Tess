# Tess 本机卸载与历史应用清理

2026-10-25。用户要求移除本机当前和历史 Tess，再自行重新下载安装；原因是系统应用搜索仍显示旧图标。

- 核对当前 `/Applications/Tess.app` 为 0.2.0 build 25；当前未运行 Tess，没有 Tess DMG 挂载。
- 共定位 37 个 `life.baode.tess` 或其检查／预览标识的应用包：1 个已安装应用及 36 个项目构建、历史归档、暂存、旧交付与检查副本。先移入系统废纸篓，但系统继续重新登记这些副本；随后按用户全部移除应用的要求，仅删除本轮定位的 37 个 Tess 应用构建包，并清理失效注册。没有清空或删除其他废纸篓内容。源码、正式 DMG 和运行数据备份保留。
- 系统仍登记了部分旧目录和曾挂载的 `/Volumes/Tess/Tess.app`；按 Tess 标识注销原路径及移入废纸篓后的路径，清除两个失效构建软链接，并使用系统注册库垃圾回收移除失效记录。完成后 Spotlight 文件索引查询为零。Launch Services 仍保留 33 条已删除应用的历史缓存，均标记为 trash / launch-disabled 且磁盘节点不存在；没有可启动的 Tess 记录。不为清除无效历史缓存而重置所有应用的系统注册库。
- 运行数据 `/Users/caine/Library/Application Support/Tess` 已移至 `.build/history/uninstalled-userdata/20261025-clean-reinstall/Application Support/Tess`，目录限制为本用户访问。新安装不会直接读取此备份。没有读取或改动 Keychain 的 API 密钥。
- 没有其他匹配 Tess 的偏好、缓存、WebKit、保存状态或启动代理目录。`com.cc.Tessera` 是不同应用，保留。
- 尝试定向重置 `life.baode.tess` 的系统权限时，`tccutil` 返回未找到 Bundle ID（-10814）；未修改系统权限数据库，也没有重置其他应用权限。临时识别用副本已一并移除，最终没有可启动的应用注册记录。重新安装后系统是否再次询问各权限需实际查看。
- 桌面搜索界面的自动操作响应异常缓慢；卸载结论以实际文件、进程、挂载和系统索引检查为依据。

源码、品牌资源、正式 DMG、GitHub 源码与 Releases、官网均保留；不自动重新安装。`.xcarchive` 内的应用包也已移除，历史归档不再能直接导出 App，完整正式包仍可从 Releases 获取。

完整移除清单和每个原位置／移除过程、数据备份与技术检查保存在本机 `evidence/20261025-tess-uninstall/`，不上传公开源码仓库。当前状态为“未安装，等待用户自行下载安装”，不能沿用旧安装成功结论。
