(** 読み取り専用の JMAP リクエストを組み立てる（RFC 8620 / RFC 8621）。

    メールを変更するメソッド（[Email/set] など）は組み立てない。 [Email/get] は [id] と
    [header:From:asAddresses:all] だけを要求し、本文・添付は取得しない。 送信と応答の解釈は呼び出し側と
    [Jmap_response] が担う。 *)

val mailbox_get : account_id:string -> Yojson.Safe.t
(** 全メールボックスの [id]・[name]・[role] を取得する。呼び出し ID は ["m"]。 *)

val email_page :
  account_id:string ->
  mailbox_id:string ->
  position:int ->
  limit:int ->
  Yojson.Safe.t
(** 1 ページ分の [Email/query]（呼び出し ID ["q"]）と [Email/get]（["g"]）。

    [Email/query] は受信日時の昇順で、[calculateTotal] を有効にする。 [Email/get] は [#ids]
    で同じリクエスト内の [Email/query] の結果を参照する。 *)
