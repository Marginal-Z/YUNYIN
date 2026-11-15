#!/usr/bin/env bash
# 核对代码里写死的 sherpa-onnx 模型 SHA-256 与 GitHub 发布页当前的文件摘要是否一致。
# 上游偶尔会重新上传同名文件（例如 matcha-icefall-zh-baker 在 2026-11-12 重新上传），写死的校验值随之失效，
# 用户下载时就会一直“校验失败”。发布页给出摘要的文件逐个比对，不一致时失败；没有摘要的旧文件跳过。
#
# 用法：check_model_digests.sh（需要 gh 与 GITHUB_TOKEN 或已登录的 gh）
set -euo pipefail

files=(lib/assistant/voice_models.dart)
digests=$(mktemp)
trap 'rm -f "$digests"' EXIT
for tag in asr-models tts-models vocoder-models kws-models; do
  gh api --paginate "repos/k2-fsa/sherpa-onnx/releases/tags/$tag" --jq '.assets[] | select(.digest != null) | "\(.name) \(.digest | ltrimstr("sha256:"))"' >> "$digests"
done

# 代码里的写法：('文件名', 'sha') 或 '文件名', 'sha'（压缩包可以不带 .tar.bz2）。
pins=$(grep -ohE "'[A-Za-z0-9_.-]+', '[0-9a-f]{64}'" "${files[@]}" | sed -E "s/'([^']+)', '([0-9a-f]{64})'/\1 \2/")
bad=0 checked=0
while read -r name sha; do
  for candidate in "$name" "$name.tar.bz2"; do
    remote=$(awk -v n="$candidate" '$1 == n { print $2; exit }' "$digests")
    [[ -z $remote ]] && continue
    checked=$((checked + 1))
    if [[ $remote != "$sha" ]]; then
      echo "::error::$candidate 的校验值已过期：代码中 $sha，发布页 $remote"
      bad=1
    fi
  done
done <<< "$pins"
# 本机语音 MOSS-TTS-Nano：代码里写 (仓库, '文件名', 大小, 'sha')，与魔搭社区仓库当前的文件摘要比对。
moss=lib/voice/moss/moss_models.dart
for repo in MOSS-TTS-Nano-100M-ONNX MOSS-Audio-Tokenizer-Nano-ONNX; do
  remote_list=$(curl -fsSL "https://modelscope.cn/api/v1/models/openmoss/$repo/repo/files?Recursive=true" | python3 -c 'import json,sys; [print(f["Path"], f["Sha256"]) for f in json.load(sys.stdin)["Data"]["Files"]]') || { echo "::warning::无法读取魔搭社区 $repo 的文件列表，跳过"; continue; }
  var=$([[ $repo == MOSS-TTS* ]] && echo tts || echo codec)
  while read -r name sha; do
    remote=$(awk -v n="$name" '$1 == n { print $2; exit }' <<< "$remote_list")
    checked=$((checked + 1))
    if [[ $remote != "$sha" ]]; then
      echo "::error::MOSS $repo/$name 的校验值已过期：代码中 $sha，魔搭社区 ${remote:-（没有这个文件）}"
      bad=1
    fi
  done < <(grep -oE "\($var, '[A-Za-z0-9_.-]+', [0-9]+, '[0-9a-f]{64}'\)" "$moss" | sed -E "s/\($var, '([^']+)', [0-9]+, '([0-9a-f]{64})'\)/\1 \2/")
done

echo "核对了 $checked 个模型文件"
exit $bad
