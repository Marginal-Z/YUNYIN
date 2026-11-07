import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/core/ui/cover.dart';

void main() {
  test('大尺寸封面地址：QQ 音乐歌单封面换成 600（保留查询参数），榜单最大 500，专辑 800', () {
    expect(hiResCover('https://qpic.y.qq.com/music_cover/abc/300?n=1'), 'https://qpic.y.qq.com/music_cover/abc/600?n=1');
    expect(hiResCover('https://qpic.y.qq.com/music_cover/abc/150'), 'https://qpic.y.qq.com/music_cover/abc/600');
    expect(hiResCover('https://y.gtimg.cn/music/photo_new/T002R300x300M000000MkMni19ClKG.jpg'), 'https://y.gtimg.cn/music/photo_new/T002R800x800M000000MkMni19ClKG.jpg');
    expect(hiResCover('https://y.gtimg.cn/music/photo_new/T003R300x300M000002R5Exz3iO9Km.jpg'), 'https://y.gtimg.cn/music/photo_new/T003R500x500M000002R5Exz3iO9Km.jpg');
    expect(hiResCover('https://imge.kugou.com/stdmusic/400/20200101/x.jpg'), 'https://imge.kugou.com/stdmusic/800/20200101/x.jpg');
  });
}
