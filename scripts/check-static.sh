#!/bin/sh
set -eu

clean=false
case "$#" in
  0) ;;
  1)
    if [ "$1" = "--clean" ]; then
      clean=true
    else
      printf '使い方: %s [--clean]\n' "$0" >&2
      exit 2
    fi
    ;;
  *)
    printf '使い方: %s [--clean]\n' "$0" >&2
    exit 2
    ;;
esac

project_root=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
cd "$project_root"
unset OCAMLPARAM

require_version() {
  tool=$1
  version_option=$2
  expected=$3
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf '%s が見つかりません。READMEの開発環境の手順を確認してください。\n' "$tool" >&2
    exit 1
  fi
  if ! actual=$("$tool" "$version_option"); then
    printf '%s のバージョンを取得できませんでした。\n' "$tool" >&2
    exit 1
  fi
  if [ "$actual" != "$expected" ]; then
    printf '%s のバージョンが一致しません（必要: %s、実際: %s）。\n' \
      "$tool" "$expected" "$actual" >&2
    exit 1
  fi
}

require_version ocamlc -version 5.4.1
require_version dune --version 3.24.2

# 通常ビルドの成果物と、警告抑制付きで保存された共有キャッシュを再利用しない。
check_build_dir=_build-static-check
if [ "$clean" = true ]; then
  dune clean --root . --no-config --profile dev --build-dir "$check_build_dir"
fi
exec dune build --root . --no-config --profile dev \
  --cache=disabled --build-dir "$check_build_dir" @all
