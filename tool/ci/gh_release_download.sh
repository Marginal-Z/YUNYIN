#!/usr/bin/env bash
# 下载 GitHub 发布文件：每一轮先走官方下载地址（github.com/…/releases/download/…），失败时改用 GitHub API
# 下载同一个文件；都失败则稍后重试。github.com 的 releases/download 入口有时整体返回 504，
# 而 API 与文件存储仍然正常；GitHub 整体不稳定时两条路也会间歇失败，多试几轮总能成功。
#
# 用法：gh_release_download.sh <下载地址> <保存路径>
# 设置了 GITHUB_TOKEN 时 API 请求带上它（避免匿名请求的频率限制；跳转到文件存储时 curl 不会转发它）。
set -euo pipefail

url=$1
dest=$2
mkdir -p "$(dirname "$dest")"
part="$dest.part"

re='^https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^/]+)$'
api_ok=false
if [[ $url =~ $re ]]; then
  api_ok=true
  owner=${BASH_REMATCH[1]} repo=${BASH_REMATCH[2]} tag=${BASH_REMATCH[3]} name=${BASH_REMATCH[4]}
  api="https://api.github.com/repos/$owner/$repo"
fi
auth=()
if [ -n "${GITHUB_TOKEN:-}" ]; then auth=(-H "Authorization: Bearer $GITHUB_TOKEN"); fi

for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsSL --max-time 600 -o "$part" "$url"; then
    mv "$part" "$dest"
    exit 0
  fi
  if $api_ok; then
    echo "官方下载地址失败，改用 GitHub API 下载 $owner/$repo $tag/$name"
    id=$(curl -fsSL --max-time 60 ${auth[@]+"${auth[@]}"} "$api/releases/tags/$tag" | jq -r --arg n "$name" '.assets[] | select(.name == $n) | .id' || true)
    if [ -n "$id" ] && curl -fsSL --max-time 600 ${auth[@]+"${auth[@]}"} -H "Accept: application/octet-stream" -o "$part" "$api/releases/assets/$id"; then
      mv "$part" "$dest"
      exit 0
    fi
  fi
  echo "下载失败，20 秒后重试（$i/10）：$url" >&2
  sleep 20
done
rm -f "$part"
echo "下载失败：$url" >&2
exit 1
