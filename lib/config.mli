(** 設定ファイル（JSON）の解析と検証。

    {[
      {
        "mailboxes": { "unprocessed": "未処理", "pending": "承認待ち" },
        "limit": 100,
        "allowed": ["alice@example.com"]
      }
    ]}

    全キーが必須。未知のキー・重複キー・型違い・範囲外はエラーにし、黙って補正しない。 [allowed] は通信の前に
    [Sender_input.validate_allowed] で検証する。 エラーはキーのパスと位置だけを持ち、設定値を含めない。
    ただし未知キー・重複キーのパスには設定ファイルに書かれたキー名がそのまま入るため、 表示する側で扱いを決める。 ファイルの読み込みと API
    トークン（環境変数）の扱いは呼び出し側が担う。 *)

type t = {
  unprocessed_mailbox : string;
  pending_mailbox : string;
  limit : int;  (** 1 回の実行で扱うメールの上限。 *)
  allowed : string list;
}

type error =
  | Invalid_json
  | Duplicate_key of string
  | Unknown_key of string
  | Missing_key of string
  | Type_mismatch of string
  | Out_of_range of string
  | Empty_value of string
  | Same_mailbox_name  (** 未処理と承認待ちに同じ名前を指定した。 *)
  | Invalid_allowed of Sender_input.address_problem

val max_limit : int
(** [limit] の上限。下限は 1。 *)

val parse : string -> (t, error) result
