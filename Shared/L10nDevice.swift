//
//  L10nDevice.swift
//  iPhoneUse
//
//  English copy for the VPN / pairing / DDI screens and device errors shown to the owner.
//

import Foundation

enum L10nDevice {
    static let table: [String: String] = [
        // Connection
        "启动中": "Starting",
        "请在设置中导入配对文件。": "Import a pairing file in Settings.",
        "内置 VPN": "Built-in VPN",
        "正在启动 VPN…": "Starting the VPN…",
        "内置 VPN 不可用（%@），已切换到 LocalDevVPN。\n": "Built-in VPN unavailable (%@); switched to LocalDevVPN.\n",
        "隧道": "Tunnel",
        "正在连接这台 iPhone…": "Connecting to this iPhone…",
        "正在关闭蜂窝数据…": "Turning off cellular data…",
        "当前为蜂窝数据：请关闭蜂窝数据后再连接，或接入 Wi-Fi。": "Currently on cellular data: turn cellular data off before connecting, or join Wi-Fi.",
        "无法连接这台 iPhone。请从 App Store 安装 LocalDevVPN，打开它，然后点重新连接。": "Couldn't reach this iPhone. Install LocalDevVPN from the App Store, open it, then tap Reconnect.",
        "下载开发者磁盘映像": "Download developer disk image",
        "正在下载开发者磁盘映像…": "Downloading the developer disk image…",
        "挂载开发者磁盘映像": "Mount developer disk image",
        "正在挂载开发者磁盘映像…": "Mounting the developer disk image…",
        "配对文件无效或已过期，请在设置中导入新的配对文件。": "The pairing file is invalid or expired; import a new one in Settings.",
        "[%@] %@/%@: %@\n目标：%@": "[%@] %@/%@: %@\nTarget: %@",
        "环回 VPN 未能连接（状态 %@）。Wi-Fi 是否已打开？": "The loopback VPN couldn't connect (status %@). Is Wi-Fi on?",

        // DeviceSession
        "尚未尝试": "Not tried yet",
        "回退": "fallback",
        "未找到配对文件。": "No pairing file found.",
        "读取配对文件失败": "Couldn't read the pairing file",
        "读取配对文件失败。": "Couldn't read the pairing file.",
        "创建隧道失败 [tcp: %@]": "Couldn't create the tunnel [tcp: %@]",
        "隧道创建失败：句柄无效。": "Tunnel creation failed: invalid handle.",
        "等待隧道连接超时": "Timed out waiting for the tunnel to connect",

        // DeviceSession+Services
        "%@ 为空": "%@ is empty",
        "读取 %@ 失败：%@": "Couldn't read %@: %@",
        "lockdownd 未返回 %@": "lockdownd returned no %@",
        "无法解析 %@": "Couldn't parse %@",
        "无法连接安装代理服务": "Couldn't reach the installation proxy",
        "安装代理客户端未能创建": "The installation proxy client couldn't be created",
        "获取已安装 App 列表失败": "Couldn't fetch the installed app list",
        "未知": "Unknown",
        "隧道未连接": "Tunnel not connected",
        "查询已安装的 DDI cryptex 失败": "Couldn't query the installed DDI cryptex",
        "无法连接映像挂载服务": "Couldn't reach the image mounter",
        "映像挂载客户端未能创建": "The image mounter client couldn't be created",
        "获取已挂载设备失败": "Couldn't list the mounted images",
        "加载 DDI cryptex 资源失败": "Couldn't load the DDI cryptex assets",
        "DDI cryptex 资源未能加载": "The DDI cryptex assets couldn't be loaded",
        "安装 DDI cryptex 失败": "Couldn't install the DDI cryptex",
        "开发者磁盘映像": "Developer disk image",
        "开发者磁盘映像信任缓存": "Developer disk image trust cache",
        "开发者磁盘映像清单": "Developer disk image manifest",
        "无法连接 lockdownd": "Couldn't reach lockdownd",
        "lockdownd 客户端未能创建": "The lockdownd client couldn't be created",
        "查询 UniqueChipID 失败": "Couldn't read UniqueChipID",
        "挂载个性化 DDI 失败": "Couldn't mount the personalized DDI",
        "截屏失败": "Screenshot failed",
        "截屏结果为空": "The screenshot came back empty",
        "触摸失败": "Touch failed",
        "长按失败": "Long press failed",
        "返回主屏失败": "Couldn't go to the Home screen",
        "输入失败": "Typing failed",
        "无法打开 AppService": "Couldn't open AppService",
        "AppService 客户端未能创建": "The AppService client couldn't be created",
        "启动 %@ 失败": "Couldn't launch %@",

        // DeveloperDiskImageService
        "ghfast.top 镜像": "ghfast.top mirror",
        "gh-proxy 镜像": "gh-proxy mirror",
        "镜像源": "mirror",
        "响应无效": "bad response",
        "地址无效": "bad URL",
        "超时": "timed out",
        "连不上": "can't reach host",
        "连接中断": "connection lost",
        "没有网络": "no network",
        "TLS 失败": "TLS failed",
        "构建清单": "Build manifest",
        "映像": "Image",
        "信任缓存": "Trust cache",
        "Cryptex 信息": "Cryptex info",
        "根哈希": "Root hash",
        "下载地址无效：%@": "Invalid download URL: %@",
        "%@：%@": "%@: %@",
        "DDI 服务器返回了无效的响应。": "The DDI server returned an invalid response.",
        "DDI 服务器返回了 HTTP %@。": "The DDI server returned HTTP %@.",

        // DDIDownloadCenter
        "剩余时间未知": "Time remaining unknown",
        "马上完成": "Almost done",
        "还剩 %@ 秒": "%@s left",
        "还剩 %@ 分 %@ 秒": "%@m %@s left",
    ]
}
