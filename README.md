# deepseek-harness 破甲

本仓库只放安装包，供 `dsh plugin add` 下载。源码不在这里。

网页环境：

```sh
dsh plugin --profile web add https://github.com/yanstu/dsh-purge-releases/releases/latest/download/dsh-purge.tgz
```

桌面环境：

```sh
dsh plugin --profile default add https://github.com/yanstu/dsh-purge-releases/releases/latest/download/dsh-purge.tgz
```

同时使用网页与桌面端时，两条命令均需执行。装完后完整重启：网页端停止 `dsh web` 再启动；桌面端从托盘退出后重新打开。

当前版本见 [Releases](https://github.com/yanstu/dsh-purge-releases/releases)。
