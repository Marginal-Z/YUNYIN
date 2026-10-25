import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/downloads.dart';
import '../../data/local_library.dart';
import '../../data/models.dart';
import '../common/actions.dart';
import '../common/song_row.dart';

Future<void> runImport(BuildContext context, {bool folder = false, bool scan = false}) async {
  final lib = context.read<LocalLibrary>();
  try {
    final r = scan ? await lib.scanDevice() : (folder ? await lib.importFolder() : await lib.importFiles());
    if (r == null || !context.mounted) return;
    Toast.show(
      context,
      r.added == 0 ? (scan && r.skipped == 0 ? '没有找到歌曲文件' : '没有新的歌曲（已跳过 ${r.skipped} 个）') : '已导入 ${r.added} 首${r.skipped > 0 ? '，跳过 ${r.skipped} 个' : ''}',
      icon: YIcons.download,
    );
  } catch (e) {
    if (context.mounted) Toast.show(context, '导入失败：${errorText(e)}', icon: YIcons.info);
  }
}

/// 导入按钮：扫描本机歌曲、导入文件；桌面端还可以导入整个文件夹。
class LocalImportBar extends StatelessWidget {
  const LocalImportBar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lib = context.watch<LocalLibrary>();
    if (!lib.supported) return const SizedBox.shrink();
    if (lib.importing || lib.enriching) {
      return YCard(
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accentText)),
              const SizedBox(width: 12),
              Text(lib.progress ?? '正在导入…', style: ts(15, color: p.text)),
            ],
          ),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: PrimaryButton(
            label: '扫描本机歌曲',
            icon: YIcons.search,
            iconSize: 18,
            height: 46,
            fontSize: 15,
            expand: true,
            onTap: () => runImport(context, scan: true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SecondaryButton(label: '导入文件', icon: YIcons.plus, iconSize: 18, height: 46, fontSize: 15, onTap: () => runImport(context)),
        ),
        if (lib.canImportFolder) ...[
          const SizedBox(width: 10),
          Expanded(
            child: SecondaryButton(label: '导入文件夹', icon: YIcons.folder, iconSize: 18, height: 46, fontSize: 15, onTap: () => runImport(context, folder: true)),
          ),
        ],
      ],
    );
  }
}

/// 乐库“本地”：导入的本地音乐 + 已下载的歌曲。
class LocalMusicList extends StatelessWidget {
  const LocalMusicList({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LocalLibrary>();
    final dl = context.watch<DownloadManager>();
    final local = lib.songs;
    final downloads = dl.items;
    Widget list(List<Song> songs, String title) => CardList(
      indent: 70,
      children: [
        for (var i = 0; i < songs.length; i++)
          SongRow(
            song: songs[i],
            onTap: () => playAll(context, songs, start: i, title: title),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LocalImportBar(),
          const SizedBox(height: 18),
          if (local.isEmpty)
            YCard(
              child: StateView.empty(title: '还没有本地音乐', message: '支持 MP3、FLAC、M4A、OGG、WAV 等格式，会读取歌名、歌手、封面与歌词。', icon: YIcons.library),
            )
          else ...[
            SectionHeader(
              '本地音乐 · ${local.length} 首',
              top: 0,
              action: '全部播放',
              onAction: () => playAll(context, local, title: '本地音乐'),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Pressable(
                onTap: lib.enriching || lib.importing
                    ? null
                    : () async {
                        final n = await lib.enrichOnline();
                        if (context.mounted) Toast.show(context, n > 0 ? '已为 $n 首歌曲补全歌词或封面' : '没有需要补全的歌曲', icon: YIcons.check);
                      },
                child: Text(
                  '联网补全缺少的歌词与封面',
                  style: ts(13, weight: w600, color: Palette.of(context).accentText),
                ),
              ),
            ),
            list(local, '本地音乐'),
          ],
          if (downloads.isNotEmpty) ...[SectionHeader('已下载 · ${downloads.length} 首'), list(downloads, '已下载')],
        ],
      ),
    );
  }
}
