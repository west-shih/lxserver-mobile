# LXServer API 调研清单

## 歌曲评论（v2.2.0）

源码：`src/server/server.ts` 的 `/api/music/comment` 分支；`src/modules/utils/musicSdk/{kw,kg,tx,wy,mg}/comment.js` 的返回归一化。

`POST /api/music/comment`，沿用普通用户请求头，JSON 为 `{songInfo: 原始平台歌曲信息, type: "hot" 或 "new", page: 从1开始, limit: 20}`。服务端按歌曲 source 调用 getHotComment/getComment，不跨平台合并。返回 `{source, comments, total, page, limit, maxPage}`；评论字段包括 id、text、userName、avatar、timeStr、likedCount、reply。平台字段可能缺失，前端保留空值兼容；只展示文本、现有回复及点赞数，不提供写操作。

服务端不支持该平台方法或上游失败时可能返回 500；客户端显示可重试状态，不把失败当作零评论。页面切换分类、关闭后丢弃过期响应。这里只核对固定基线和夹具，实际部署/平台评论可用性待实测。

## 证据基线

- 上游仓库：https://github.com/XCQ0607/lxserver
- 源码调研基线：v2.2.0（package.json 与同名 Git tag 已核对），commit `13865b82b19fe51219e3e21948c104a50e6fcebc`；用户实际部署 commit 待确认，版本矩阵见 COMPATIBILITY.md。
- 已阅读：`docs/api/reference.md`、`src/server/server.ts`、五平台 `musicSearch.js`。
- 可用测试实例：待确认，真实地址和凭据不要写入版本库。

**已核对源码契约，但尚未使用真实部署完成网络联调。Mock 测试仅验证客户端请求和响应处理。**

## 第一版使用的原生接口

源码依据：[server.ts（固定 commit）](https://github.com/XCQ0607/lxserver/blob/13865b82b19fe51219e3e21948c104a50e6fcebc/src/server/server.ts)。

| 接口 | 契约与客户端行为 |
| --- | --- |
| POST /api/user/login | JSON username/password；成功返回 success/token/username；401 账号密码错误，403 禁用。不调用管理员 /api/login |
| GET /api/user/auth/verify | x-user-token；返回 valid、username 等；valid=false 清理本地会话并回登录页 |
| POST /api/user/logout | x-user-token；服务端删除内存 Session Token；客户端同时清理本地会话并停止播放 |
| GET /api/music/search | name/source/type=song/page/limit=20；读取对象 list 与 hasMore；平台值 kw/kg/tx/wy/mg，分别为酷我/酷狗/QQ/网易/咪咕 |
| POST /api/music/url | x-user-token + x-user-name；JSON songInfo（保留搜索结果原始字段）、quality=所选音质 ID、enableAutoSwitchApiSource=true；响应读取 url 与 type（服务器音质标注） |
| GET /api/music/cache/check | 用户 Token/name；name/singer/source/songmid/songId/quality/exactQuality=1；仅使用 exists=true、非 isCollision、quality 精确匹配的文件；只接受同服务器 /api/music/cache/file/ 地址。旧版 404 或缓存服务失败继续在线解析 |

- 用户 Token 是内存会话，重启或过期后需重新登录；不保存密码做静默重登。
- 搜索 source 不支持 all；聚合搜索由客户端对当前平台分别发起请求，不伪造聚合接口。
- 五个检索平台与自定义音乐解析源不同。服务端必须为用户配置可用源，解析失败时不会模拟播放。
- 图片依照 server.ts 的 getSongCoverUrl 兼容 img/pic/picUrl、meta、album 与 otherSource.meta 字段，空字符串继续回退；个人歌单读取 Album/album/cover/pic/picUrl。无地址或下载失败使用占位图；具体失败歌单的网络原因仍待实测。
- 2026-11-14 真机封面排查：网易 CDN music.126.net 对 Dart 默认 User-Agent 返回 403；同一地址使用 Mozilla/5.0 与网易网页 Referer 返回 200。SongArt 仅对该域名及其子域设置图片请求头，不携带 LXServer 凭据。字段兼容不能解决此 HTTP 拒绝问题。
- 补充复查：Image.network 使用 headers.add，导致 User-Agent 同时含 Dart 与 Mozilla，手机仍返回 403。ArtworkImage 使用独立 HttpClient 清除默认 User-Agent，并通过 headers.set 设置请求头；本地 HTTP 服务测试验证实际收到单一 User-Agent 且图片解码成功。失败项从图片缓存移除，应用重启清除内存图片缓存，无需清理账号数据。
- 客户端保留完整 songInfo，应对不同平台额外字段；跨平台歌曲标识不合并。
- 40 秒请求超时；显式传 limit 避免服务端一次聚合数千条；切平台时忽略旧响应。
- 不自动重试写操作；不向音频 CDN 转发登录 Token；错误内容不直接回显服务端原始正文。
- 音频播放仍需验证重定向、音频请求头、来源限制与失效重取，尚无真实实例验收结论。

## 聚合、收藏、歌单与歌词

仍以同一固定 commit 为依据，新增阅读 `src/server/sources/customSourceHandlers.ts`、
`src/server/sources/userApi.ts`、`src/modules/list/listDataManage.ts`、`src/types/music.d.ts` 和五源 songList 实现。

| 接口 | 客户端处理 |
| --- | --- |
| GET /api/custom-source/list?username=当前用户 | 用户 Token；响应为数组。仅统计 enabled=true 且 status=success 的解析源，合并 supportedSources 并逐源排除 disabledSources |
| GET /api/user/list | 用户 Token/name；读取 loveList、defaultList、userList[].list；显式编辑使用下述全量 POST 契约 |
| GET /api/user/library/artists、/api/user/library/albums | 响应为数组，收藏字段 id/source/name/picUrl，专辑额外 artistName；两者失败不阻断个人歌单 |
| GET /api/music/artistSongs、/api/music/albumSongs | id/source；歌手返回数组，专辑读取 list；读取收藏条目的歌曲 |
| GET /api/music/songList/tags | source；读取 tags 分组下 list 与 sortList；分类和排序 ID 来自服务端，不硬编码 |
| GET /api/music/songList/list | source/tagId/sortId/page；读取 list、total/limit（若有） |
| GET /api/music/songList/search | source/text/page；在线歌单搜索 |
| GET /api/music/songList/detail | source/id/page；分页加载 list，跨页去重，遇空页/重复页停止；info.img / info.pic 为歌单独立封面 |
| GET /api/music/cache/list | 用户 Token/name；success=true、data 数组。按 id、quality、folder(cache/music) 建立服务器文件状态，一次加载供所有可见歌曲复用。下载目录同档优先，接口不可用标记未知，不伪造缓存状态 |
| GET /api/music/lyric | 用户 Token/name；query 携带 source/songmid/name/singer 及可用的 songId/hash/interval/copyrightId/albumId/lrcUrl/mrcUrl/trcUrl；读取 lyric 和可选 tlyric，失败不阻断音频播放 |

歌词依据：固定基线 `src/server/server.ts` GET 分支与 `src/server/music/downloadLyrics.ts`，先读取当前用户的服务端已有歌词，再请求平台，失败时允许读取内嵌歌词。旧 POST 分支直接请求平台，绕过已有歌词。2026-11-14 SM S9180 真实部署诊断：同一 QQ 歌曲 POST 返回 HTTP 500 / `Get lyric failed`，GET 返回 200、3088 字符歌词，含 `_fromLocalCache` 字段；补数字 songId 后 POST 仍失败。安装修复版后，通过真机 PlayerController.loadLyrics 实测加载 75 行同步歌词，loadingLyrics=false、lyricError=null。电脑直连 QQ 返回成功不能证明服务器网络正常。部署 `/js/config.js` 自报 v2.2.0 / `6c6462d`，完整部署 commit 未确认；仅验证本条 GET 契约，不扩大兼容范围。

- 平台可见性依据“支持解析的平台”，不是搜索请求成功率，也不保证每首歌一定可播放。
- 缓存标签与网页 public/music/js/local/server_file_state.js 对齐：标识按 songmid/songId/id 和平台前缀生成，下载目录 music 显示已下载，cache 显示已缓存；均在服务器，不在手机。状态单次并发合并、60 秒复用，账号切换清空，刷新音乐库强制刷新；不逐首逐音质请求，不持久保存文件列表/签名 URL。
- 状态接口成功且明确无可用平台时显示空状态；404、权限错误、网络失败或旧版字段不完整时保留五个平台，标记未知。
- 支持刷新状态，客户端不启用/禁用/上传任何服务端音源。
- 聚合搜索各平台独立分页，轮流合并结果；按平台和歌曲 ID 去重，同歌名跨平台保留。
- 某平台失败保留其他结果，重试时不跳过失败页；切换关键词/平台、退出后忽略旧响应。
- 个人收藏的歌曲保留 meta，并映射 songId、picUrl、albumName、qualitys 与各平台必需字段。
- 服务器本地文件条目可见，但当前不能播放，不将 local 错标为酷我。
- 基础 LRC 支持多时间标签、毫秒、翻译同时间匹配、当前行高亮和点击跳转。逐字歌词、罗马音、时间偏移元信息尚未适配。
- 个人歌单由 `source/sourceListId` 标识关联在线来源（public/music/app.js createItem / handleJumpToOriginalList）；default/love 为不可删除系统列表。手机端跳转到应用内原始在线歌单详情。
- `POST /api/user/list`：普通用户鉴权，与 GET 相同；请求为完整 ListData（defaultList/loveList/userList），响应 `{success:true}`。证据：src/server/server.ts:2665 → listDataManage.restore → createSnapshot；restore 见 src/modules/list/listDataManage.ts。不是单歌单 PATCH，也没有 CAS/版本前置条件。
- 重命名、删除与同步均在操作前重读最新快照，仅修改目标自建歌单 name、移除目标自建歌单或替换目标 list 和非空来源封面 Album，保留其他歌单、字段与元数据；同步完整拉取 songList/detail 各页、按平台歌曲 ID 去重，重复不完整页/失败时中止，不提交部分内容。上限 1000 页，超限中止。写成功后重新读取列表，不做自动写入重试。
- 并发设备在 GET 与 POST 之间的编辑仍可能被覆盖；当前不具备实时推送同步、事务冲突检测。源码基线已核对、Mock 已验证，部署写入行为待真实实例验证。

## 音质契约

- 列表标签依据上游 public/music/app.js 的 getQualityTags：读取歌曲 types/_types、qualitys/_qualitys 及 meta 中对应字段，或显式 quality/type，按 Master、Atmos、Hi-Res、无损、高品质显示最高一档；未知或仅标准不显示高级标签。平台占位条目 isPlatformQuality 不当作具体歌曲音质。标签不是解析成功证明，不触发额外 URL 请求。
- 服务器文件索引可补充具体已存在音质；颜色对照 app.js getSourceTag、public/music/css/theme_variables.css .t-badge-* 和 server_file_state.js：QQ/无损/缓存绿，酷我/Hi-Res 黄，酷狗/高品质/下载蓝，网易红，咪咕粉，Master 紫，Atmos 青。

- 额外依据：`public/music/js/player/quality.js` 的平台可选音质和优先级，以及 `src/server/sources/userApi.ts` 返回的 `{url,type,...}`。
- 请求标识包括 128k、192k、320k、flac、flac24bit、hires、atmos、atmos_plus、master；WAV 仅在歌曲明确标注时提供。
- 平台级可选音质不等于歌曲可用音质。歌曲 types/_types 或 meta.qualitys/_qualitys 标记的 isPlatformQuality 条目不当作实测可用。
- 音质面板分组：具体 metadata、当前 reportedQuality、服务器文件质量为主列表证据；不完整信息中的其余平台档位折叠为“尝试其他音质”。完整新搜索元数据之外的档位不展示，平台明确不支持档位不加入折叠项。展示有标注不等于当前解析源必然可用。
- 默认客户端偏好 flac。新搜索结果包含具体音质字段且不含 isPlatformQuality 占位项时，按不超过偏好的最高已标注档位开始，并跳过未标注档位；无信息或包含占位项时按平台档位尝试。历史歌单无法确认字段完整性，不把仅标注 128k 当上限。
- 手动选择可尝试平台支持但旧歌单未标注的音质。获取失败不把旧音频标为新音质。
- 展示服务器 type，而非只展示请求值；type 缺失/不识别时显示“音质未确认”。已识别 type 与请求不同则拒绝该次资源，先尝试同档其他源，再考虑较低档位。
- 首选失败（解析或加载失败）后，同歌曲、同平台依次尝试较低音质，默认 flac → 320k → 128k；192k 仅在平台可选时插入。高级档位失败先退至 flac，不把空间音频模式作为音质阶梯。401 立即停止，不跨平台换歌。
- 每个档位仍启用服务端自定义解析源重试；成功显示实际档位及降级提示，首选偏好不变。全部失败才报错；手动切换全部失败尝试恢复原音频。
- 用户选择立即保存为本机偏好，即使解析源拒绝也不回写为标准音质；选择面板保持打开，显示请求进度与结果。
- 每档先读服务端已有文件，再读内存链接，最后在线解析。URL 加载失败且 hasMoreSources=true 时，携带失败 sourceId（缺失则 sourceName）到 excludeApiSources，先试同平台其他源。总解析调用最多 4 次，解析恢复调度预算 30 秒，每次 URL 请求最多 10 秒；音频加载耗时不受该解析预算硬取消。
- 歌曲播放记录以服务器、账号、平台歌曲 ID、解析源配置为作用域，并绑定产生记录时的全局首选。成功档位不按时间失效，重播先沿用；URL 过期只重解析该档位。原档位失败才按当前首选重新选档；主动重试清除当前记录，修改全局首选清除旧记录。最多保留 200 首，按最近成功播放淘汰；注销、源配置变化会失效。旧版本缺少首选绑定的记录不直接沿用，下次成功后建立新记录。
- 失败仅内存退避 30 秒，不持久化，也不代表歌曲永久没有该音质。网络/认证/权限错误停止恢复，不写失败记录；无可用平台源时停止在线解析，仍允许检查较低档已有文件。
- 成功历史使用已有安全存储，串行写入；旧版持久失败记录迁移时丢弃。播放地址最多 100 条，仅内存保留 5 分钟（无明确服务端有效期时的保守上限），不落盘；反复重播不无限续期。注销清除记录，刷新发现源顺序、启用、平台或版本变化时失效。
- 音质面板提供“重新尝试首选音质”，清除当前歌曲结果及地址记录，绕过旧音质标注重新尝试；临时手动切换绕过标注，但不清除或回写长期成功档位。缓存不改变首选偏好。降级期间抑制播放器中间加载错误，全部失败后才报错。
- type 是解析源的标注，不是客户端对音频码率/位深的独立检测结果。
- 切换重新解析 URL，保留切换时进度和播放/暂停状态；获取失败继续旧流，加载新流失败尝试恢复旧 URL。恢复失败时显示播放错误。

## 能力清单

| 能力 | 需要确认 | 状态 |
| --- | --- | --- |
| 连接与版本 | 健康检查、版本识别、地址前缀、HTTPS | 待确认 |
| 鉴权 | 登录、验证、登出已核对；实际部署权限待测 | 源码已核对，实例待测 |
| 搜索 | 五平台、关键词、分页已核对；各源实际响应待测 | 源码已核对，实例待测 |
| 播放 | URL 获取已核对；音质、过期、请求头、跳转、Range 待测 | 源码部分核对，实例待测 |
| 歌曲详情 | 封面、歌手、专辑、时长、来源字段 | 待确认 |
| 歌词 | 格式、时间戳、翻译、逐字歌词 | 待确认 |
| 排行榜与歌单 | 入口、分页、详情、可用平台 | 待确认 |
| 用户歌单与收藏 | 查询、创建、修改、删除、排序、权限 | 待确认 |
| 同步 | HTTP/WebSocket 等实际机制、增量、冲突和幂等 | 待确认 |
| 下载 | 音频访问限制、失效重取、断点续传支持 | 待确认 |

## 每个接口的记录模板

```text
能力名称：
证据：服务端版本/commit + 文档链接或源码文件/符号
方法与路径：
鉴权与必要请求头：
参数：类型、是否必填、默认值、约束
成功响应：脱敏示例及字段含义
失败响应：HTTP 状态、业务错误码
分页/限流/超时/重试约束：
是否可安全重试、是否具有副作用：
实测时间与结果：
客户端映射与兼容要求：
```

记录响应示例前移除令牌、签名 URL、个人歌单与其他敏感信息。
服务端不具备的能力明确记录“不支持”，不要用猜测接口补齐。

## 手机缓存与下载（当前实现）

本轮未新增 LXServer 写入接口。手机本地文件优先于服务器已有文件和解析 URL；手动音质/下载按选定档位顺序处理。verify 网络超时为 6 秒；仅网络失败允许恢复已安全保存的会话，鉴权失败仍清除。音频第三方请求不携带 LXServer 登录头。本机范围代理仅监听回环地址，不属于服务器 API。详见 [LOCAL_MEDIA.md](LOCAL_MEDIA.md)。

本机存储淘汰仅修改应用私有文件及索引，不调用 LXServer 删除接口。已核对 v2.2.0 `src/server/music/cacheCleanup.ts`、`fileCache.ts` 的容量/保留期及使用保护；客户端区别及完整机制见 [PLAYBACK_ENGINE.md](PLAYBACK_ENGINE.md)。

下载封面使用歌曲标准化 img 元数据，不猜测新的服务端图片接口；请求图片 CDN 时不添加 LXServer 凭据。敏感鉴权图片 URL 不写索引，可仅保存获取到的本机图片。旧记录只按同平台、同歌曲 ID 从已验证歌单/搜索结果补齐。

播放状态恢复不新增服务器接口；只保存本机歌曲元数据和进度，继续时沿用原生解析/缓存流程。参考固定 v2.2.0 app.js 的 savePlaybackState/restorePlaybackState，客户端暂停恢复及队列窗口区别见 PLAYBACK_ENGINE.md。

- 重命名证据：v2.2.0 public/music/app.js:14211 handleRenameList，仅允许 userList 项、名称 trim 后非空、更新 name 后 pushDataChange。手机端列表与详情共用菜单，系统 love/default 不可重命名；保留来源元数据和歌曲。Mock 验证空白输入不写入、改名后详情标题同步更新。

### 关联歌单封面刷新

- 证据：src/server/server.ts 的 songList/detail 分支直接返回 SDK 详情及 info；tx/songList.js 的活动 getListDetail 将 dirinfo.picurl 映射为 info.img，public/music/app.js 收藏逻辑将 info.img/info.pic 存入 Album。客户端 SongBatch 保留来源封面，完整分页成功后与歌曲一起显式写入 Album；缺失或空白来源封面不清空已有 Album，不把歌曲图片当歌单封面。
- 2026-11-14 Android SM S9180 只读排查：一份 QQ 关联歌单服务端 Album 非空，原歌单详情 info.img 非空，手机请求已有图片返回 200 / image/jpeg；客户端曾保留空 image，重新 GET 私人歌单后恢复并在列表显示。未执行真实 POST，不记录歌单名、ID、图片完整地址或鉴权数据。部署完整 commit 仍未知，结论仅限这组只读接口及图片。
- CollectionScreen 同时订阅 AppController 和 LibraryController，重读后更新封面/标题，无需退出重进。Mock 覆盖只读重载零写入、详情封面即时更新、刷新封面写入与空白响应保留旧图。

## 歌单元数据与完整收藏（v2.2.0）

- 列表/搜索返回的 author/desc/play_count/time 与详情 info 中同名字段用于显示；详情优先，缺失时保留列表值。证据：五平台 songList.js，QQ 活动详情函数映射 dirinfo.host_nick/desc/listennum 到 info；QQ/酷狗列表中的 time 由各自创建/发布时间格式化，不能泛称更新时间。播放量不是唯一听众人数。私人 userList 的原生收藏创建只保证 name/source/sourceListId/Album/locationUpdateTime/list，不假设存在创作者/简介或日期。
- 收藏沿用 public/music/app.js 的 _executeCollectSongList 与 formatSongToLxMusicStandard：完整获取全部页，按平台歌曲标识去重；GET 最新 /api/user/list，按 source + sourceListId 查重；新增 `${source}_${128位随机十六进制}` ID，保存上述原生字段，POST 完整快照，success=true 后重读。取消收藏复用确认删除，可能影响其他设备的这份私人歌单，不删除手机已下载音频。
- librarySong 规范化歌曲 id/meta，QQ 同时保留媒体 mid 与数值 songId，酷狗保留 songId/hash，咪咕保留版权/歌词字段；已有合法 LX 条目保留额外元数据。没有新增服务端接口、管理员鉴权或未经核实的字段写入。
- playlist_prototype_test 覆盖元数据合并、全分页去重、原生身份、重复收藏零额外 POST、分页失败/会话重置零部分写入、保存重读阶段写入锁、收藏按钮确认与选中态。上述写入为 Mock 契约验证，真实部署收藏/取消及多设备可见性待验收。

### 日期字段与收藏跳转边界

- 固定基线网易 `wy/songList.js` 的 filterList 将平台 item.createTime 格式化为列表 time；getListDetail 的 info 只导出 play_count/name/img/desc/author，没有 createTime/time。2026-11-14 Android 当前网易外部歌单的只读 GET/detail 与该字段集合一致；缓存列表有日期，而收藏跳转初始元数据为空。已在当前页以同平台、同歌单 ID 的缓存回填并确认日历日期显示，不记录实际歌单名称、ID或日期。
- DiscoveryController.originalSummary 优先使用同 source + sourceListId 的已加载列表摘要，供“打开原始歌单”及刷新使用；未命中时只保留收藏已有字段，不额外发搜索/平台请求，不虚构日期。QQ 等其他源的 time 可能表示修改/发布日，不能统一当创建日。
- 当前 GET/user/list 的自建记录未返回 createTime/createdAt/create_time/time，locationUpdateTime 为 null。基线 src/types/list.d.ts 的 UserListInfo 及 listDataManage.createUserList 未定义或生成 createTime；locationUpdateTime 不能当创建时间。快照允许保留未知字段，不代表标准接口承诺提供创建日。
- playlist_prototype_test 覆盖同平台缓存日期回填、跨平台同 ID 隔离、未缓存无日期、从收藏打开缺日期的详情后正确展示列表日期。以上修复不改变服务端协议或歌单数据。

### 私人歌曲编辑（v2.2.0）

基线 `src/server/server.ts` 的 GET/POST `/api/user/list` 与 `listDataManage.ts` 的歌曲移除/位置更新支持私人列表内容修改；系统 love/default 的歌曲同样可以修改，系统列表自身仍不可删除/重命名。LibraryController.editSongs 先取最新完整快照，library_edit 按平台限定歌曲身份变更目标，保留其他列表、既有歌曲原始数据及未知字段。复制仅规范化新条目并查重；排序要求最新目标顺序与开始编辑时一致，拒绝过期草稿。删除和草稿排序一起提交；无变化不 POST，明确 success 后发布状态并只读回查。回查失败提示已保存，不重新 POST；旧读请求不能回滚新结果。服务端无 CAS，GET/POST 间仍可能冲突，见 [版本限制](UPSTREAM_LIMITATIONS.md)。library_edit_test 与 collection_editor_test 为 Mock 验证，未执行真实私人歌曲写入。

### 私人歌单列表排序（v2.2.0）

`listDataManage.restore/getListData` 按 userList 数组顺序恢复及导出歌单；`userListsUpdatePosition` 同样通过调整 userLists 数组次序排序。客户端沿用已核对的 GET/POST `/api/user/list`，不新增接口：先读最新快照，要求 userList ID 顺序与拖动开始时一致，并校验新顺序是完整唯一排列，然后仅重排原始歌单对象，保留最新歌曲、元数据、未知字段、love/default 及其他顶层字段，不改写日期。系统列表不在 userList 内，不能仅凭该数组表达与私人歌单的混排；混排改用下述账号显示设置。无变化不写入；保存失败不自动重试，成功后只读回查。没有 CAS，仍有 GET/POST 之间的并发窗口。library_order_test 覆盖上述契约与界面拖动/长按；真实部署顺序写入与其他设备可见性待验收。

### 含系统列表的显示顺序与账号设置（v2.2.0）

- `public/music/app.js` 的 getOrderedFavoriteSidebarItems/persistFavoriteSidebarOrder 使用 `settings.favoriteSidebarOrder` 表达系统项及私人歌单的混排，先存浏览器 lx_settings，saveAccountSettingsToFile 开启时调用 pushSettingsToServer；私人子序列另经 persistUserListOrderFromSidebar 保存歌单。网页本地已缓存的设置不会因手机写入而实时更新，其读取服务端设置仍受网页自己的同步逻辑控制。
- `src/server/server.ts` GET/POST `/api/user/settings` 使用普通用户 x-user-name/token 鉴权，GET 返回原始设置对象，无文件则 `{}`；POST 完整替换 userSettingsJSON 并返回 `{success:true}`。公开受限用户写入另有管理员限制与字段白名单，客户端不索要管理员权限、不绕过 403。该接口有缓存/调度等已知设置副作用，故客户端先 GET 并保留所有其他字段，仅修改 favoriteSidebarOrder，不更改 saveAccountSettingsToFile。
- 手机读取账号显示顺序，忽略当前不存在的项，未记录的新歌单追加显示。拖动前并行 GET 最新歌单与设置，核对当前可见顺序及唯一完整排列；先按需保存 userList 子序列，再按需保存混排设置。保留网页歌手/专辑/公开收藏等当前手机列表不展示的 ID 及其相对位置，不将 love/default 塞入 userList。成功后回读；失败不自动重发写入。两个整件替换接口没有 CAS/事务，第二步失败会提示私人排序已保存但显示排序未确认，而非宣称全部失败或已原子同步。
- library_order_test 为 Mock 证据，覆盖系统项移动、重新加载恢复、最新账号字段和隐藏 ID 保留、过期显示顺序拒绝、部分保存提示、回查失败不重发。真实部署设置写入与网页接收仍待验收。

### 客户端简单歌单聚合与平台选择

固定 v2.2.0 `server.ts` 的 GET `/api/music/songList/list`、`search`、`tags` 都按 source 调用单平台 SDK，没有服务端 all 参数。客户端聚合并行调用原有单平台接口，不发 source=all；推荐先读取 tags.sortList 的首个排序 ID（与原单平台实现相同，空列表沿用 hot），控制器生命周期内复用；搜索只使用 source/text/page。每平台独立游标，以平台+歌单 ID 区分，重复/空页停止继续拉取；部分失败可重试且不清空其他平台结果。源信息按原 source 传入详情，不把平台同 ID 歌单互相覆盖。没有跨平台分类协议，也不保证统一热度排序。

平台标签数量不另加接口，仍来自既有音源状态解析；只在本机保存两页的 platform ID/all，启动恢复后由原可用平台检查纠正。偏好缺失、损坏或未知 ID 默认网易；已保存 all 继续聚合，已禁用平台选择回聚合，状态接口失败仍保留平台为未知。discovery_aggregate_test 与 platform_selection_test 为 Mock/组件证据。Android SM S9180 profile 版已只读确认五个平台的推荐结果在同一列表交错展示及来源标签，不保存实际歌单名/ID；真实聚合搜索、后续翻页、失败恢复与偏好跨启动仍待真机复核。

### 总数、原生页与展示分页（v2.2.0）

- `server.ts` 的 `/api/music/search` 歌曲分支返回 list/total/allPage/pageSize/fetchedPages/stopReason/hasMore/source。客户端显式传 limit=20，使用单原生页模式；SDK 的实际 pageSize 可能受自身上限约束。total/allPage 是平台自报值，服务端源码明确提示页数墙、重复页及预算限制，不能解释为全部可取得。客户端保留 total/pageSize，以用户设置数量重新计算展示页数，不直接把原生 allPage 当展示页数。
- `/api/music/songList/list`、`search`、`detail` 沿用单平台源，列表/搜索的 total/limit 用于展示总数及原生页映射，详情 total 经 SongBatch 保留。缺少总数且仍有后续时只显示“第 N 页”；全部已加载或私人快照可使用实际条数。不存在 source=all 或新的服务端分页接口。
- 聚合固定连续，不计算跨平台总页数。单平台且打开分页时，PageWindow 记录已读原生页，按展示窗口读取相交的缺失原生页（例：20 条原生页，跳到第 50 个 20 条展示页仅请求原生第 50 页）。已有缓存仍可回看，原生请求大小不因展示设置改变，账号/查询切换使旧响应失效。总数缺失时不猜任意远端页码，只对已加载范围开放跳页。
- 请求失败、空页或全页重复不跳空白页、不自动循环重试；错误不触发写入。歌曲队列保留已加载歌曲，跳页不自动播放、不修改私人歌单。外部详情仍复用已有完整批次读取/去重逻辑；未读部分只在用户明确翻页/跳页时继续读取。
- `real_pagination_modal_test` 覆盖 total/pageSize 解析、远端直跳及跨批次窗口、缓存保留、聚合无分页、未知总数不伪造分母、空/重复页、三处跳页面板、输入/滚轮/取消与键盘布局。这些为 Mock/组件证据；真实平台总数的准确性不作保证。
