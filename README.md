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

環境構築後、次のコマンドをそれぞれ別ステップで実行します。
既存の開発環境では、プロジェクトルートから同じコマンドで再現できます。

```sh
opam exec -- ./scripts/check-static.sh
opam exec -- dune build @fmt
opam exec -- dune build
opam exec -- dune runtest --force
```

静的チェックはコンパイラの型チェック・警告を使い、追加linterは導入しません。
チェックが失敗しても環境準備と開発ツールの導入が成功していれば残りのチェックを実行し、
非0終了はジョブの失敗として扱います。キャンセル時は停止します。
整形チェックはソースを書き換えず、テストは`--force`で毎回実行します。
CIのトークン権限は`contents: read`のみで、秘密情報・実メールを使わず、自動コミットや成果物のアップロードも行いません。

### GitHub Actionsの更新

Dependabotは毎週月曜9時（日本時間）にGitHub Actionsの更新を確認し、
バージョン更新PRを同時に最大5件まで作成します。SHA固定のActionも対象で、更新PRは既存のCIで検証します。
自動マージは設定していません。設定は`.github/dependabot.yml`で管理します。

OCaml・Dune・OCamlFormatの依存定義・lockや、opam-repositoryのSHAはこの設定の対象外です。
これらは「開発環境と依存管理」の手順に従い、設定の整合を確認して手動で更新します。

### CI環境とキャッシュ

環境構築とコンパイラのキャッシュは
[ocaml/setup-ocaml v3.9.0](https://github.com/ocaml/setup-ocaml/releases/tag/v3.9.0)に任せます。
ActionはコミットSHAで固定し、OCaml 5.4.1とopam-repositoryのSHAをワークフローで固定します。
opamはActionの対応範囲内で利用可能な最新安定版を選び、バージョンをログへ記録します。
Actionの更新時に、その対応範囲も確認します。

キャッシュ対象はopam rootとコンパイラのローカルswitch（`_opam/`）です。
キーにはOS・アーキテクチャ・opam・コンパイラ・リポジトリURL・sandbox設定が反映されます。
Actionはコンパイラ環境の構築直後にキャッシュを保存します。
プロジェクトと開発ツールの依存は、その後に毎回`mail_weaver.opam.locked`から導入します。
共用スクリプトで元の依存定義・生成物・lockの整合性を確認し、`--with-test`は付けません。
Dune共有キャッシュとプロジェクトのビルド・テスト成果物のキャッシュは無効です。

mainへのpushと同一リポジトリのPRではキャッシュを使い、fork PRでは復元・保存とも無効にします。
権限を追加せず、checkoutの認証情報も保存しません。
キャッシュヒット時にも全4チェックと`dune runtest --force`を毎回実行します。

環境準備やチェックの失敗はCI失敗として扱い、専用の自動破棄・再構築処理は持ちません。
復旧にはActions画面で該当キャッシュを削除するか、ワークフローの`cache-prefix`を更新します。
キャッシュを無効にして実行する場合は`cache: false`を指定します。
時間比較には環境準備ステップと依存導入ステップの所要時間の合計を使います。

ローカルでは開発環境の手順で同じOCaml・Dune・OCamlFormatを用意し、前述の全4コマンドを実行します。
Actionとランナーを含む環境全体の再現性を保証するものではありません。

Issue #16の検証では、実CIのミス→ヒット、準備時間の比較、ヒット時のチェック実行を確認します。
独立したキャッシュ無効実行とマージ後mainの実測は今回の完了条件に含めません。

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

## 開発環境と依存管理

依存定義の編集元は`dune-project`です。Duneが生成する`mail_weaver.opam`と、
`opam lock`で生成する`mail_weaver.opam.locked`をGit管理します。
`.opam`とlockは手編集しません。実装・ユニットテストはOCaml標準ライブラリを使います。

| ツール | バージョン |
| --- | --- |
| OCaml | 5.4.1 |
| Dune | 3.24.2 |
| OCamlFormat | 0.29.0 |

DuneとOCamlFormatも通常の依存に含め、lockで間接依存まで固定します。
opam本体は利用可能な安定版を使い、共用スクリプトのCLI互換性は`--cli=2.2`で指定します。
OSのパッケージや環境全体を固定するものではありません。

### 新しい専用環境の構築

opam 2.2以上、Cコンパイラ、make、Gitなどをあらかじめ用意してください。
プロジェクトルートで、既存の`default` switchや個人設定に触れずに構築します。
以下は一時rootを使います。rootの保存先を変更する場合も専用の絶対パスを指定してください。

```sh
mail_weaver_repository='git+https://github.com/ocaml/opam-repository.git#eba24de6376079a3f9dfa4a9c9ca842475cd1bbc'
mail_weaver_root=$(mktemp -d "${TMPDIR:-/tmp}/mail-weaver-opam.XXXXXX")
export OPAMROOT="$mail_weaver_root" OPAMSWITCH=mail-weaver
unset OPAMLOCKED OPAMWITHTEST OPAMWITHDOC OPAMWITHDEVSETUP \
  OPAMBUILDTEST OPAMBUILDDOC OPAMBESTEFFORT OPAMIGNORECONSTRAINTS \
  OPAMIGNOREAVAILABLE OPAMSKIPVERSIONCHECKS
opam init --cli=2.2 --root="$OPAMROOT" --bare --no-setup --no-opamrc \
  --yes default "$mail_weaver_repository"
opam switch create --cli=2.2 --root="$OPAMROOT" \
  "$OPAMSWITCH" ocaml-base-compiler.5.4.1 --yes
./scripts/install-deps.sh "$OPAMROOT" "$OPAMSWITCH"
```

共用スクリプトは初期化済みrootとswitchを必須引数で受け取り、`default`とpinを拒否します。
lockがなければ停止し、`opam install . --deps-only --locked`に相当する導入を実行します。
さらに元の依存制約、`.opam`の生成同期、導入済み依存から再生成したlockとの一致を確認します。
不整合時に未固定の導入へ切り替えたり、追跡済みlockを自動更新したりしません。

Duneが生成する`odoc {with-doc}`は、今回は有効にしません。
`opam lock`が未導入の`odoc`を表示することがありますが、文書生成条件を無効にした環境では想定どおりです。
OCamlFormatを含む依存パッケージ自身のテスト・文書・開発用依存も有効にしません。
プロジェクトのテストは、依存導入後に別途実行します。

同じシェルで、全4チェックを実行します。

```sh
opam exec -- ./scripts/check-static.sh
opam exec -- dune build @fmt
opam exec -- dune build
opam exec -- dune runtest --force
```

`opam exec`は上でexportした専用root／switchを使います。
別のシェルから再利用する場合は、保存したrootの絶対パスとswitchを再指定してください。
直接`dune`などを実行する場合は、この専用環境を現在のシェルに反映します。
個人のシェル設定ファイルは変更しません。

```sh
eval "$(opam env --cli=2.2 --root="$OPAMROOT" --switch="$OPAMSWITCH")"
```

### 依存定義とlockの更新

1. `dune-project`の依存・制約を変更します。ツールを更新する場合は、
   `.ocamlformat`と静的チェックスクリプトの固定値も同時に更新します。
2. 既存の専用環境で、次を実行して`.opam`を再生成します。
   `@opam`が差分を報告したら内容を確認して`dune promote`で反映し、チェックを再実行します。

```sh
opam exec -- dune build @opam
opam exec -- dune promote
opam exec -- dune build @opam
```

3. 「新しい専用環境の構築」の`opam switch create`までを、新しいrootで実行します。
   古いlockとの不整合があるため、共用スクリプトはまだ実行しません。
   個人のswitchや、依存が導入済みのswitchからlockを生成しないでください。
4. プロジェクトルートで、更新時に限り`--locked`を付けずに依存を解決し、lockを生成します。
   `opam lock`の出力先はカレントディレクトリです。

```sh
opam install --cli=2.2 --root="$OPAMROOT" --switch="$OPAMSWITCH" \
  --yes --deps-only ./mail_weaver.opam
opam lock --cli=2.2 --root="$OPAMROOT" --switch="$OPAMSWITCH" ./mail_weaver.opam
./scripts/install-deps.sh "$OPAMROOT" "$OPAMSWITCH"
git diff -- dune-project mail_weaver.opam mail_weaver.opam.locked
```

5. 直接・間接依存の採用バージョン、意図しない依存・pin・ローカルパスがないことを確認します。
   再度新しい専用root／switchを作り、今度は共用スクリプトでlockから導入し、全4チェックを実行します。
   macOSとUbuntuの両方で確認し、OS差があればlockを無視して回避せずに原因を調べます。

### 固定リポジトリの更新とCI検証

リポジトリSHAを更新する場合は、CIの`opam-repositories`と上記手順のURLを同じSHAへ変更します。
そのSHAの新規環境で依存・lockの更新、差分確認、新規環境への再導入、全4チェックを行います。
コンパイラ・主要ツールの更新は、リポジトリSHAの更新とは別に判断してください。

CIではキャッシュの有無にかかわらず共用スクリプトと全4チェックを実行します。
キャッシュを無効にする検証は、一時的に`cache: false`を指定します。
キャッシュ利用時のlock反映は、固定リポジトリ内の互換性がある間接依存を別バージョンでlockし、
導入後の`opam list --installed --columns=name,version`で確認します。
検証用のlock変更は最終成果物から除き、元のlockで全チェックを再実行します。
実CIの実行URL・checkout SHA・キャッシュ利用・各チェックの結果はPRなどに記録し、
ローカル検証と実CIの確認を区別してください。

## 整形

OCamlFormat 0.29.0と`profile=default`をルートの`.ocamlformat`で固定しています。
異なるバージョンのOCamlFormatではバージョンチェックが失敗します。
開発環境の手順で、lockから固定バージョンのツールを導入してください。
OCamlFormat自身のテスト用依存には`dune < 3.22`の制約があるため、
依存パッケージ自身のテストは有効にしません。プロジェクトのテストは別途実行します。
以下の直接実行は、専用環境を`opam env`でシェルに反映した状態を前提とします。

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

ローカルとCIでは、同じ固定バージョンのツールで次を実行します。
整形チェックと静的チェックは独立した入口とし、CIでも同じ入口を使用します。

```sh
dune build @fmt
./scripts/check-static.sh
dune runtest
```

## 静的チェック

開発環境の手順でOCaml 5.4.1 / Dune 3.24.2を用意した後、次を実行します。
追加パッケージは不要です。ローカルとCIで共用する入口はこのスクリプトです。
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
