// Test-only LX API fixture, never used by the production application.
// Run locally: node integration_test/fixture_server.mjs
import http from 'node:http';

const port = 18765;
const token = 'integration-test-token';
let loggedIn = false;
let resolutionCount = 0;
let cacheMode = false;
let lastExcluded = [];
const rate = 22050;
const pcmLength = rate * 2 * 30;
const wav = Buffer.alloc(44 + pcmLength);
wav.write('RIFF', 0); wav.writeUInt32LE(36 + pcmLength, 4);
wav.write('WAVEfmt ', 8); wav.writeUInt32LE(16, 16);
wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
wav.writeUInt32LE(rate, 24); wav.writeUInt32LE(rate * 2, 28);
wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
wav.write('data', 36); wav.writeUInt32LE(pcmLength, 40);
// Silence validates decoding and clock advancement without unexpected sound.
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${port}`);
  const json = (value, status = 200) => {
    res.writeHead(status, {'content-type': 'application/json'});
    res.end(JSON.stringify(value));
  };
  if (url.pathname === '/api/music/comment') return json({source: 'kw', comments: [{id: 'fixture-comment', userName: 'Fixture listener', text: 'Fixture comment', likedCount: 12, timeStr: '2026-01-01', reply: [{userName: 'Fixture reply', text: 'Reply text'}]}], total: 1, page: 1, limit: 20, maxPage: 1});
  if (url.pathname === '/cover.png') { res.writeHead(200, {'content-type': 'image/png'}); return res.end(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64')); }
  if (url.pathname === '/broken.wav') return json({error: 'Fixture broken media'}, 404);
  if (url.pathname === '/fixture.wav' || url.pathname === '/api/music/cache/file/fixture/fixture.wav') {
    if (url.pathname !== '/fixture.wav' && (url.searchParams.get('token') !== token || !loggedIn)) return json({error: 'Unauthorized cache file'}, 401);
    if (req.headers['x-user-token']) return json({error: 'Credentials leaked to media'}, 400);
    const match = /bytes=(\d+)-(\d*)/.exec(req.headers.range || '');
    const start = match ? Number(match[1]) : 0;
    const end = match && match[2] ? Math.min(Number(match[2]), wav.length - 1) : wav.length - 1;
    res.writeHead(match ? 206 : 200, {'content-type': 'audio/wav', 'accept-ranges': 'bytes',
      'content-length': end - start + 1, ...(match ? {'content-range': `bytes ${start}-${end}/${wav.length}`} : {})});
    return res.end(wav.subarray(start, end + 1));
  }
  let body = '';
  for await (const chunk of req) body += chunk;
  const data = body ? JSON.parse(body) : {};
  if (url.pathname === '/api/user/login') {
    if (data.username !== 'fixture-user' || data.password !== 'fixture-password') return json({success: false}, 401);
    loggedIn = true;
    return json({success: true, token, username: 'fixture-user'});
  }
  if (!loggedIn || req.headers['x-user-token'] !== token) return json({success: false}, 401);
  if (url.pathname === '/fixture/stats') return json({resolutionCount, lastExcluded});
  if (url.pathname === '/fixture/cache-enable') {cacheMode = true; return json({success: true});}
  if (url.pathname === '/fixture/go-offline') {
    json({success:true});
    setTimeout(()=>{server.close();server.closeAllConnections();setTimeout(()=>server.listen(port,'127.0.0.1'),5000);},30);
    return;
  }
  if (url.pathname === '/api/music/cache/list') return json({success: true, data: [
    {id: 'kw_fixture-1', source: 'kw', quality: 'flac', folder: 'cache'},
    {id: 'tx_fixture-1', source: 'tx', quality: 'master', folder: 'music'},
  ]});
  if (url.pathname === '/api/music/cache/check') {
    const quality = url.searchParams.get('quality');
    return json(cacheMode && quality === 'flac' && url.searchParams.get('songmid') !== 'fixture-recovery'
      ? {exists: true, quality, url: `/api/music/cache/file/fixture/fixture.wav?token=${token}`}
      : {exists: false});
  }
  if (url.pathname === '/api/user/auth/verify') return json({valid: true, username: 'fixture-user'});
  if (url.pathname === '/api/user/logout') { loggedIn = false; return json({success: true}); }
  if (url.pathname === '/api/custom-source/list') return json([
    {id: 'ready', enabled: true, status: 'success', supportedSources: ['kw', 'kg', 'tx', 'wy', 'mg'], disabledSources: ['mg']},
    {id: 'disabled', enabled: false, status: 'success', supportedSources: ['mg']},
  ]);
  const song = {name: '接口测试歌曲', singer: '测试数据', songmid: 'fixture-1', img: 'http://10.0.2.2:18765/cover.png', source: 'kw', interval: '00:30'};
  const nestedSong = {id: 'kw_fixture-1', name: song.name, singer: song.singer, source: 'kw', interval: '00:30',
    meta: {songId: 'fixture-1', albumName: '收藏中的嵌套歌曲', picUrl: song.img, qualitys: [{type: '128k'}]}};
  if (url.pathname === '/api/user/list') return json({loveList: [nestedSong], defaultList: [], userList: [{id: 'custom', name: '测试歌单', list: [nestedSong]}]});
  if (url.pathname === '/api/user/library/artists') return json([{id: 'artist', name: '收藏测试歌手', source: 'kw', picUrl: ''}]);
  if (url.pathname === '/api/user/library/albums') return json([{id: 'album', name: '收藏测试专辑', artistName: '测试歌手', source: 'kw', picUrl: ''}]);
  if (url.pathname === '/api/music/artistSongs') return json([song]);
  if (url.pathname === '/api/music/albumSongs') return json({list: [song]});
  if (url.pathname === '/api/music/songList/tags') return json({tags: [{name: '风格', list: [{id: 'pop', name: '流行'}]}], sortList: [{id: '5', name: '推荐'}, {id: '6', name: '最热'}]});
  if (url.pathname === '/api/music/songList/list' || url.pathname === '/api/music/songList/search') return json({list: [{id: 'discovery', name: '测试发现歌单', author: '仅测试数据', play_count: '100', source: url.searchParams.get('source')}], total: 1, limit: 20});
  if (url.pathname === '/api/music/songList/detail') return json({list: [{...song, source: url.searchParams.get('source')}], total: 1, limit: 20});
  if (url.pathname === '/api/music/lyric') return json({lyric: '[00:00.00]第一行歌词\n[00:02.00]第二行歌词\n[00:05.00]第三行歌词', tlyric: '[00:00.00]First line\n[00:02.00]Second line'});
  if (url.pathname === '/api/music/search') {
    const source = url.searchParams.get('source');
    if (source === 'kg' && url.searchParams.get('name') === 'partial') return json({error: 'Test partial failure'}, 500);
    return json({list: [{name: '接口测试歌曲', singer: '测试数据', songmid: 'fixture-1', img: 'http://10.0.2.2:18765/cover.png', source, interval: '00:30', albumName: '仅自动化测试'}], hasMore: false});
  }
  if (url.pathname === '/api/music/url') {
    resolutionCount++;
    lastExcluded = data.excludeApiSources || [];
    if (data.songInfo?.songmid === 'fixture-recovery') {
      const failed = !lastExcluded.includes('fixture-bad');
      return json({url: `http://10.0.2.2:${port}/${failed ? 'broken.wav' : 'fixture.wav'}`, type: data.quality,
        sourceId: failed ? 'fixture-bad' : 'fixture-good', hasMoreSources: failed});
    }
    if (req.headers['x-user-name'] !== 'fixture-user' || data.songInfo?.songmid !== 'fixture-1') return json({error: 'Invalid contract'}, 400);
    if (data.quality === 'hires') return json({error: 'Fixture quality unavailable'}, 500);
    const type = data.quality === 'flac24bit' ? '320k' : data.quality;
    return json({url: `http://10.0.2.2:${port}/fixture.wav?quality=${type}`, type});
  }
  return json({error: 'Not found'}, 404);
});
server.listen(port, '127.0.0.1', () => console.log(`Test-only fixture listening on 127.0.0.1:${port}`));
