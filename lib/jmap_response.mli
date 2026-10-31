(** JMAP 応答の解釈（RFC 8620 / RFC 8621）。

    From の抽出は README の「JMAP・設定・保存層との責務分担」の契約に従う。 メッセージ固有の構造の問題は
    [Sender_input.Parse_failed]、 キーの欠落・応答全体の破損・メソッドエラーは [System_error.t]
    として区別する。 エラーにはサーバーの文字列やアドレスを含めない。 *)

type session = {
  api_url : string;  (** [https://] で始まる。 *)
  account_id : string;  (** メール用の主アカウント。 *)
  max_objects_in_get : int;  (** 1 以上。 *)
}

val session : string -> (session, System_error.t) result

type mailbox = { id : string; name : string; role : string option }

val mailboxes : string -> (mailbox list, System_error.t) result
(** [Jmap_request.mailbox_get] の応答を解釈する。 *)

type email = { id : string; from : Sender_input.from_input }

type page = {
  query_state : string;
  position : int;
  total : int;
  emails : email list;  (** [Email/query] の [ids] の順。 *)
}

val page : string -> (page, System_error.t) result
(** [Jmap_request.email_page] の応答を解釈する。

    [Email/get] の結果は [Email/query] の [ids] と過不足なく一致しなければならない。 [notFound] が空でなければ
    [Email_not_found] とする。 *)
