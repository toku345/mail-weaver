(** 構造化済みFromと許可リストから配送先候補を決める純粋な判定。
    アドレスは有効なASCIIのlocal-part@domain形式を前提とする。
    quoted local-part、国際化アドレス、表示名、生ヘッダー、構文検証は対象外。
    この判定は送信者認証ではなく、SPF/DKIM/DMARCを検証しない。 *)

module Address_set : Set.S with type elt = string
(** アドレス文字列の不変集合。ドメインの大小文字を含め、入力をそのまま保持する。 *)

type pending_reason =
  | Missing_from
  | Multiple_from
  | Unapproved_sender

type decision = Inbox | Pending of pending_reason

val decide : from:string list -> allowlist:Address_set.t -> decision
(** Fromが0件なら[Pending Missing_from]、2件以上なら[Pending Multiple_from]。
    1件なら双方のドメインだけASCII小文字化して完全一致を比較し、
    一致すれば[Inbox]、それ以外は[Pending Unapproved_sender]を返す。
    ローカル部の大小文字、+タグ、ドットは保持する。許可リストは変更しない。 *)
