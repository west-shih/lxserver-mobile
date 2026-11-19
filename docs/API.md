# LXServer API 调研清单

## 歌手与专辑（R028，v2.2.0）

头像证据：固定基线 `wy/extendSearch.js:handleSingerResult` 返回 `picUrl`；`wy/extendDetail.js:getArtistDetail` 返回 `avatar`，依次优先 `data.user.avatarUrl`、`artist.avatar`、`artist.cover`、`artist.picUrl`。两者不保证同一构图，客户端均为居中 cover 裁切。网易歌手卡片通过既有 `GET /api/music/artistDetail?source=wy&id=…` 补取详情头像，会话内串行去重、最多缓存 100 项，失败保留原图；不写回收藏。只读基线脚本已核对 v2.2.0 / 13865b82b19fe51219e3e21948c104a50e6fcebc。SM S9180 profile 覆盖安装后已观察到目标卡片与详情构图一致，不据此扩大其他接口或部署版本支持范围。

基线仍为 `upstream-baseline.json` 的 v2.2.0 / `13865b82b19fe51219e3e21948c104a50e6fcebc`，只读脚本校验通过。源码证据：`src/server/server.ts` 搜索/artistDetail/artistSongs/artistAlbums/albumSongs 与 user/library 路由，`src/modules/utils/musicSdk/{wy,tx}/extendSearch.js`、`extendDetail.js`、`tx/singer.js`，网页 `public/music/app.js` 的 handleSearchTypeChange、toggleArtistFavorite、toggleAlbumFavorite。

- `GET /api/music/search?name=...&source=wy|tx&type=singer|album&page=1&limit=20`：对象 list/total/pageSize。只有 wy/tx 注入 extendSearch/extendDetail；网页同样限制。解析源 supportedSources 只表示账号音频解析平台，客户端与上述能力取交集；状态未知保留两平台并提示，不增加虚构能力接口。歌手/专辑采用单平台，不发送 source=all。
- 搜索条目 id/name/picUrl/source；歌手 alias/albumSize（alias 来自网易 SDK；当前 QQ 搜索映射不提供 alias）；专辑 artistName/artistId/size/publishTime。网易搜索时间为毫秒时间戳，QQ 为字符串；缺失不填造。保留后续页面缺省/0 时的首屏 total；沿用原生 20 条和 PageWindow，已知总数可直接请求目标窗口，空/重复页不跳空页，不把 total 当全部可取得的保证。
- `GET /api/music/artistDetail?id&source` 返回 name/avatar/desc/musicSize/albumSize。`artistSongs?id&source&order=hot|time` 返回数组；服务端按每页 100、默认最多 20 页（配置上限 100 页）聚合，手机仅显示已加载数量，详情数量不等于加载队列大小。信息和歌曲请求可独立失败。
- `GET /api/music/artistAlbums?id&source&page`：list/total，条目 id/name/img/singer/publishTime/total。服务端默认每批 50；按平台和 ID 去重，空/重复页停止。
  - QQ 日期映射缺陷：固定基线 `tx/singer.js` 的 GetAlbumList 使用 `music.musichallAlbum.AlbumListServer`，filterAlbumList 仍仅映射 `item.pub_time || ''`，extendDetail 再转发 info.publishTime。2026-11-15 电脑对公开 QQ 接口只读查询（先 searchSinger 获取 MID，再原生 POST GetAlbumList、num=2）返回 HTTP 200/code=0，条目日期键为 publishDate，两条均非空；原有 pub_time 缺失。因此该基线会丢弃歌手专辑列表的发行日期；专辑搜索读取 publicTime/pubTime，为另一条路径。修复应在服务端映射中支持 publishDate 并保留 pub_time 回退，手机不能从已丢失字段恢复日期。此为 QQ 直连证据，未验证用户部署完整 commit 或修改其服务端。
- `GET /api/music/albumSongs?id&source`：list/total/name/artistName/artistId/desc/img/picUrl/publishTime。网易 502 分支被上游映射为空列表；客户端不能据此断言平台一定没有歌曲。歌手跳转要求可靠 ID，QQ 纯数字 artistId 可能是 singerid 兜底，不能当 MID 调用，保持不可点击。
- `GET/POST /api/user/library/artists|albums`：GET 数组，POST **原始 JSON 数组整表覆盖**，成功 `{success:true}`。收藏主键为 source + String(id)。新增歌手保存 id/source/name/picUrl；专辑另存 artistName、interval='00:00'、meta.albumId/picUrl/albumName，与网页一致；有已知发行日期时手机额外保留 publishTime（原始数字/字符串）。固定基线 POST 分支 JSON.parse 后直接写入整个数组，GET 在按需补图后返回原数组，不裁剪该字段；此为客户端可选元数据，非网页保证存在的字段。旧收藏没有日期时不推测或批量补查；歌手有已知 alias 时手机同样保留该可选数组。详情 SDK 不保证单独返回 alias，手机只展示实际已有别名，不按名称猜测或跨 ID 合并。保存前重读，保留无关对象/未知字段，已存在不重写，取消只删除目标；保存后回读，不自动重发 POST。接口无 CAS 或事务，不能保证跨设备并发不覆盖。服务端可能移除相同对象的不喜欢记录；本轮客户端不提供不喜欢功能。

证据等级：上述为固定源码及 `entity_search_test` 的 Mock/Flutter 组件验证，真实部署 commit 未确认，歌手/专辑接口及写入未实测，不扩大兼容范围。真实验收需检查两平台检索/详情、收藏及取消跨页面和跨设备可见性、热门/最新、专辑跳转、实际播放与确认下载。

## 歌曲评论（v2.2.0）

源码：`src/server/server.ts` 的 `/api/music/comment` 分支；`src/modules/utils/musicSdk/{kw,kg,tx,wy,mg}/comment.js` 的返回归一化。

`POST /api/music/comment`，沿用普通用户请求头，JSON 为 `{songInfo: 原始平台歌曲信息, type: "hot" 或 "new", page: 从1开始, limit: 列表浏览每页数量（默认 20）}`。服务端按歌曲 source 调用 getHotComment/getComment，不跨平台合并。返回 `{source, comments, total, page, limit, maxPage}`；评论字段包括 id、text、userName、avatar、timeStr、likedCount、reply，以及部分平台的 images。基线的酷狗、酷我、QQ 部分响应映射配图；已有回复也可带头像和配图。客户端只读展示，配图地址可点击预览。咪咕最新评论上游需要前页游标，跳页范围限已加载页。

服务端不支持该平台方法或上游失败时可能返回 500；客户端显示可重试状态和已脱敏的 HTTP/网络错误，不展示服务端原始错误体，不把失败当作零评论。页面切换分类、关闭后丢弃过期响应。

QQ 评论 SDK 的 getSongId 优先直接使用 songId，否则用 songmid 查询数字 ID。客户端评论请求按 meta.songId、根 songId、数字 songmid 顺序选取纯数字值填充 songId；无数字值时移除不合法 songId，让服务端按 MID 查询，不修改原歌曲或其他接口。依据固定基线 tx/comment.js:getSongId 和 server.ts:normalizeSongInfo；comments_mode_test 覆盖两类 ID、嵌套元数据、原对象保留及安全错误提示。

2026-11-18 对用户部署（公开配置自报 v2.2.0/buildHash 6c6462d，完整 commit 未确认）只读实测：同一 QQ 歌曲内网、公网 POST 最热均 200/7 条，最新均 200/20 条；MID 错填 songId、仅数字 songmid 均返回 500，数字 songId 返回 200。此为该曲接口验证，尚不能证明手机原请求失败原因，也不扩大其他平台支持范围；修复后手机页面待复核。

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
| GET /api/music/cache/check | 用户 Token/name；name/singer/source/songmid/songId/quality/exactQuality=1；仅使用 exists=true、非 isCollision、quality 精确匹配的文件；只接受同服务器 /api/music/cache/file/ 地址。基线服务端对明确未命中返回 exists=false，客户端短时复用该结果；旧版 404 或缓存服务失败继续在线解析 |

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

2026-11-17 SM S9180 真实会话只读复查：使用手机恢复队列当前 QQ 歌曲的 songmid、数字 songId 和当前会话，在电脑侧重放 GET 歌词请求，返回 HTTP 500 / `Get lyric failed`；同歌曲 GET `/api/music/cache/lyric` 返回 404 / `Not found in cache`。本次没有可用服务端歌词缓存兜底，不能将此前某首歌曲 GET 成功推广到全部歌曲。固定基线 QQ `tx/lyric.js` 在上游业务码重试耗尽或解析结果无歌词时均可能抛出此错误；仅凭响应不能区分上游限制、空歌词或具体解析失败，需要部署端日志。当前手机构建为 AOT，VM Service 可读实例但不支持表达式求值；本次未通过播放器重新执行加载，也未验证部署 commit，不将电脑侧重放记为真机端到端通过。

同日直连部署原始端口复查仍为 500，缓存为 404；部署自报 v2.2.0 / `6c6462d`，完整 commit 未知。进一步只读核对 Docker 实际 `tx/lyric.js`：`getSongId` 原样返回传入的 songId，而 GET 查询参数均为字符串。容器内实际模块对照同一歌曲：字符串 songId 抛 `Get lyric failed`，数值 songId 返回 1466 字符歌词；同部署 HTTP 对照携带 songId 为 500、仅携带 MID 为 200。根因是数字 ID 的类型在 GET 链路中丢失，并非已证实的网络故障。客户端对具有非数字 QQ MID 的歌词 GET 省略 songId，让服务端通过 MID 获取数值 ID；保留缓存优先与其他平台字段。该方式首次可能增加服务端歌曲信息查询，后续复用其 MID→ID 内存缓存。仅数字身份仍保留既有参数，其兼容性不扩大；未修改容器或远程配置。

本次客户端验证：Dart 格式化、flutter analyze、music_features_test / browse_cache_test 共 22 项测试及 Android debug 构建通过，ADB 覆盖安装返回 Success。安装后调试验证期间 USB/ADB 连接中断，设备列表为空，未取得 PlayerController 加载结果；手机端显示验收待完成。

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

- 客户端列表展示优先使用该歌本机已记住的成功档位（标准档同样显示），无记录再按以下资料标签规则展示；当前播放页显式实际音质优先。此展示调整不改变服务端契约，也不使用全局默认冒充该歌实际音质。

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

### 新建私人歌单（v2.2.0）

固定基线 `public/music/app.js` 的 `handleCreateList` 将 `{id, name, source: 'webplayer', list: []}` 追加到私人 `userList`。网页 `pushDataChange` 的普通用户 REST 分支提交完整快照至 `POST /api/user/list`，`server.ts` 经普通用户鉴权后调用 `listDataManage.restore` 并创建快照。

客户端在写入锁内读取最新快照，追加 `webplayer_` 加 128 位随机十六进制 ID 的条目，保留现有歌单、系统列表和其他请求字段。创建并加入复用私人歌单既有歌曲格式和平台歌曲身份去重，在同一次 POST 提交歌单和歌曲。响应确认成功后回读；同一个输入框内手动重试沿用原 ID，若最新快照包含该 ID，则沿用已保存的歌单，省去重复 POST。接口没有 CAS，其他设备同时写入仍有覆盖窗口。已核对固定基线并使用 Mock 验证，真实部署写入及跨设备可见性待验收。

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

## 默认列表与收藏目标（v2.2.0）

基线 `src/modules/list/listDataManage.ts` 的 init/导入逻辑使用 `defaultList/loveList/userList` 并映射原生系统 ID。`public/app.js` 将 default 显示为“试听列表”，`public/music/js/library/songlist_manager.js` 单曲点击路径标明加入默认列表；它不是手机端新建的个人歌单。原生协议允许编辑其歌曲，客户端仅从明确“收藏到歌单”的目标选择中排除 default，保留收藏页及排序中的系统项，避免改动现有同步数据。单曲与批量收藏共用目标选择和 LibraryController.editSongs，按最新快照去重并保留无关字段；不写入原平台歌单。song_menu_metadata_test 为 Mock 验证，真实部署写入待验收。

公共列表卡片仅显示已解析 `time`，与详情共用 CollectionMetadata；日期保持平台原义，不将其统一宣称为创建日，缺失不补造。歌曲菜单评论复用同一 `/api/music/comment` 原始歌曲身份请求，不需先播放。

## 系统媒体会话（客户端能力）

固定基线 v2.2.0 / 13865b82 的 public/music/app.js 已核对 mediaSession 的 play/pause/previoustrack/nexttrack/seekto 与 updateMediaSessionMetadata。手机端通过 audio_service 发布本机系统会话，操作委派 PlayerController，不新增 LXServer 路径、鉴权或响应字段；本次不扩大服务端兼容范围。实现与运行验收边界见 PLAYBACK_ENGINE.md。

## 网易查询风控与请求放大边界

以下为固定 v2.2.0 / 13865b82 源码核对，不是部署流量实测。网易触发校验的内部规则、阈值和本次触发原因未知；不能仅凭 App 开发时间或校验提示判断责任入口。未向真实网易接口发送排查请求，未修改部署或上游检出。

- 公共出口：`wy/utils/index.js` 的 eapiRequest/weapiRequest 经 `modules/utils/request.js` 请求网易，后者按 music 分类选择代理。因此走同一部署的网页、App、Subsonic 在线查询可能共享服务器或代理出口；实际出口及其他服务是否共用仍待查。搜索 SDK 请求与自定义音源播放解析需分别统计，不能以播放次数代替网易查询次数。
- 失败重试：`wy/musicSearch.js` 的 search、`extendSearch.js` 的歌手/专辑/歌单搜索遇非 200 业务码会递归立即重试，最多共 3 次，没有校验分类或退避；`wy/songList.js` 的详情、推荐、分类也存在失败递归重试。原始校验信息可能被 `try max num` 等通用错误覆盖。需先明确原始 HTTP 状态、业务码及校验信号，再设计结构化错误，不能把任意 403/500 都判为网易风控。
- 原生歌曲搜索：`server.ts /api/music/search` 显式传正数 limit 才走单页；未传时从第一页连续取数，最多 60 页、4000 条或约 15 秒预算，并可能因空页、重复页或错误提前停止。App `LxApi.search` 明确传 limit=20；基线网页 app.js 的普通歌曲搜索传 limit=30，服务端按 SDK 上限收紧，网易为 20，故这两条普通歌曲搜索路径均非默认全量抓取。
- 网页输入联想：`public/music/js/library/search_suggestions.js` 在输入停顿 300ms 后调用 tipSearch；聚合时按各平台查询，有 60 秒非空结果缓存。取消浏览器 fetch 不等于已证明服务端及网易请求均被取消。App home.dart 当前只在显式提交时搜索，未发现相同输入联想路径。
- App 重复查询：`AppController.search` 仅阻止正在搜索时的 more，新查询没有相同请求合并；版本号只丢弃旧响应，不取消网络请求。跨平台并发不等于同时向网易请求五次，但重复提交、切平台再切回和重新进入详情可能重复请求网易。目前没有统一网易查询冷却与校验熔断；LxApi 将多数服务端失败转换为通用错误。
- 重试层级复核：LxApi._request → _requestJson 只发送一次，server.ts 上述原生查询路由未另包一轮重试，底层 request.js 也未发现自动重发。因此普通搜索不是 App 三次乘服务端三次，而是一次 App 请求仍可能被网易 SDK 放大为三次。网页 JavaScript 不在 App 调用链内。不能根据 retryNum 参数名断言实际重试：wy/musicDetail.getList 虽保留该参数，失败直接 throw；songList.search 也直接失败，不同于 extendSearch.searchPlaylist 的递归三次。
- 歌手列表头像补全：`ArtistCard` 构建时调用 `AppController.artistPortrait`，网易每个不同歌手都会排队读取 artistDetail，不仅是请求图片；当前仅有最多 100 项会话内 Future 复用，未落盘。进入歌手详情又由独立控制器读取简介，未共享该结果。这属于列表逐项补全导致的额外平台查询，应改为优先现有图片、缺图占位并共享持久化详情缓存，避免仅为头像自动查询全部歌手。
- 歌手详情：App `EntityDetailController.load` 并行请求 artistDetail 和 artistSongs。`server.ts /api/music/artistSongs` 内部串行抓取每页 100 条，默认最多 20 页；配置 artist.maxFetchPages 可调整且上限 100。App 一次调用不代表一次网易请求，详情不是按手机显示页按需查询。该放大点应优先整改，不能仅在 UI 增加防抖。
- 外部歌单：App 浏览详情按批次加载；完整收藏/显式刷新经 `LibraryController.remoteSongs` 连续读取到结束，安全上限 1000 次且无新歌曲时失败。网易 `songList.getListDetail` 每次先请求歌单详情，再按 trackIds 分批调用 musicDetail 补足，翻页可能重复读取详情；需区分普通浏览和显式全量操作，不应以不完整结果覆盖已有收藏。
- Subsonic：`integrations/subsonic.ts fetchOnlineSearchSongs` 在缓存未命中时，每个平台主动取到目标 50 条；网易每页 20，最多先取 3 页，不足时还会尝试简繁关键词变体。成功返回结果复用 5 分钟缓存，但该函数未合并同键在途请求。歌手、专辑搜索另有在线路径。默认配置 onlineSearch=true、onlineSearchMode=fallback、候选源含 wy；实际配置未知。“客户端很少播放”不能证明没有搜索或后台请求。
- MA：本地未取得用户所用插件源码、版本或配置。若使用 MA 官方 OpenSubsonic provider，它依赖 Subsonic 服务；禁用整个服务会影响该 provider 的同步、查询及播放。若是直连原生 API 的第三方 LXServer provider，则需按插件调用链判断，不能推断两者独立。可先评估只关闭 Subsonic 在线搜索，保留协议和本地库访问；这会影响依赖在线搜索的功能，不代表所有在线相关调用都已停止。

完整调用链的整改建议（包含上游能力，服务端改动不在本次客户端实施范围）：先在服务端公共网易调用处保留脱敏错误分类、停止校验响应重试、按出口限制并发并合并相同在途查询；冷却时间遵循上游明确信号，未提供时作为可配置策略，不宣称某个请求速率安全。随后让歌手歌曲按需分页，App 增加查询复用、同请求合并、取消未开始任务及明确冷却提示，并让播放降级/批量操作在校验错误后停止继续尝试。浏览与完整收藏要保留不同的完整性语义。

验收需覆盖：校验响应只发送一次上游请求、相同并发查询合并、切换查询不再执行旧排队任务、冷却不阻止其他平台及已有本机文件播放、歌手首屏不全量抓取、完整收藏失败不覆盖旧数据。仍需部署版本及脱敏运行证据：按入口/平台/操作统计上游次数、并发、重试、缓存命中及状态码，与首次校验时间对齐；不得记录密码、Token、Cookie、完整签名 URL 或原始个人查询。当前部署 commit 未确认，无真实流量归因结论。

客户端请求收敛与浏览缓存第一版已实现，范围和数据生命周期见 ARCHITECTURE.md“浏览缓存与请求收敛”。全部沿用既有接口，不修改上游。显式下拉刷新仅保证请求 LXServer，不保证其绕过服务端自身缓存；HTTP 5xx/429 停止播放解析尝试，不等于已经取得原始网易校验码。跨重启磁盘复用、离线缓存命中和请求次数通过 Mock/临时目录测试，部署风控归因与真实设备流量仍待核实。

浏览软过期是客户端策略，沿用现有接口，不假设 ETag、服务端快照版本或缓存绕过参数。已只读校验 v2.2.0 / 13865b82 基线；server.ts 的 artistDetail、artistAlbums、artistSongs、albumSongs 调用链仍按原契约，artistSongs 仍可能在服务端全量抓取，客户端普通翻页不触发过期重取。推荐/分类 1 小时，搜索/外部歌单/歌曲列表 24 小时，歌手基本资料 7 天；页面进入更新成功后使同查询旧后续页失效，失败保留旧缓存。Mock 时间推进验证不代表真实部署时效或请求量已测。

### 打开分享歌单

固定 v2.2.0 基线 `src/server/server.ts` 的 GET `/api/music/songList/detail` 将 source/id/page 传入各平台 `songList.getListDetail`。客户端保留输入，通过 query 编码发送，不自行猜测短链解析接口；使用返回的 info.name/img/author 等展示详情，收藏复用既有流程。
酷狗 `src/modules/utils/musicSdk/kg/songList.js:getListDetail` 将纯数字交给 getUserListDetailByCode；普通分享 URL 交给 getUserListDetail，`id_` 前缀为内部 special ID。网页提示不支持用歌单 ID 或概念版链接打开。基线 changelog 虽记载 #483 酷狗码导入修复，不代表所有链接均可用，也不能证明用户部署的具体失败原因。需要失败链接类型、错误及部署 commit 进一步核实；本次仅源码核对和 Mock 验证，未修改服务端。

2026-11-17 酷狗分享只读排查：使用用户提供的酷狗码与普通版 `m.kugou.com/songlist/gcid_…/` 链接，在本机用 Node fetch 按固定基线的方法与签名参数请求公开酷狗接口（未运行完整 LXServer request 适配层，未请求用户部署，未持久化个人输入/响应）。码的 `/command/` 与链接的 `/v1/songlist/batch_decode` 均 HTTP 200、业务码 0；后续 `/api/v5/special/info_v2` 同样成功；两路最终在 `/api/v5/special/song_v2` 收到 HTTP 200、业务码 20028。因此已定位本机直连时的失败阶段为歌曲列表获取，不能归因于输入格式或 gcid 解码失败；20028 的具体含义及部署侧是否同因仍待确认。基线 createHttpFetch 对非零业务码重试，最终可能只暴露 try max num，丢失原始错误。客户端不绕过服务端直接读取酷狗，不修改上游参考检出。
