# mail-weaver

メールを整理し、必要な情報を必要なタイミングで届けるメールアシスタント。
将来はローカルモデルによる内容別の振り分け、メルマガのアーカイブと日次サマリーを目指します。

## 現在の実装

Issue #1の共通開発基盤と、Issue #2の送信者許可判定を含みます。
CLI、JMAP接続、SQLiteへの永続化はまだ実装していません。

## CI

GitHub Actionsの`OCaml CI`は、main向けPR（Draftを含む）とmainへのpushで実行します。
Ubuntu 24.04 x86_64の1環境を使い、タイムアウトは45分です。
PRではGitHubが作るマージコミット、pushではpush先のコミットを検証し、
checkoutしたSHAをログに記録します。

CI環境の復旧制御をシェルテストで確認し、
環境構築後、次のコマンドをそれぞれ別ステップで実行します。
既存の開発環境では、プロジェクトルートから同じコマンドで再現できます。

```sh
opam exec -- ./scripts/check-static.sh
opam exec -- dune build @fmt
opam exec -- dune build
opam exec -- dune runtest --force
```

静的チェックはコンパイラの型チェック・警告を使い、追加linterは導入しません。
チェックが失敗しても環境構築が成功していれば残りのチェックを実行し、
非0終了はジョブの失敗として扱います。キャンセル時は停止します。
整形チェックはソースを書き換えず、テストは`--force`で毎回実行します。
CIは書き込み権限・秘密情報・実メールを使わず、自動コミットや成果物のアップロードも行いません。

### UbuntuでCI環境を新規構築する

CIは`./scripts/setup-ci.sh <新規ディレクトリの絶対パス>`を使い、
opam 2.6.1 / OCaml 5.4.1 / Dune 3.24.2 / OCamlFormat 0.29.0を導入します。
opamの公式Linuxバイナリはスクリプトに記録したSHA-256で検証します。
opam-repositoryは`eba24de6376079a3f9dfa4a9c9ca842475cd1bbc`に固定し、
間接依存を含む導入パッケージ一覧をログに残します。
OCamlFormatの導入に`--with-test`は付けません。

Ubuntu 24.04 x86_64で、OS依存を先に用意します。
この`apt-get`操作はOS全体へパッケージを導入します。

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential pkg-config m4 unzip bubblewrap rsync git curl \
  ca-certificates bzip2 patch
```

続いて、bashからプロジェクトルートで実行します。

```bash
ci_parent=$(mktemp -d)
ci_dir="$ci_parent/environment"
./scripts/setup-ci.sh "$ci_dir"
(
  set -e
  source "$ci_dir/environment.sh"
  opam exec -- ./scripts/check-static.sh
  opam exec -- dune build @fmt
  opam exec -- dune build
  opam exec -- dune runtest --force
)
# 確認後、今回作成した隔離環境を削除する。
rm -rf -- "$ci_parent"
```

スクリプトはUbuntu 24.04 x86_64以外では変更前に停止し、既存ディレクトリへの上書きを拒否します。
指定先の配下にバイナリ・opam root・`ci` switch・一時ファイルを配置し、
既存の`default` switch、個人のopam設定、シェル設定は変更しません。
途中で失敗した場合も既存ディレクトリは再利用せず、確認後に削除して新しい指定先で再実行してください。

上記の直接実行はActionsキャッシュを使わず、毎回新しいディレクトリから構築します。
固定するのはツールと依存メタデータです。ランナーイメージやOSパッケージ全体の
完全な再現性を保証するものではありません。バージョン更新時はスクリプト、
既存チェックの固定値、READMEを合わせて更新して検証してください。

### CIのツール・依存キャッシュ

Actionsでは`$RUNNER_TEMP/mail-weaver-ci`の`bin/`と`root/`だけをキャッシュします。
opamバイナリ、OCamlコンパイラ、Dune、OCamlFormat、依存パッケージと、
保存時の絶対パスを含みます。個人のopam root、設定、認証情報、メールデータ、
`tmp/`、`environment.sh`、プロジェクトのビルド・テスト成果物は含めません。
OS依存の導入は毎回行い、Dune共有キャッシュは引き続き無効です。

キーは世代番号、OS、Ubuntu 24.04、アーキテクチャと、CI構築スクリプト・
ワークフロー・Duneおよびopamの依存宣言のハッシュから生成します。
固定ツールのバージョンとopam-repository SHAの変更は構築スクリプトのハッシュに
反映されます。`restore-keys`は使わず、完全一致したキャッシュだけを採用します。

`scripts/prepare-ci.sh <true|false>`がActionsの完全一致ヒットの有無を受け取り、
固定したCI専用パスを準備します。ヒット時は`setup-ci.sh --restore <絶対パス>`で
保存先の絶対パス・opamバイナリのSHA-256・全ツールのバージョン・switchのパスを検証します。
リポジトリ設定と間接依存の一覧の変化は個別に比較せず、環境変更はキャッシュキーで識別します。
一時ディレクトリと`environment.sh`は毎回生成します。

復元失敗・不整合時は警告を残してCI専用パスだけを破棄し、新規構築を1回試します。
再構築失敗はCI失敗です。環境準備成功後はヒット・ミス・復旧のいずれでも全4チェックを
実行し、テストは`--force`で毎回実行します。コードのチェック失敗では再構築しません。
準備結果（`hit` / `miss` / `recovered`）をログに記録します。準備時間の比較には
Actionsのキャッシュ復元ステップと環境準備ステップの所要時間の合計を使います。

保存するのは完全一致のミスかつ全チェック成功時だけで、mainへのpushと同一リポジトリのPRが対象です。
fork PRは復元のみとし、トークン権限は`contents: read`のままです。
[GitHubのキャッシュ分離](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#restrictions-for-accessing-a-cache)により、
PRのmerge refに保存したキャッシュをmainや他のPRが復元することはできません。

既存キャッシュは同じキーで上書きできません。不整合が続く場合はGitHubのActions画面で
該当キャッシュを削除するか、ワークフローの`CI_CACHE_EPOCH`を更新してください。
自動復旧はその実行の環境を再構築するもので、保存済みキャッシュ自体は修復しません。
CIで一時的に無効化する場合は、復元・保存の両ステップを`if: ${{ false }}`で省略します。
ローカルでキャッシュなしの構築を再現する場合は、前節の既存手順を使用できます。

復旧制御と削除範囲は、一時領域と偽setupを使う6ケースのシェルテストで確認できます。
実opamの動作とActionsのキャッシュヒットはこのテストの検証対象に含みません。

```sh
bash test/ci_cache_test.sh
```

Issue #16では、実CIのミス→ヒットでの成功、準備時間の比較、ヒット時のテスト失敗検出を
別途確認します。独立したキャッシュ無効実行とマージ後mainの実測は今回の完了条件に含めません。

### CI導入の検証記録

導入時には専用Draft PRで、警告27・未整形コード・テスト期待値の違反を
1種類ずつ追加・除去し、対象ステップの診断と無関係なチェックの成功を確認します。
実行URL・checkout SHA・各チェック結果はPR本文に記録し、意図的な違反はmainへマージしません。
完了状態は「ローカル検証済み」「PR上で正常・異常検証済み」
「マージ後のmain push確認済み」に分け、最後の確認まではIssue全体を完了扱いにしません。

## 送信者の許可判定

`lib/sender_policy.ml`の`decide ~from ~allowed`が、Fromアドレス一覧と許可済みアドレス一覧から配送先候補を返す純粋関数です。

| From | 許可リスト | 判定 |
| --- | --- | --- |
| 1件 | 一致するアドレスあり | `Inbox` |
| 1件 | 一致するアドレスなし | `Pending Sender_not_allowed` |
| 欠落・0件 | 任意 | `Pending Missing_from` |
| 2件以上 | 一部／全部が許可済みでも | `Pending Multiple_from` |

入力の前提:

- 各アドレスはASCIIの`local-part@domain`形式で、`@`を1つだけ含む。quoted local-part、国際化アドレス、表示名は入力に含まれず、構文検証は行わない。
- 一致判定はアドレス全体の完全一致。比較時はFrom・許可リスト双方のドメイン部分だけASCII小文字化し、ローカル部の大小文字は区別する。
- 表示名、ドメインのみの一致、部分一致、`+`タグの除去やGmailのドット除去などのサービス固有の同一視では許可しない。
- 同じ入力は常に同じ結果を返し、入力は書き換えない。送信者認証（SPF/DKIM/DMARC）は責務外。

## v0.1.0の範囲

- OCaml CLI、Fastmail JMAP、SQLiteを使う。
- 未承認の送信者は承認待ちへ、明示的に許可した送信者は受信箱へ振り分ける。
- 迷惑メール・送信者ブロックはメールサービス側に任せる。
- 本文・添付取得、LLM、Web UI、自動アーカイブ・削除は対象外とする。
- 利用者がアーカイブ・削除したメールを、自動で受信箱へ戻さない。
- 実行ホストの停止中に処理が滞留することは許容する。

## 開発環境

共通環境はopam 2.6.1の既存の`default` switchで管理しています。
比較する実装では、次のバージョンを共通で使用してください。

| ツール | バージョン |
| --- | --- |
| OCaml | 5.4.1 |
| Dune | 3.24.2 |
| OCamlFormat（開発用） | 0.29.0 |

新しいチェックアウトで、既存のswitchを現在のシェルに反映して確認します。
switchの再作成やグローバル設定の変更は不要です。

```sh
eval "$(opam env --switch=default)"
ocaml -version
dune --version
```

実装・テストにはOCaml標準ライブラリとDuneを使用し、整形には開発用のOCamlFormatを使用します。
上記バージョンが導入済みなら、追加の導入操作は不要です。
既存のOCaml 5.4.1のswitchにDuneだけが不足している場合の導入コマンドは次のとおりです。

```sh
opam install --switch=default dune.3.24.2
```

プロジェクトルートでビルド・テストします。

```sh
dune build
dune runtest
```

`test/smoke.ml`は標準ライブラリを使う小さなプログラムです。
`dune runtest`がコンパイル・実行し、成功時に`smoke test passed`を出力します。
再実行して出力を確認する場合は`dune runtest --force`を使います。

## 整形

OCamlFormat 0.29.0と`profile=default`をルートの`.ocamlformat`で固定しています。
異なるバージョンのOCamlFormatではバージョンチェックが失敗します。
現在使用するswitchを確認し、そのswitchに導入してください。
OCaml 5.4.1 / Dune 3.24.2は開発環境の手順で用意します。

```sh
opam switch show
opam install ocamlformat.0.29.0
eval "$(opam env)"
ocamlc -version
dune --version
ocamlformat --version
```

OCamlFormat自身のテスト用依存には`dune < 3.22`の制約があるため、
この導入に`--with-test`は指定しません。プロジェクトのテストは別途実行します。

プロジェクトルートで次を実行します。

```sh
# ソースを書き換えて整形
dune fmt

# ソースを書き換えず、未整形なら差分を表示して非0終了
dune build @fmt
```

チェックには`--auto-promote`を付けません。差分を確認して`dune fmt`で修正し、
チェックを再実行してください。ビルドディレクトリには整形結果が生成されます。

対象はプロジェクト内の`.ml` / `.mli`で、`lib/`の実装・インターフェースと
`test/`のテストを含みます。`dune-project`の`enabled_for ocaml`で
Duneファイルの整形は対象外にしています。
生成物とインストール済み外部依存は独自に走査せず、Dune標準の探索を使用します。
`_build/`、`_build-static-check/`、`_opam/`などは探索対象外です。
将来、外部ソースをリポジトリ内に取り込む場合はDuneの`vendored_dirs`で指定します。
特定のエディタや独自スクリプトは不要です。

ローカルと将来のCIでは、同じ固定バージョンのツールで次を実行します。
整形チェックと静的チェックは独立した入口とし、CIワークフローは別途導入します。

```sh
dune build @fmt
./scripts/check-static.sh
dune runtest
```

## 静的チェック

開発環境の手順でOCaml 5.4.1 / Dune 3.24.2を用意した後、次を実行します。
追加パッケージは不要です。ローカルと将来のCIで共用する入口はこのスクリプトです。
リポジトリ内外のどのディレクトリからでも、スクリプトのパスを指定して実行できます。

```sh
./scripts/check-static.sh
```

型チェックとコンパイラ警告を利用し、Duneが管理する実装（`.ml`）、
インターフェース（`.mli`）、テストをコンパイルします。テストの実行は
`dune runtest`で別途行います。生成物や外部依存をソースとして独自に走査しません。
整形はformatterの責務とし、このチェックでは整形も自動修正も行いません。

### 警告の方針

ルートの`dune`で通常開発と同じ`dev`プロファイルに設定を集約しています。
`:standard`で標準設定を継承し、`-w`で次の警告だけを追加で有効化します。
標準で有効な警告を無効化する指定はありません。

| 追加する警告番号 | 検出対象 |
| --- | --- |
| 27 | 未使用の引数など |
| 32–39 | 未使用の値・open・型・ループ変数・祖先・コンストラクタ・拡張・rec |
| 50 | 不適切な位置のドキュメントコメント |
| 60 | 未使用のモジュール |
| 66 | 未使用の`open!` |
| 67 | 未使用のファンクタ引数 |
| 69 | 未使用のレコードフィールド |
| 74 | 全域に見えても部分的なマッチとしてコンパイルされるパターンマッチ |

有効化とエラー化は別です。Dune 3.24.2の`dev`既定値である
`-warn-error +a`を継承し、有効な警告はすべてエラーとして扱います。
非推奨APIの`deprecated`アラートも`-alert +deprecated++deprecated`で
明示的に有効化し、エラーにします。独自の警告抑制はありません。
標準で無効な警告は、上記の追加対象以外はコンパイラの既定値に従います。

指摘されたファイル・行・警告番号を確認し、不要な宣言の削除やマッチの補完など、
必要最小限の修正を行って再実行してください。警告の説明は
`ocamlc -warn-help`で確認できます。意図的な未使用引数には`_`または`_`から始まる
名前を使います。個別の警告抑制が必要な場合は、対象箇所に限定し、理由をコメントに
記録してください。コンパイラ更新時に新しく標準で有効になった警告も検出対象とし、
固定バージョンの更新と合わせて対応を判断します。

追加linterは今回導入しません。調査時点の
[Zanuda 2.1.0](https://opam.ocaml.org/packages/zanuda/zanuda.2.1.0/)は
OCaml 5.4系が依存条件に含まれていません。
[Camelot 2.1.0](https://opam.ocaml.org/packages/camelot/camelot.2.1.0/)は
OCaml 5.4.1に対応していますが、現段階ではコンパイラで検出できる範囲を基盤とし、
追加ルール・依存の管理負担を増やさない方針です。

### 増分ビルドと環境

チェックは専用の`_build-static-check/`で増分ビルドを行います。
このディレクトリへのビルドは共通スクリプトからだけ行ってください。
通常ビルドの`_build/`は再利用せず、Duneの共有キャッシュも無効化します。
警告のエラー化を抑制して作った成果物を、抑制解除後もDuneが再利用し、
違反があるのに成功する事象を確認したためです。
専用ディレクトリ内の増分成果物は保持し、変更なしの再実行では再コンパイルを省きます。

必要なときだけ、専用成果物を削除して再チェックできます。
通常ビルドの成果物は削除しません。

```sh
./scripts/check-static.sh --clean
```

スクリプトはOCaml・Duneの固定バージョンを確認し、`OCAMLPARAM`を子プロセス内で
解除します。Duneには`--no-config`と`--profile dev`を明示します。
ツール不足・バージョン不一致・違反は非0終了になります。
これらは使用ツールとチェック設定の確認であり、OS・システム依存・switchの内容などを
含む環境全体の再現性を保証するものではありません。

## ローカルデータ

ビルド成果物、ローカルswitch、環境変数ファイル、認証情報、ローカルDB、メールデータはGit管理から除外します。
実メールや認証情報をコミットしないでください。設定例を追加する場合はダミー値だけを使用してください。

## 比較の開始点

Issue #1のPRをマージした後、そのmainのコミットSHAを記録し、同じSHAからGPT用・Fugu用の独立したworktreeを作ります。
送信者判定の実装はIssue #2で扱います。
