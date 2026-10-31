(** 設定したメールボックス名を JMAP の ID へ解決する。

    未処理・承認待ちは名前の完全一致、受信箱は [role = "inbox"] で特定する。 該当なし・複数該当・3 つの ID
    の重複は、推測せずにエラーにする。 *)

type target = Unprocessed | Inbox | Pending
type ids = { unprocessed : string; inbox : string; pending : string }

type error =
  | Mailbox_not_found of target
  | Mailbox_ambiguous of target
  | Mailbox_conflict  (** 異なる用途に同じメールボックスが解決された。 *)

val resolve :
  unprocessed_name:string ->
  pending_name:string ->
  Jmap_response.mailbox list ->
  (ids, error) result
