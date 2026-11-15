# 当前 LXServer 基线能力限制

此处记录服务端契约的限制，不把客户端尚未实现或可通过现有接口实现的功能归为“不支持”。固定基线为 **LXServer v2.2.0**，commit `13865b82b19fe51219e3e21948c104a50e6fcebc`；版本/tag/部署差异见 [COMPATIBILITY.md](COMPATIBILITY.md)，接口和实测证据统一见 [API.md](API.md)。用户部署完整 commit 未确认，不扩大其他版本结论。

| 编号 | 当前不能保证的能力 | 依据与客户端处理 |
| --- | --- | --- |
| U001 | 仅通过网易原歌单详情稳定取得创建时间 | `wy/songList.js` 的列表 filterList 会将平台 createTime 转为 time，但 getListDetail 的 info 不导出日期。实际部署只读响应同样缺少 time/createTime。客户端可按同平台、同原 ID 复用已加载列表摘要；没有列表缓存时保持缺省，不伪造日期。这不是原平台没有创建日期，也不是所有入口都无法显示。 |
| U002 | 查询自建歌单的标准创建时间、追溯早期创建日期 | `src/types/list.d.ts` 的 UserListInfo 与 `listDataManage.createUserList` 未定义/生成 createTime。当前私人记录无 createTime/createdAt/create_time/time，locationUpdateTime 为 null；后者不能冒充创建时间。客户端不使用当前时间、收藏时间或随机 ID 推算历史日期。快照能保留自定义字段不代表标准接口承诺提供它。 |
| U003 | 跨设备原子修改歌单、避免 GET 与 POST 间的写入冲突 | `/api/user/list` POST 是整份 restore，没有 revision/CAS/If-Match。客户端先读最新快照、保留其他列表与未知字段；排序校验编辑前顺序，旧读请求不能回滚新操作，显式删除需确认且不自动重试写入。这些措施仍不能消除 GET/POST 间另一设备写入的竞态。歌单数组与账号 favoriteSidebarOrder 分属两个整件替换接口，混排双写也无事务；客户端明确提示部分保存。 |
| U004 | 修改网易/QQ 等原平台的公共歌单内容 | 已核对的 LXServer songList 接口只读取原平台列表/详情，没有原平台账号授权的歌曲删除/排序接口。可编辑的是 LXServer 用户自己的系统列表和个人歌单副本。外部原歌单只能选择、下一首播放、收藏到私人歌单或下载；删除与拖动排序在“我的歌单”副本中进行。 |

QQ 歌手专辑列表还有日期映射缺陷：固定基线 tx/singer.js.filterAlbumList 只取 pub_time，但 2026-11-15 电脑直连公开 QQ GetAlbumList 返回的是 publishDate，基线转换后 publishTime 为空。专辑搜索是另一条字段映射，因此可以有日期。需要修正服务端映射；客户端不能从空字段恢复，亦不逐张补查详情。具体只读实测与版本范围见 API.md；未修改或验证用户部署的服务端。

## 可以使用现有接口实现的部分

私人歌单的歌曲添加、移除及顺序可以通过最新 `/api/user/list` 快照修改后完整保存，包括 love/default 的歌曲内容；系统列表自身仍不可删除或重命名。来源歌单副本的修改不会回写网易/QQ 原歌单，之后主动刷新来源可能重新加入已删除歌曲或覆盖个人排序。

更新上游基线后，应重新核对这些限制；未核对前不得直接把表中项目标为已解除。此文不保存个人歌单名称、ID、图片地址、令牌或密码。
