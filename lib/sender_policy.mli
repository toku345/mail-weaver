(** 送信者の許可判定。

    From アドレス一覧と許可済みアドレス集合から、配送先候補を決める純粋関数。
    送信者認証（SPF/DKIM/DMARC）ではなく、生のメールヘッダーや表示名の解析もしない。

    生入力を使う連携の入口には [Sender_input.decide] を使用すること。

    {2 入力の前提}

    - [from] は構造化済みの From アドレス一覧。0 件は From 欠落として扱う。
    - [allowed] は許可済みアドレス一覧を集合として扱う。
    - 各アドレスは ASCII の local-part@domain 形式で、'@' を 1 つだけ含む。 quoted
      local-part、国際化アドレス、表示名は入力に含まれない。 構文検証は行わない（前提に反する入力の挙動は未定義）。
    - 同じ入力は常に同じ結果を返し、ネットワーク・ファイル・DB・時刻に依存しない。
    - [from] と [allowed] を含む入力は書き換えない。 *)

type pending_reason =
  | Missing_from  (** From が欠落、または 0 件。 *)
  | Multiple_from  (** From が 2 件以上。一部または全部が許可済みでも承認待ちにする。 *)
  | Sender_not_allowed  (** From は 1 件だが、許可リストに一致するアドレスがない。 *)

type decision =
  | Inbox  (** 受信箱へ振り分ける。 *)
  | Pending of pending_reason  (** 承認待ち。理由は [pending_reason] で区別できる。 *)

val decide : from:string list -> allowed:string list -> decision
(** [decide ~from ~allowed] は配送先候補を返す。

    - [from] が 1 件で、許可リストに一致するアドレスがあれば [Inbox]。
    - [from] が 1 件で一致しなければ [Pending Sender_not_allowed]。
    - [from] が 0 件なら [Pending Missing_from]。
    - [from] が 2 件以上なら [Pending Multiple_from] （一部または全部が許可済みでも承認待ちにする）。

    一致判定はアドレス全体の完全一致で行う。比較時は From・許可リスト双方の ドメイン部分だけ ASCII 小文字化し、ローカル部の大小文字は区別する。
    表示名、ドメインのみの一致、部分一致、+tag の除去や Gmail のドット除去などの サービス固有の同一視では許可しない。 *)
