# 架构约定

## 初始方向

采用按功能组织的轻量分层。先建立必要边界，避免一次生成大量空文件。
功能目录按需要创建，未实现模块不提前建立空壳。初始规划：

```text
lib/
  main.dart
  app/                  # 启动、主题、路由与依赖组装
  core/                 # 配置、网络基础、错误、基础存储
  features/
    connection/         # 服务器配置与鉴权
    search/             # 搜索
    player/             # 播放服务、队列、播放状态与界面
    library/            # 歌单、收藏与历史
    discovery/          # 排行榜等浏览入口
    downloads/          # 下载与离线资源
    settings/           # 偏好与存储管理
  shared/               # 已出现复用需求的组件与模型
test/
integration_test/
```

功能内部按需要使用 presentation、application、data 目录；仅在业务复杂度需要时引入 domain 层。

## 依赖方向

界面 → 状态/用例 → Repository → API 或本地数据源。

- 服务端 DTO 在数据边界转换，避免响应字段散落于 Widget。
- HTTP 客户端统一处理地址、鉴权、超时、错误转换与日志脱敏。
- 播放服务独立于页面生命周期；队列和当前播放项只有一个权威状态源。
- 播放地址可能具有时效性，获取与刷新策略依据 API 证据确定。
- 凭据使用平台安全存储；普通偏好与敏感数据分开保存。
- 下载及缓存只通过其所属服务管理，不由 UI 直接删除文件。

## 待确定

当前使用 ChangeNotifier / ListenableBuilder、Navigator、http、just_audio、flutter_secure_storage。
AppController 负责登录、平台能力与聚合搜索状态，PlayerController 持有唯一播放器、队列和歌词状态，LxApi 封装原生接口。
LibraryController 管理个人歌单、歌手、专辑的独立加载状态；DiscoveryController 管理在线歌单分类、排序、搜索和分页。
ServerFilesController 独立读取服务器文件状态，按用户会话隔离，合并并发并以 60 秒 TTL 复用。AppController 触发刷新；歌曲行只订阅状态，不发送 HTTP。PlayerController 通过只读回调获得已有服务器文件音质，和元数据/当前播放音质一起形成选项分组。
MusicHome 使用三个导航入口，共享播放器；详情页只调用控制器，退出时清除私人数据并关闭详情路由。
PersonalCenterScreen 组织账号和本机存储入口；共享 showSongActions 为列表和播放页提供统一歌曲菜单，页面通过 AppController 发送操作，不重复实现下载/文件管理。
SongMetadata 共用歌曲平台/最高标注音质/本机文件标签；PlayerController 管理播放模式与自动完成事件，nextQueueIndex 为纯策略。CommentsController 持有打开时歌曲快照、分类及分页，通过请求代际防止过期响应覆盖或销毁后通知；评论不改变当前播放状态。
MusicHome 持有顶部搜索框；各列表页以单个 CustomScrollView 组织筛选和内容，筛选不固定占用列表高度。
SongArt 的网络及本机封面通过 ResizeImage 按显示尺寸和设备像素比限制解码大小；SongTile 将文件状态订阅限制在元数据区域，避免通知重建封面和整行。音乐库加载/排序提示固定 2px 占位，避免保存时改变列表位置。SongArt 通过 ArtworkImage 加载封面；独立图片客户端替换默认 User-Agent，不使用登录凭据，避免 Flutter NetworkImage 追加请求头导致 CDN 拒绝。
SessionStore 持久化服务器和 Token 会话，不保存密码；另存平台/播放/列表偏好及账号隔离的浏览条件，搜索输入也存于安全存储。音频 URL 请求不附带用户 Token。
后台媒体服务采用 audio_service，SystemAudioHandler 订阅唯一 PlayerController 并将系统操作委派回控制器，不创建第二播放器或队列；本地数据库、实时同步方案尚未选定。个人歌单重命名/删除/关联歌单刷新由 LibraryController 重读快照后调用 LxApi 全量写入，UI 仅确认和发送操作；接口无并发冲突检测。歌词使用独立 LRC 解析模型；异步响应与当前曲目绑定，切歌/退出使旧请求失效。
后续随功能扩大拆分 AppController，避免把所有业务持续集中其中。

音质策略独立为 QualityPolicy，解析返回 PlaybackResource，区分请求值与服务器标注。
PlayerController 负责音质切换、旧音频恢复与偏好持久化回调；页面不直接重建播放器。
初始请求不以旧歌单音质标注为上限；个人中心的全局首选立即持久化，当前歌曲临时切换不持久化。loadWithQualityFallback 统一负责解析/加载失败后的同平台降级，鉴权失败和过期请求停止重试；成功降级不修改偏好。
新搜索结果以 freshQualityMetadata 标记来源，新鲜具体音质列表用于过滤候选档位；历史收藏默认不假定完整。PlaybackCache 独立管理结果 TTL、安全存储回调、内存播放地址和源配置作用域。PlayerController 负责读取缓存、更新播放状态及手动重试，页面不操作缓存文件或解析 URL。
新鲜列表含平台占位项时不作为完整音质约束。loadWithQualityFallback 优先沿用与当前首选绑定的成功档位，每档先查服务端已有文件；加载失败时携带 sourceId 排除已失败源。失败仅会话内 30 秒退避，网络/权限错误直接终止；无在线源时仍允许读取较低档已有缓存。成功档位无时间 TTL，最多 200 条 LRU；只有 URL 存在短期 TTL。修改首选或主动重试后重新选档，自动降级不回写偏好。
播放页使用 PageView 切换封面/歌词，复用 player_controls，歌词自动滚动只操作内部纵向 ScrollPosition。

## 验证重点

`AlbumCard` 和 `ArtistCard` 为 EntityGrid 的两种展示组件，按列宽及文字缩放计算卡片高度。歌手卡片使用大圆头像、细环与渐变，别名位于主名下；专辑卡片仅外轮廓圆角、歌手居左/平台居右，无快捷播放和下载。两类卡片圆角统一 12；CardFavoriteButton 共用灰色遮罩、图标尺寸与内部视觉偏移，收藏不触发详情导航。toggleEntity 统一处理歌手/专辑的取消确认，卡片与详情共用；确认后再次核对当前会话再调用 LibraryController 保存，关闭或保留不写入。SongArt 使用 ResizeImagePolicy.fit 保持原图宽高比，之后通过 BoxFit.cover 裁切；网络与本机图片采用相同策略。人物缺图用灰底白色人物占位，不改变普通歌曲封面的默认样式。

`PlayAllControl` 为歌单与歌手/专辑详情共用的紧凑播放按钮、标题及数量组件，不持有播放状态。歌手详情保留内容标签吸附，下方独立播放栏同样吸附；收藏统一放在详情导航栏最右侧。专辑标签只显示专辑列表，不渲染播放栏。

歌手/专辑详情的多选状态由路由维护，按歌曲 ID 跨页保留；复用 PlaylistEditGlyph、CollectionEditActions、pickCollection、LibraryController.editSongs 及 LocalMediaController.enqueue。全选仅作用于实际载入歌曲，底部仅提供下一首播放/收藏/下载，不渲染原平台删除操作；下载先快照选中歌曲再选档确认。数量标签先专辑后歌曲，避免晚到的歌曲数量挤动首项。

歌手/专辑由 `MusicEntity` 统一解析搜索、收藏与详情字段；`EntitySearchController` 管理类型、平台、分页窗口及过期响应，`EntityDetailController` 管理每个详情路由的歌曲/信息与独立专辑分页。AppController 组合账号可用平台和静态功能支持范围，不将 supportedSources 当作完整能力表。页面只调用控制器；收藏由 LibraryController 共用写入锁，保存前重读整表、保留其他对象及字段，按平台/ID 去重并回读确认。详情复用 SongTile、PlayerController、MiniPlayer 和 LocalMediaController，不创建播放器或自行请求接口。数量/简介缺失不伪造，歌曲分页只派生视图不改变队列。

接口解析与错误转换、队列行为、歌词解析、同步幂等性适合自动化测试。
后台音频、系统控制和平台权限需要真机验证。

## 手机缓存与下载（当前实现）

`features/local_media` 由 LocalMediaController 管理文件索引、隔离作用域、LRU 和下载队列；AudioTransfer 管理单次传输，CachedAudioProxy 向唯一播放器提供回环范围读取 URL。UI 只订阅状态并调用操作。path_provider 提供私有目录，crypto 提供稳定散列标识。生命周期见 [LOCAL_MEDIA.md](LOCAL_MEDIA.md)。

PlaybackGlyph 为纯绘制组件，统一圆角图形，继承按钮的 IconTheme 以支持禁用颜色；不改变播放控制逻辑。showSongActions 通过 fromPlayer 区分场景：播放页提供音质并隐藏立即播放，列表提供立即播放并隐藏音质。

播放内核机制集中在 [PLAYBACK_ENGINE.md](PLAYBACK_ENGINE.md)。LocalMediaController 在播放器采用资源后更新使用时间；文件查询不算播放。淘汰只按最近实际播放时间排序，旧版本优先级记录不再读取。单曲清理由控制器执行，UI 只请求确认和发送操作。

LocalArtwork 由 LocalMediaController 管理：独立串行封面任务、大小与类型限制、原子写入、按平台歌曲 ID 复用及孤立文件清理。SongArt 只选择本机或网络图片提供器，不自行下载/管理文件。

PlaybackSnapshot 仅包含可恢复状态；PlaybackResumeStore 管理私有文件、节流与原子串行写入。AppController 监听唯一播放器并安排保存、恢复已验证会话的快照；LxApp 通过生命周期回调补存。恢复不创建 AudioPlayer，只有显式播放才加载资源。core/song_snapshot.dart 统一歌曲最小持久化字段，复用于下载和播放快照。

音乐库长按通过 showCollectionActions 弹出操作面板，详情保留 CollectionMenu；两者复用 performCollectionAction。CollectionScreen 区分私人可编辑歌单与外部在线详情，并订阅 LibraryController 的封面/标题变化。CollectionHeader 只渲染可用元数据；CollectionMetadata 在 data 边界解析 author/desc/play_count/time，DiscoveryController 合并列表与详情字段，经 SongBatch 交付页面；originalSummary 在收藏跳转时按 source/原 ID 复用已加载列表摘要，保留详情接口未返回的日期，不新增搜索请求。私人收藏记录缺少这些字段时不伪造，也不新增未经核对的持久化字段。

LibraryController 在完整分页后聚合歌曲/封面；收藏重读快照查重，再通过 LxApi 保存原生字段。librarySong 对齐上游 formatSongToLxMusicStandard 的 id/meta，同时保留额外字段。显式同步只以非空来源图更新 Album；操作期间保持写入锁，reset/dispose 使旧操作失效。UI 不发送 HTTP。

CollectionScreen 用单个 CustomScrollView 组织可滚动头部、SliverPersistentHeader 吸附工具栏和歌曲；搜索在导航按需展开，PopScope 优先退出搜索/选择。搜索/分页只派生显示条目，不改变已加载播放队列。多选状态归详情页所有，PlayerController.enqueueNext 将选择歌曲去重放在当前歌曲之后且不自动播放；批量下载经 LocalMediaController，页面不管理文件。分页模式及数量由 AppController/SessionStore 保存。ScrollingTitle 只对超宽标题运行动画并遵循系统减少动态效果，保留完整无障碍标签。

私人歌曲编辑通过 LibraryController.editSongs/_editSnapshot 保存，歌单混排通过 reorderCollections 协调歌单数据与账号显示设置，两者共用控制器写入锁和会话版本；library_edit 是纯快照变换，保留未知字段并检查排序基线。CollectionScreen 只持有选择和排序草稿，调用控制器保存，不直接请求 HTTP。确认删除可合并待保存顺序，成功回查失败不会重发写入。编辑工具栏由 CollectionEditActions 和 PlaylistEditGlyph 提供；原平台歌单没有对应写接口，显示只读边界。LibraryScreen 的 SliverReorderableList 包含全部歌单，系统项可移动但不可删除/改名；松手后暂显新顺序，控制器先 GET 最新歌单/账号设置，检查完整显示顺序，仅在自建项相对顺序变化时 POST 歌单，再 POST 保留其他字段的 favoriteSidebarOrder。网页隐藏入口保持原位置，新增歌单追加展示；读取设置失败不阻止浏览，但保存时必须有合法设置。双写无事务，部分失败展示已确认状态和明确提示，不自动回滚或重试写入。分类复用 ChoiceChip，主页顶栏统一占用高度（搜索框默认 40，随文字缩放），分类行最小 44 高，保证首次切页标签对齐；“我的”标题为“我的收藏”；MusicBadge 保留原英文 height=1.3 与自然字体度量，不强制共用 strut/leading；含中文标签仅在自然基线上做 0.5 逻辑像素的向上视觉微调（随文字缩放），避免影响英文。真机视觉效果仍需用户复核。

PlatformFilters 与“我的收藏”复用 EqualFilterRow，统一等宽铺满、左右留白与间距，无额外底部 padding。按文字实际宽度确定最小单元宽度，大字体/窄屏保留等宽并横滑。平台采用 musicSourceOrder（网易/QQ/酷狗/酷我/咪咕），首次默认网易，无选中项仍表示聚合，已保存 all 不被覆盖。SessionStore 的平台偏好保存 search/discovery 的平台标识或 all，不保存标签数量或服务端配置；按设备偏好恢复，沿用现有音源状态接口核对有效性，已禁用的平台选择回聚合，状态未知仍保留平台。

DiscoveryController 的聚合沿用歌曲搜索思路：各平台独立分页与去重，按平台轮流合并，失败单独提示；切换/重置后丢弃旧响应。聚合模式仅推荐/关键词搜索，不映射平台分类；选定平台才显示原生分类与排序。推荐首次按平台从现有 tags 响应取得首个原生排序标识，当前控制器生命周期内复用；正常关键词搜索复用已加载分类；跨启动恢复补读分类以校验保存的排序，不额外请求“平台标签数量”。没有新依赖或服务端聚合接口。

搜索、公共歌单和歌单内歌曲共用 ResultPagination 的 32px 分页条及页码面板，单平台按既有 pagedCollections/collectionPageSize 偏好分页，聚合固定连续浏览。搜索/歌单接口的 total 用于计算展示总页数；缺失且尚未读完时仅显示当前页，不把缓存页数当总页数。未知总数的跳页只允许已加载范围。分页时主页 MiniPlayer 使用 compact 边距，与歌单详情一致，不另加上下空白。

PageWindow 缓存单平台原生页及 total/nativeSize；展示页大小与接口页大小分开。跳页仅顺序读取目标窗口相交的缺失原生页，缓存仍按原生页号合并、歌曲身份去重，播放仍使用已加载列表。控制器的 searchRevision/resultRevision 隔离新查询，未完成的旧翻页不阻止新查询翻页。总数是原平台自报值；目标页为空或完全重复时保留当前页并提示，不自动重试。分类栏保持紧凑，tags.sortList 为 0 项不占位，1 项纯文字，多项下拉。

app_modal.dart 统一底部面板和确认框的白底、圆角、标题/副标题、取消入口、输入框、42px 确认按钮与选中态。选择/信息用底部面板，重命名等输入用适配键盘的紧凑面板；删除/清理/退出仍明确确认并使用警示色。showAppSheet 管理安全区、最大可用高度和键盘遮挡，内容高度按场景确定；音质即时生效的面板使用“关闭”，未提交的选择使用“取消”。showPageJump 使用同一面板，输入/惰性滚轮二选一，确认校验后返回零基页码，不自行发请求。没有新依赖或第二套播放器。


浏览条件由 AppController 管理，SessionStore 保留轻量条件用于旧版本迁移；BrowseSnapshotStore 独立保存浏览会话，见下节。

网易 ArtistCard 只使用现有图片，不额外查询详情补头像；已替代早期会话内头像补全策略。

## 浏览缓存、浏览会话与请求收敛

仅修改 App，沿用现有 LXServer API，不修改服务端或参考检出。BrowseCache 在应用私有持久化目录 browse-cache-v1 保存白名单查询响应；与音频缓存、下载、播放地址和账号凭据分离。搜索、公共歌单分类/推荐/搜索/详情、歌手/专辑详情、评论和歌词按服务器、账号、接口及完整参数隔离，文件名为散列，不持久化 Token。公开封面按 URL/非鉴权请求头复用；带鉴权头或已识别敏感参数的封面不落盘。已有下载封面仍由 LocalArtwork 管理。

浏览缓存含封面共用独立 LRU，默认 128 MiB，可选 32/64/128/256/512/1024 MiB，单响应不超过 4 MiB，单封面不超过 2 MiB。缓存不因进入页面或重启按时间自动刷新，用户通过下拉或清理显式更新；数据可能陈旧。写入串行、临时文件替换；缓存 I/O 失败不阻止正常接口返回。设置新增“清理浏览缓存”，不删除音频、下载、收藏或偏好；清理后不允许早于清理的在途响应重新落盘。缓存不等于权威数据，账号鉴权和私人收藏/设置快照仍走原流程，写入前最新快照及回读不使用浏览缓存。

LxApi 仅对白名单 GET 及现有只读评论 POST 合并同请求、按服务器/平台串行发送；未开始且已无有效调用方的查询取消，已发送请求不声称可停止服务端工作。同平台同接口失败会停止已经排队的后续查询，后续用户显式操作可重新尝试，不把普通 500 定性为网易风控。普通查询不增加自动重试。refreshBrowse 用于显式刷新，绕过 App 读缓存；成功更新第一页后清除相同查询旧后续页，失败保留磁盘缓存。搜索、公共歌单、实体详情和外部歌单详情支持下拉；刷新关联歌单同样强制联网读取完整批次，不以旧缓存冒充最新同步。

网易歌手卡片不再逐项请求详情补头像，只用已有列表图片。歌手详情仍受服务端 artistSongs 内部全量抓取限制，App 通过复用结果减少调用，未实现不存在的服务端分页。服务端 5xx 和 HTTP 429 会终止本次播放解析降级，下载遇此错误暂停同平台后续排队任务；不推断原始校验原因。缓存覆盖命中后可离线恢复浏览首屏，但首次登录与鉴权拒绝沿用原安全边界。

BrowseSnapshotStore 在 browse-session-v2.json 保存账号/服务器隔离的浏览会话，不受内容 LRU 淘汰或“清理浏览缓存”影响：三个主页的列表和原生 PageWindow、当前条件、页码/滚动位置、我的子分类，以及详情内容、详情分页、歌曲/专辑子页签。页面快照最多保留 100 项，页栈最多 20 层，单会话文件最多 24 MiB；超过文件预算保留上一份完整快照，未知版本/损坏记录回退到旧条件恢复。250ms 合并保存，生命周期离开前台补存，串行临时文件替换；强杀仍可能丢失尚未落盘的最后变化。快照过滤凭据、临时播放地址和敏感链接，不保存选择/编辑草稿或待确认动作。注销及鉴权拒绝清除会话，账号切换不串读；写入收藏仍读取最新服务端快照，不把本地浏览记录作为写入基线。

RememberedPage 管理滚动和分页状态，详情页面重新进入先恢复本地模型，刷新重建第一页；浏览主页继续使用 IndexedStack。BrowseNavigatorObserver 记录 browseRoute 的受支持页面，MusicHome 就绪后重建歌手/专辑/歌单详情、个人中心、下载、音频缓存设置及播放器页栈；返回按原顺序逐级退回。播放器只恢复页面/封面歌词子页签及暂停的播放快照，不自动播放；对话框、评论面板、未提交编辑与确认操作不恢复。旧版本没有页面/页栈记录时仍按既有查询条件恢复首屏。缓存与快照 I/O 失败不作为成功持久化的证据。

内容缓存和状态快照是不同的可用性边界：清理内容缓存保留当前界面和快照；恢复已有页面不因重新进入而刷新，缺页只在用户分页时按需查询。私人收藏页可从快照恢复，显式刷新和保存前仍读取服务端。容量设置持久保存；BrowseCache 默认为 128 MiB，音频新用户默认 2048 MiB，保留所有既有有效音频限制，包括 0/256/512/1024 MiB，扩展到 3072/4096/5120 MiB。主动下载不计入音频自动缓存上限。

browse_session_test 覆盖原生非连续页与第 3 页恢复、位置/账号隔离、页栈返回、详情重开零歌手查询、损坏回退、注销与在途写入清除、快照敏感字段过滤、默认容量和 5 GiB 配置持久化；browse_cache_test 继续验证内容缓存生命周期。测试注入 http.Client 默认不启用磁盘内容缓存，显式注入 BrowseCache 才启用；BrowseSnapshotStore 支持临时目录及测试内存替身。SM S9180 已覆盖安装并验收搜索第 3 页、播放页歌词子页签及返回路径、歌单详情第 3 页与滚动位置、多层设置返回、我的专辑子分类的强制结束后恢复；存储压力下超大列表和 iOS 仍需设备验收。