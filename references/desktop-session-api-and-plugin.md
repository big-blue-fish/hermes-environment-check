---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# Desktop 会话 REST API 语义 & 桌面插件开发要点

实测环境：Hermes CN Desktop 0.20.0-cn.5，dashboard 后端 127.0.0.1:9120。

## 会话列表 API（/api/sessions）

- **认证**：`/api/*` 业务端点需要 dashboard 的内部会话认证（由桌面 shell 注入，随 dashboard 进程重启自动轮换）。该认证机制属厂商内部实现，本文档不公开细节；插件页面与 dashboard 同源，同源 fetch 会自动携带认证。收到 401 说明认证已轮换，重试即可。
- **归档过滤**：`GET /api/sessions?archived=include|only|exclude`（默认 exclude）。`include` = 全部（含归档），`only` = 只归档。
- **归档/恢复**：`PATCH /api/sessions/{id}` body `{"archived": true|false}` → `{"ok":true,...}`。归档后列表 API 不再返回（exclude 默认），但 analytics 统计不过滤 archived —— 归档 = 列表隐藏 + 数据保留，两全其美。
- **⚠️ DELETE /api/sessions/{id} 是永久删除**（实测 `{"ok":true}` 后 GET 变 Session not found，sessions 行直接没了）。**禁止对真实会话调用**。误删恢复：回填会话无 messages 时，从 desktop-ui.sqlite 的 turn_stats 重新聚合 INSERT 回 sessions 表即可（值可查备份/校准记录）。
- 会话详情 `GET /api/sessions/{id}`、消息 `GET /api/sessions/{id}/messages`。

## 桌面插件（desktop-plugins）开发要点

- 位置：`$HERMES_HOME/desktop-plugins/<id>/plugin.js`（目录名 == 插件 id）。桌面 app 监视该目录，保存即热重载；`touch plugin.js` 可触发。应用内 Ctrl+K → "Reload desktop plugins" 是渲染进程动作。
- 纯 ESM、不编译：UI 用 `jsx()/jsxs()`（react/jsx-runtime），只可 import `@hermes/plugin-sdk`、`react`、`react/jsx-runtime`。
- 数据获取：页面与 dashboard 同源时**直接 fetch 相对路径** `/api/sessions?...`（同源请求自动携带会话认证，无需手动处理）；`host.request(method, params)` 是 gateway JSON-RPC（session.info 等）。
- 注册 pane：`ctx.register({ id, area: 'panes', title, data: { placement: 'left', width }, render })`。
- 样式：只用主题变量（`text-(--ui-text-secondary)` 等），禁止硬编码颜色。
- 插件加载失败 app 弹 toast 报错名；验证「全部会话」面板：`references` 外先确认 UI 出现。

## 会话列表 UI 现状（0.20.0-cn.5）

- 桌面客户端会话列表默认只显示未归档会话，**UI 无「查看归档」入口**（dashboard SessionsPage 也只有归档统计 + 清理旧归档，无查看/恢复）。归档会话只能通过 API（archived=include）或 all-sessions 插件查看。
- 会话列表数据来自 state.db sessions 表；归档标记写两处：state.db `sessions.archived` + desktop-ui.sqlite `session_ui_state.archived`。
