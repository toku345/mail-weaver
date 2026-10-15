# mail-weaver

メールを整理し、必要な情報を必要なタイミングで届けるメールアシスタント。
将来はローカルモデルによる内容別の振り分け、メルマガのアーカイブと日次サマリーを目指します。

## 現在の実装

OCaml / Duneの共通開発基盤と、送信者の許可判定を行う純粋関数を含みます。
CLI、JMAP接続、SQLiteへの永続化はまだ実装していません。

### 送信者の許可判定

`Mail_weaver.Sender_policy.decide ~from ~allowlist`に、構造化済みFromの
文字列リストと、`Address_set.of_list`で作った許可済みアドレスの不変集合を渡します。
アドレスは有効なASCIIの`local-part@domain`形式が前提です。
表示名・生ヘッダーの解析、quoted local-part、国際化アドレス、構文検証は扱いません。

| From | 結果 |
| --- | --- |
| 0件（欠落） | `Pending Missing_from` |
| 2件以上（同じアドレスの重複も含む） | `Pending Multiple_from` |
| 1件で許可リストと一致 | `Inbox` |
| 1件で一致しない | `Pending Unapproved_sender` |

双方のドメインだけASCII小文字化して完全一致を比較します。
ローカル部の大小文字、+タグ、ドットは区別し、ドメイン一致や部分一致では許可しません。
たとえば`alice@EXAMPLE.TEST`は`alice@example.test`と一致しますが、
`Alice@example.test`や`alice+news@example.test`とは一致しません。
許可リストを変更せず、ネットワーク・ファイル・DB・時刻に依存しません。
これは配送先候補の判定であり、送信者認証（SPF/DKIM/DMARC検証）ではありません。

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

新しいチェックアウトで、既存のswitchを現在のシェルに反映して確認します。
switchの再作成やグローバル設定の変更は不要です。

```sh
eval "$(opam env --switch=default)"
ocaml -version
dune --version
```

現時点ではOCaml標準ライブラリとDune以外の依存はありません。
上記バージョンが導入済みなら、依存導入操作は不要です。
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
`test/sender_policy_test.ml`は許可判定・大小文字・誤一致防止と入力の不変性を検証します。
再実行して出力を確認する場合は`dune runtest --force`を使います。

## ローカルデータ

ビルド成果物、ローカルswitch、環境変数ファイル、認証情報、ローカルDB、メールデータはGit管理から除外します。
実メールや認証情報をコミットしないでください。設定例を追加する場合はダミー値だけを使用してください。

## 比較の開始点

Issue #1のPRをマージした後、そのmainのコミットSHAを記録し、同じSHAからGPT用・Fugu用の独立したworktreeを作ります。
送信者判定の実装はIssue #2で扱います。
