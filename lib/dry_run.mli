(** dry-run の出力を組み立てる。

    メール ID・予定移動先・保留理由・件数だけを出し、From アドレスは出力しない。 メール ID は [Jmap_response] で JMAP の
    Id 形式（英数字・ハイフン・下線）に検証済みとする。

    {[
      M1	inbox
      M2	pending	Sender_not_allowed
      M3	pending	Invalid_from_address	index=0	Unsupported.Display_name_form
      summary	processed=3	inbox=1	pending=2	limit_reached=false
      pending_reason	Sender_not_allowed	1
      pending_reason	Invalid_from_address	1
    ]} *)

type entry = { id : string; outcome : Sender_input.outcome }

val render : limit_reached:bool -> entry list -> string
