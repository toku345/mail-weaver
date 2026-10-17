#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
test_dir=$(mktemp -d)
test_dir=$(cd -- "$test_dir" && pwd -P)
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -- "$test_dir/scripts" "$test_dir/runner with spaces" "$test_dir/outside"
cp -- "$project_root/scripts/prepare-ci.sh" "$test_dir/scripts/"
export RUNNER_TEMP="$test_dir/runner with spaces" CALLS="$test_dir/calls"
ci_dir="$RUNNER_TEMP/mail-weaver-ci"
cat > "$test_dir/scripts/setup-ci.sh" <<'SETUP'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CALLS"
if [[ $1 == --restore ]]; then
  [[ -f $2/valid ]]
  if [[ ${FAIL_RESTORE:-0} == 1 ]]; then
    false
    touch "$RUNNER_TEMP/should-not-exist"
  fi
  exit 0
fi
[[ ! -e $1 && ! -L $1 ]]
[[ ${FAIL_BUILD:-0} == 0 ]] || exit 19
mkdir -- "$1"
SETUP
chmod +x "$test_dir/scripts/setup-ci.sh"
prepare="$test_dir/scripts/prepare-ci.sh"

# 1. 正常ヒットは構築しない。
mkdir -- "$ci_dir"
printf cached > "$ci_dir/valid"
"$prepare" true > "$test_dir/log" 2>&1
[[ $(cat "$CALLS") == "--restore $ci_dir" && $(cat "$ci_dir/valid") == cached ]]
echo 'ok - hit skips build'

# 2. ミスは残骸を除去して1回構築する。
: > "$CALLS"
touch "$ci_dir/partial"
"$prepare" false > "$test_dir/log" 2>&1
[[ $(cat "$CALLS") == "$ci_dir" && ! -e $ci_dir/partial ]]
echo 'ok - miss clears partial restore and builds once'

# 3. 復元の途中失敗後は後続処理を実行せず、警告付きで1回再構築する。
touch "$ci_dir/valid"
: > "$CALLS"
FAIL_RESTORE=1 "$prepare" true > "$test_dir/log" 2>&1
[[ $(wc -l < "$CALLS") -eq 2 && ! -e $RUNNER_TEMP/should-not-exist && ! -e $ci_dir/valid ]]
[[ $(cat "$test_dir/log") == *'::warning::'* ]]
echo 'ok - restore failure rebuilds once with warning'

# 4. 再構築失敗を伝播し、再試行しない。
: > "$CALLS"
status=0
FAIL_BUILD=1 "$prepare" true > "$test_dir/log" 2>&1 || status=$?
[[ $status -eq 19 && $(wc -l < "$CALLS") -eq 2 ]]
echo 'ok - rebuild failure propagates without retry'

# 5. symlink先のデータは削除しない。
printf keep > "$test_dir/outside/keep"
ln -s -- "$test_dir/outside" "$ci_dir"
"$prepare" false > "$test_dir/log" 2>&1
[[ $(cat "$test_dir/outside/keep") == keep && ! -L $ci_dir ]]
echo 'ok - cleanup preserves symlink target'

# 6. 不正な入力では削除もsetupも行わない。
printf keep > "$ci_dir/keep"
: > "$CALLS"
for runner in / relative ''; do
  if RUNNER_TEMP="$runner" "$prepare" false > "$test_dir/log" 2>&1; then exit 1; fi
done
if "$prepare" invalid > "$test_dir/log" 2>&1; then exit 1; fi
[[ ! -s $CALLS && $(cat "$ci_dir/keep") == keep ]]
echo 'ok - invalid input never deletes or builds'
