# 用 Charles 获取自己的电表配置

本指南以 macOS 微信中的南网小程序为例。只适用于你有权访问的账户和设备。接口来自小程序实际请求，不是已确认授权的开放 API；使用前请核对服务方现行协议。仅体验界面可直接使用 `--demo`，无需抓包。

## 1. 准备 Charles

从 [Charles 官网](https://www.charlesproxy.com/) 获取软件。Charles 是独立的第三方调试工具，有自己的许可与试用安排，不随本项目提供。

让目标应用流量经过 Charles：在 Charles 的 Proxy 菜单检查 macOS 系统代理设置。Charles 支持自动配置系统代理，但不代表每个版本的微信都会采用它。[官方系统代理说明](https://www.charlesproxy.com/documentation/configuration/browser-and-system-configuration/)

## 2. 仅为目标域启用 HTTPS 调试

在 Charles 的 SSL Proxying 设置中添加主机 `weixin.csg.cn`、端口 `443`。也可在 Structure 列表中右键该主机开启 SSL Proxying。不要使用匹配所有域名的 `*` 规则。[官方 SSL Proxying 说明](https://www.charlesproxy.com/documentation/proxying/ssl-proxying/)

若需要查看 HTTPS 内容，Charles 官方 macOS 流程是在 Help → SSL Proxying → Install Charles Root Certificate 安装本次 Charles 生成的根证书，然后在“钥匙串访问”中检查该证书并设置信任。信任此证书会允许 Charles 解密经过它代理的目标 HTTPS 流量；不要安装他人发来的根证书，也不要共享自己的证书私钥。[官方证书说明](https://www.charlesproxy.com/documentation/using-charles/ssl-certificates/)

只在理解并接受上述信任变化时操作。若应用拒绝代理或有证书固定机制，本指南不提供绕过方法；可停止并使用演示模式。

## 3. 找到一次成功的月度用电查询

在自己的南网小程序里登录并查询月度/每日用电，在 Charles 中筛选：

```text
Host: weixin.csg.cn
Path: /ucs/ma/wx-api/charge/queryElectricityCalendar
Method: POST
```

请求名称可能随着小程序更新变化。先检查响应是否成功、有当前电表的用电数据；登录失败或绑定错误的请求不能作为可靠配置来源。当前解析器接受 `sta` 为 `00` 或 `0` 的成功响应。

## 4. 把四个字段填入 App

| App 字段 | 从哪里复制 | 注意 |
| --- | --- | --- |
| x-auth-token | Request Headers → x-auth-token | 只复制值，不复制头名称或引号 |
| 区域代码 | 请求 JSON → areaCode | 深圳常见为 090000，以自己的请求为准 |
| 用电客户 ID | 请求 JSON → eleCustId | 重新登录后可能改变 |
| 计量点 ID | 请求 JSON → meteringPointId | 需与同次请求的客户 ID 配套 |

示意请求体（占位符不可直接查询）：

```json
{
  "areaCode": "090000",
  "eleCustId": "YOUR_CUSTOMER_ID",
  "meteringPointId": "YOUR_METERING_POINT_ID",
  "yearMonth": "YYYYMM"
}
```

App 自动填写查询月份，并把 Token 同时用于 `x-auth-token` 和 `CAMSID` Cookie。无需粘贴整个 curl 命令，也无需填写 Host、User-Agent 或 Cookie。

**一定使用同一次成功请求里的 Token 与三个电表参数。** 到“设置 → 连接电表”粘贴并“保存并刷新”，确认显示查询成功。公开求助只写错误类型，别发送这些字段的真实值。

![连接设置示例](screenshots/settings-connection.png)

## 5. 完成后恢复环境

停止 Charles 录制，关闭为本次调试开启的系统代理与 SSL Proxying 规则；若不再需要 HTTPS 调试，在钥匙串中移除本次安装的 Charles 根证书或撤销信任。删除不再需要的本地会话文件，避免长期保存登录凭证。

以后正常运行 szElectricityMeter 不需要 Charles 常驻，也不需要保留抓包代理。

## 排错

| 现象 | 处理 |
| --- | --- |
| 只看到 CONNECT，看不到 JSON | 核对目标域 SSL Proxying、代理与证书配置；不保证所有微信版本可用 |
| Charles 完全没有目标请求 | 确认正在录制，重新在小程序触发查询；应用可能不走系统代理 |
| 您尚未登录 / Token 失效 | 在小程序重新登录，重新取得同一次成功请求的配置 |
| 请确认绑定 id 是否正确 | 更新 eleCustId，并核对 meteringPointId；仅更新 Token 可能无效 |
| 保存成功但查询失败 | 保存只是本机操作，以“连接验证”的请求结果为准 |
| 暂无当日数据 | 电量按日发布，等待数据更新，不要用高频轮询尝试补齐 |

不提供账号代查、Token 共享、自动续期、验证码规避或突破访问限制的方法。

[返回首页](../README.md)
