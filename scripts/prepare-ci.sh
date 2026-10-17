#!/usr/bin/env bash
set -euo pipefail

# Actionsの復元結果だけを受け取り、削除先はRUNNER_TEMP直下に固定する。
if [[ $# != 1 || ( $1 != true && $1 != false ) || ${RUNNER_TEMP:-} != /* ]]; then
  echo '使い方: RUNNER_TEMP=<絶対パス> scripts/prepare-ci.sh <true|false>' >&2
  exit 2
fi
runner_dir=$(cd -- "$RUNNER_TEMP" && pwd -P)
[[ $runner_dir != / ]]
ci_dir="$runner_dir/mail-weaver-ci"
setup_script="$(cd -- "$(dirname -- "$0")" && pwd -P)/setup-ci.sh"
started=${CI_PREP_STARTED:-$(date +%s)}
[[ $started =~ ^[0-9]+$ ]]
mode=miss

if [[ $1 == true ]]; then
  if "$setup_script" --restore "$ci_dir"; then
    mode=hit
  else
    mode=recovered
    echo '::warning::CIキャッシュの検証に失敗しました。専用環境を破棄して1回だけ新規構築します。繰り返す場合はキャッシュ削除または世代番号更新が必要です。' >&2
  fi
fi

if [[ $mode != hit ]]; then
  # 復元途中の残骸も除去する。symlinkは辿らず、固定した子パスだけを削除する。
  rm -rf -- "$ci_dir"
  "$setup_script" "$ci_dir"
fi
elapsed=$(( $(date +%s) - started ))
printf 'CI環境: %s、準備時間（復元を含む）: %s秒\n' "$mode" "$elapsed"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  printf 'CI環境: %s、準備時間（復元を含む）: %s秒\n' "$mode" "$elapsed" >> "$GITHUB_STEP_SUMMARY"
fi
