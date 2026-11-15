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
SessionStore 仅持久化服务器和 Token 会话，不保存密码。音频 URL 请求不附带用户 Token。
后台播放服务、本地数据库、实时同步方案尚未选定。个人歌单重命名/删除/关联歌单刷新由 LibraryController 重读快照后调用 LxApi 全量写入，UI 仅确认和发送操作；接口无并发冲突检测。歌词使用独立 LRC 解析模型；异步响应与当前曲目绑定，切歌/退出使旧请求失效。
后续随功能扩大拆分 AppController，避免把所有业务持续集中其中。

音质策略独立为 QualityPolicy，解析返回 PlaybackResource，区分请求值与服务器标注。
PlayerController 负责音质切换、旧音频恢复与偏好持久化回调；页面不直接重建播放器。
初始请求不以旧歌单音质标注为上限；个人中心的全局首选立即持久化，当前歌曲临时切换不持久化。loadWithQualityFallback 统一负责解析/加载失败后的同平台降级，鉴权失败和过期请求停止重试；成功降级不修改偏好。
新搜索结果以 freshQualityMetadata 标记来源，新鲜具体音质列表用于过滤候选档位；历史收藏默认不假定完整。PlaybackCache 独立管理结果 TTL、安全存储回调、内存播放地址和源配置作用域。PlayerController 负责读取缓存、更新播放状态及手动重试，页面不操作缓存文件或解析 URL。
新鲜列表含平台占位项时不作为完整音质约束。loadWithQualityFallback 优先沿用与当前首选绑定的成功档位，每档先查服务端已有文件；加载失败时携带 sourceId 排除已失败源。失败仅会话内 30 秒退避，网络/权限错误直接终止；无在线源时仍允许读取较低档已有缓存。成功档位无时间 TTL，最多 200 条 LRU；只有 URL 存在短期 TTL。修改首选或主动重试后重新选档，自动降级不回写偏好。
播放页使用 PageView 切换封面/歌词，复用 player_controls，歌词自动滚动只操作内部纵向 ScrollPosition。

## 验证重点

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

PlatformFilters 与“我的收藏”复用 EqualFilterRow，统一等宽铺满、左右留白与间距，无额外底部 padding。按文字实际宽度确定最小单元宽度，大字体/窄屏保留等宽并横滑。平台采用 musicSourceOrder（网易/QQ/酷狗/酷我/咪咕），首次默认网易，无选中项仍表示聚合，已保存 all 不被覆盖。SessionStore 只保存 search/discovery 的平台标识或 all，不保存标签数量、分类缓存或服务端配置；按设备偏好恢复，沿用现有音源状态接口核对有效性，已禁用的平台选择回聚合，状态未知仍保留平台。

DiscoveryController 的聚合沿用歌曲搜索思路：各平台独立分页与去重，按平台轮流合并，失败单独提示；切换/重置后丢弃旧响应。聚合模式仅推荐/关键词搜索，不映射平台分类；选定平台才显示原生分类与排序。推荐首次按平台从现有 tags 响应取得首个原生排序标识，当前控制器生命周期内复用；关键词搜索不请求分类，不额外请求“平台标签数量”。没有新依赖或服务端聚合接口。

搜索、公共歌单和歌单内歌曲共用 ResultPagination 的 32px 分页条及页码面板，单平台按既有 pagedCollections/collectionPageSize 偏好分页，聚合固定连续浏览。搜索/歌单接口的 total 用于计算展示总页数；缺失且尚未读完时仅显示当前页，不把缓存页数当总页数。未知总数的跳页只允许已加载范围。分页时主页 MiniPlayer 使用 compact 边距，与歌单详情一致，不另加上下空白。

PageWindow 缓存单平台原生页及 total/nativeSize；展示页大小与接口页大小分开。跳页仅顺序读取目标窗口相交的缺失原生页，缓存仍按原生页号合并、歌曲身份去重，播放仍使用已加载列表。控制器的 searchRevision/resultRevision 隔离新查询，未完成的旧翻页不阻止新查询翻页。总数是原平台自报值；目标页为空或完全重复时保留当前页并提示，不自动重试。分类栏保持紧凑，tags.sortList 为 0 项不占位，1 项纯文字，多项下拉。

app_modal.dart 统一底部面板和确认框的白底、圆角、标题/副标题、取消入口、输入框、42px 确认按钮与选中态。选择/信息用底部面板，重命名等输入用适配键盘的紧凑面板；删除/清理/退出仍明确确认并使用警示色。showAppSheet 管理安全区、最大可用高度和键盘遮挡，内容高度按场景确定；音质即时生效的面板使用“关闭”，未提交的选择使用“取消”。showPageJump 使用同一面板，输入/惰性滚轮二选一，确认校验后返回零基页码，不自行发请求。没有新依赖或第二套播放器。
