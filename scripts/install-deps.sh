#!/bin/sh
set -eu

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

if [ "$#" -ne 2 ]; then
  printf '使い方: %s OPAM_ROOT SWITCH\n' "$0" >&2
  exit 2
fi

dependency_root=$1
dependency_switch=$2
case "$dependency_root" in
  /*) ;;
  *) fail 'opam root は既存の専用環境の絶対パスで指定してください。' ;;
esac
case "$dependency_switch" in
  ''|default|*/default|-*) fail 'default 以外の専用 switch を明示してください。' ;;
esac
[ -f "$dependency_root/config" ] || fail '指定した opam root は初期化されていません。'

# 呼び出し元の設定で依存条件や厳密な制約を変えない。
unset OPAMLOCKED OPAMWITHTEST OPAMWITHDOC OPAMWITHDEVSETUP \
  OPAMBUILDTEST OPAMBUILDDOC OPAMBESTEFFORT OPAMIGNORECONSTRAINTS \
  OPAMIGNOREAVAILABLE OPAMSKIPVERSIONCHECKS
export OPAMROOT="$dependency_root" OPAMSWITCH="$dependency_switch"
opam_cmd() {
  opam_subcommand=$1
  shift
  opam "$opam_subcommand" --cli=2.2 --root="$dependency_root" \
    --switch="$dependency_switch" "$@"
}

project_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$project_root"
[ -f mail_weaver.opam ] || fail 'mail_weaver.opam がありません。'
[ -f mail_weaver.opam.locked ] || fail 'mail_weaver.opam.locked がありません。未固定での導入は行いません。'
resolved_switch=$(opam_cmd switch show)
[ "$resolved_switch" != default ] || fail 'default switch には導入できません。'
pinned_packages=$(opam_cmd list --pinned --short)
[ -z "$pinned_packages" ] || fail 'pin のない専用 switch を使用してください。'

opam_cmd install --yes --deps-only --locked ./mail_weaver.opam
# --locked は元の定義を置き換えるため、元の制約も別途確認する。
opam_cmd install --deps-only --check ./mail_weaver.opam
opam_cmd exec -- dune build --no-config @opam

lock_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/mail-weaver-lock.XXXXXX")
trap 'rm -rf "$lock_check_dir"' EXIT
trap 'exit 1' HUP INT TERM
cp mail_weaver.opam "$lock_check_dir/mail_weaver.opam"
# opam lock の出力先はカレントディレクトリなので、一時領域へ移動する。
(cd "$lock_check_dir"; opam_cmd lock ./mail_weaver.opam)
# opam 標準のパーサーでコメントと表記差を除いて比較する。
opam_cmd show --just-file --raw ./mail_weaver.opam.locked > "$lock_check_dir/expected"
opam_cmd show --just-file --raw "$lock_check_dir/mail_weaver.opam.locked" > "$lock_check_dir/actual"
if ! cmp -s "$lock_check_dir/expected" "$lock_check_dir/actual"; then
  diff -u "$lock_check_dir/expected" "$lock_check_dir/actual" || :
  fail '依存定義と lock が一致しません。README の更新手順を確認してください。'
fi

opam --version
opam_cmd exec -- ocamlc -version
opam_cmd exec -- dune --version
opam_cmd exec -- ocamlformat --version
opam_cmd list --installed --columns=name,version
