// 从 GitHub Releases 读取最新版本，填充下载链接，并按访客的系统推荐安装包。
const REPO = 'Marginal-Z/YUNYIN';
const RELEASES = `https://github.com/${REPO}/releases/latest`;

async function detect() {
  const ua = navigator.userAgent;
  let os = 'unknown';
  if (/Android/i.test(ua)) os = 'android';
  else if (/Windows/i.test(ua)) os = 'windows';
  else if (/Mac OS X|Macintosh/i.test(ua) && !/iPhone|iPad/i.test(ua)) os = 'mac';
  else if (/Linux|X11/i.test(ua)) os = 'linux';
  let arm = /aarch64|arm64/i.test(ua);
  try {
    const hints = await navigator.userAgentData?.getHighEntropyValues(['architecture']);
    if (hints?.architecture) arm = hints.architecture === 'arm';
  } catch (_) {}
  return { os, arm };
}

function recommended({ os, arm }) {
  switch (os) {
    case 'android': return ['android-arm64-v8a.apk', 'Android'];
    case 'windows': return ['windows-x64-setup.exe', 'Windows'];
    case 'linux': return [arm ? 'linux-arm64.AppImage' : 'linux-x64.AppImage', 'Linux'];
    case 'mac': return ['macos-universal.zip', 'macOS'];
    default: return [null, null];
  }
}

function size(bytes) {
  return bytes ? `${(bytes / 1048576).toFixed(1)} MB` : '';
}

// 更新说明是简单的 Markdown：标题、列表与引用。
function renderNotes(md) {
  const esc = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);
  const inline = (s) => esc(s).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/`(.+?)`/g, '<code>$1</code>');
  let html = '';
  let list = false;
  for (const raw of md.split('\n')) {
    const line = raw.trim();
    const item = line.match(/^[-*]\s+(.*)/);
    if (item) {
      if (!list) { html += '<ul>'; list = true; }
      html += `<li>${inline(item[1])}</li>`;
      continue;
    }
    if (list) { html += '</ul>'; list = false; }
    if (!line) continue;
    html += `<p>${inline(line.replace(/^#+\s*|^>\s*/, ''))}</p>`;
  }
  return html + (list ? '</ul>' : '');
}

async function main() {
  const env = await detect();
  const [pick, osName] = recommended(env);
  const primary = document.getElementById('primary-download');
  const label = document.getElementById('primary-label');
  const meta = document.getElementById('release-meta');
  if (osName) {
    label.textContent = `下载 ${osName} 版`;
    document.querySelector(`.platforms article[data-os="${env.os}"]`)?.classList.add('current');
  }

  let release;
  try {
    const r = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: { Accept: 'application/vnd.github+json' } });
    if (!r.ok) throw new Error(r.status);
    release = await r.json();
  } catch (_) {
    meta.innerHTML = `暂时无法获取版本信息，请前往 <a href="${RELEASES}">GitHub Releases</a> 下载。`;
    document.querySelectorAll('[data-asset]').forEach((a) => (a.href = RELEASES));
    return;
  }

  const version = release.tag_name.replace(/^v/, '');
  const assets = new Map(release.assets.map((a) => [a.name, a]));
  const find = (suffix) => assets.get(`YunYin-${version}-${suffix}`);

  document.querySelectorAll('[data-asset]').forEach((a) => {
    const asset = find(a.dataset.asset);
    if (!asset) {
      a.removeAttribute('href');
      a.title = '此版本未提供';
      return;
    }
    a.href = asset.browser_download_url;
    const em = a.querySelector('em');
    const s = size(asset.size);
    if (s) {
      if (em) em.textContent = `${em.textContent} · ${s}`;
      else a.insertAdjacentHTML('beforeend', `<em>${s}</em>`);
    }
  });

  const date = release.published_at ? new Date(release.published_at).toLocaleDateString('zh-CN') : '';
  const best = pick && find(pick);
  if (best) {
    primary.href = best.browser_download_url;
    meta.textContent = `v${version} · ${size(best.size)}${date ? ` · ${date} 发布` : ''}`;
  } else {
    primary.href = '#download';
    meta.textContent = `最新版本 v${version}${date ? ` · ${date} 发布` : ''}`;
  }
  document.getElementById('download-sub').textContent = `最新版本 v${version}，所有安装包由 CI 自动构建并发布在 GitHub Releases。`;

  if (release.body?.trim()) {
    document.getElementById('notes-body').innerHTML = renderNotes(release.body);
    const notes = document.getElementById('notes');
    notes.querySelector('summary').textContent = `v${version} 更新说明`;
    notes.hidden = false;
  }
}

main();
