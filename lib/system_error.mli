(** 実行全体を止める通信・プロトコル上の障害。

    メールごとの保留（[Sender_input.Pending_input] など）とは区別し、 [Parse_failed] や
    [Sender_not_allowed] へ変換しない。 サーバーの応答本文・エラー文言・アドレスは保持せず、定数だけを持つ。 *)

type method_error =
  | Server_unavailable
  | Server_fail
  | Server_partial_fail
  | Unknown_method
  | Invalid_arguments
  | Invalid_result_reference
  | Forbidden
  | Account_not_found
  | Account_not_supported_by_method
  | Account_read_only
  | Request_too_large
  | Anchor_not_found
  | Unsupported_sort
  | Unsupported_filter
  | Other_method_error  (** 上記以外の [type]。サーバーの文字列は保持しない。 *)

type protocol_problem =
  | Session_malformed
  | Mail_capability_missing
  | Api_url_not_https
  | Response_malformed
  | Missing_method_response
  | Unexpected_method_response
  | Invalid_id
  | Email_property_missing
      (** 要求した [header:From:asAddresses:all] のキー自体が無い。From 欠落とは区別する。 *)
  | Email_ids_mismatch
  | Unexpected_position
  | Unexpected_empty_page

type t =
  | Invalid_json
  | Protocol of protocol_problem
  | Method_error of method_error
  | Email_not_found  (** [Email/get] の [notFound] が空でない。件数を黙って減らさない。 *)
  | Query_state_changed  (** ページの途中で一覧が変わった。取得漏れ・重複があり得るため正常完了にしない。 *)
