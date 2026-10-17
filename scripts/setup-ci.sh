#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 || $1 != /* ]]; then
  echo '使い方: scripts/setup-ci.sh <新規ディレクトリの絶対パス>' >&2
  exit 2
fi

if [[ $(uname -s) != Linux || $(uname -m) != x86_64 || ! -f /etc/os-release ]]; then
  echo 'Ubuntu 24.04 x86_64で実行してください。' >&2
  exit 1
fi
# OSの確認は、ファイルを作成する前に行う。
source /etc/os-release
if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 ]]; then
  echo 'Ubuntu 24.04 x86_64で実行してください。' >&2
  exit 1
fi

for tool in curl sha256sum git gcc make pkg-config m4 unzip bwrap rsync bzip2 patch tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool がありません。READMEのCI環境構築手順を確認してください。" >&2
    exit 1
  fi
done

ci_dir=$1
# mkdir自身にも存在チェックを任せ、既存ディレクトリ・symlinkを上書きしない。
mkdir -m 700 -- "$ci_dir"
ci_dir=$(cd -- "$ci_dir" && pwd -P)
mkdir -- "$ci_dir/bin" "$ci_dir/tmp"

# 呼び出し元のopam設定・コンパイラ設定を専用環境へ持ち込まない。
while IFS= read -r variable; do
  unset "$variable"
done < <(compgen -e | sed -n '/^OPAM/p')
unset OCAMLPARAM OCAMLLIB CAML_LD_LIBRARY_PATH OCAML_TOPLEVEL_PATH
export OPAMROOT="$ci_dir/root" OPAMSWITCH=ci OPAMYES=1 OPAMJOBS=2
export OPAMNOSELFUPGRADE=1 TMPDIR="$ci_dir/tmp" DUNE_CACHE=disabled
export PATH="$ci_dir/bin:$PATH"

opam_version=2.6.1
opam_sha256=b533d393a6967150d6ef41cb3d71e147e93ecbabeb59e921aa412c0ae79ebe3d
repository_sha=eba24de6376079a3f9dfa4a9c9ca842475cd1bbc
curl --fail --location --retry 3 \
  "https://github.com/ocaml/opam/releases/download/$opam_version/opam-$opam_version-x86_64-linux" \
  --output "$ci_dir/tmp/opam"
printf '%s  %s\n' "$opam_sha256" "$ci_dir/tmp/opam" | sha256sum --check --strict
install -m 755 -- "$ci_dir/tmp/opam" "$ci_dir/bin/opam"

opam init --bare --no-setup --no-opamrc \
  default "git+https://github.com/ocaml/opam-repository.git#$repository_sha"
opam switch create ci ocaml-base-compiler.5.4.1
# OCamlFormatの依存テストは、固定したDuneとの制約が合わないため導入しない。
opam install dune.3.24.2 ocamlformat.0.29.0

[[ $(opam --version) == "$opam_version" ]]
[[ $(opam exec -- ocamlc -version) == 5.4.1 ]]
[[ $(opam exec -- dune --version) == 3.24.2 ]]
[[ $(opam exec -- ocamlformat --version) == 0.29.0 ]]
printf 'opam: %s\nopam-repository: %s\n' "$opam_version" "$repository_sha"
opam list --installed --columns=name,version

# bashのsourceで利用する。パスに空白や引用符があっても展開できるようにする。
{
  cat <<'ENV'
while IFS= read -r ci_opam_variable; do
  unset "$ci_opam_variable"
done < <(compgen -e | sed -n '/^OPAM/p')
unset ci_opam_variable
ENV
  printf 'export PATH=%q:"$PATH"\n' "$ci_dir/bin"
  printf 'export OPAMROOT=%q OPAMSWITCH=ci OPAMNOSELFUPGRADE=1\n' "$OPAMROOT"
  printf 'export TMPDIR=%q DUNE_CACHE=disabled\n' "$TMPDIR"
  printf 'unset OCAMLPARAM OCAMLLIB CAML_LD_LIBRARY_PATH OCAML_TOPLEVEL_PATH\n'
} > "$ci_dir/environment.sh"
printf '環境構築完了: %s/environment.sh\n' "$ci_dir"
