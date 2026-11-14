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
SongArt 通过 ArtworkImage 加载封面；独立图片客户端替换默认 User-Agent，不使用登录凭据，避免 Flutter NetworkImage 追加请求头导致 CDN 拒绝。
SessionStore 仅持久化服务器和 Token 会话，不保存密码。音频 URL 请求不附带用户 Token。
后台播放服务、本地数据库、写入同步方案尚未选定。歌词使用独立 LRC 解析模型；异步响应与当前曲目绑定，切歌/退出使旧请求失效。
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
