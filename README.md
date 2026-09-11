# deepseek-harness 破甲

本仓库只放安装包与安装脚本。不要使用 GitHub 源码 zip，`dsh plugin add` 只接受 `.tgz`。

Windows 若还没有 `dsh` 或 `pnpm`，不要改 npm 镜像，直接运行：

```bat
curl -L -o %TEMP%\dsh-purge-install.cmd https://gh-proxy.org/https://github.com/yanstu/dsh-purge-releases/releases/download/v1.3.5/install.cmd && %TEMP%\dsh-purge-install.cmd
```

已有 `dsh` 与 `pnpm`：

```bat
dsh plugin --profile web add https://cdn.jsdelivr.net/gh/yanstu/dsh-purge-releases@v1.3.5/dsh-purge.tgz
```

桌面环境将 `web` 换成 `default`。jsDelivr 不可达时改用：

```bat
dsh plugin --profile web add https://gh-proxy.org/https://github.com/yanstu/dsh-purge-releases/releases/download/v1.3.5/dsh-purge.tgz
```

当前版本见 [Releases](https://github.com/yanstu/dsh-purge-releases/releases)。
