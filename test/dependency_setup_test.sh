#!/bin/sh
set -eu

fixture=$(mktemp -d "${TMPDIR:-/tmp}/mail-weaver-deps-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$fixture/project/scripts" "$fixture/root" "$fixture/bin"
cp "$1" "$fixture/project/scripts/install-deps.sh"
installer="$fixture/project/scripts/install-deps.sh"
: > "$fixture/root/config"
: > "$fixture/project/mail_weaver.opam"
cat > "$fixture/bin/opam" <<'OPAM'
#!/bin/sh
: > "$OPAM_CALLED"
exit 99
OPAM
chmod +x "$fixture/bin/opam"
export PATH="$fixture/bin:$PATH" OPAM_CALLED="$fixture/opam-called"

expect_refusal() {
  expected_status=$1
  expected_message=$2
  shift 2
  status=0
  sh "$installer" "$@" > "$fixture/output" 2>&1 || status=$?
  if [ "$status" -ne "$expected_status" ] ||
    ! grep -F "$expected_message" "$fixture/output" >/dev/null; then
    cat "$fixture/output" >&2
    printf '予期した拒否結果と一致しません（終了値: %s）。\n' "$status" >&2
    exit 1
  fi
  [ ! -e "$OPAM_CALLED" ] || { printf '拒否前に opam が呼ばれました。\n' >&2; exit 1; }
}

expect_refusal 2 '使い方:'
expect_refusal 1 '絶対パス' relative issue19
expect_refusal 1 'default 以外' "$fixture/root" default
expect_refusal 1 'default 以外' "$fixture/root" /isolated/default
expect_refusal 1 '初期化されていません' "$fixture/missing-root" issue19
expect_refusal 1 'mail_weaver.opam.locked がありません' "$fixture/root" issue19
rm "$fixture/project/mail_weaver.opam"
expect_refusal 1 'mail_weaver.opam がありません' "$fixture/root" issue19
printf 'dependency setup guard tests passed (7 cases)\n'
