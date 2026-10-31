type session = {
  api_url : string;
  account_id : string;
  max_objects_in_get : int;
}

type mailbox = { id : string; name : string; role : string option }
type email = { id : string; from : Sender_input.from_input }

type page = {
  query_state : string;
  position : int;
  total : int;
  emails : email list;
}

let ( let* ) = Result.bind
let mail_capability = "urn:ietf:params:jmap:mail"
let malformed = Error (System_error.Protocol System_error.Response_malformed)

let parse text =
  match Json_input.parse text with
  | Ok json -> Ok json
  | Error Json_input.Invalid_json -> Error System_error.Invalid_json
  | Error (Json_input.Duplicate_key _) -> malformed

(* RFC 8620 §1.2: Id は 1〜255 文字の英数字・ハイフン・下線。出力の区切りも壊さない。 *)
let valid_id id =
  let length = String.length id in
  1 <= length && length <= 255
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' -> true | _ -> false)
       id

let id (json : Yojson.Safe.t) =
  match json with
  | `String id when valid_id id -> Ok id
  | `String _ -> Error (System_error.Protocol System_error.Invalid_id)
  | _ -> malformed

let assoc (json : Yojson.Safe.t) =
  match json with `Assoc fields -> Ok fields | _ -> malformed

let member key fields =
  match List.assoc_opt key fields with
  | Some value -> Ok value
  | None -> malformed

let string (json : Yojson.Safe.t) =
  match json with `String value -> Ok value | _ -> malformed

let non_negative (json : Yojson.Safe.t) =
  match json with `Int value when value >= 0 -> Ok value | _ -> malformed

let list (json : Yojson.Safe.t) =
  match json with `List items -> Ok items | _ -> malformed

let rec map_result f = function
  | [] -> Ok []
  | item :: rest ->
      let* value = f item in
      let* values = map_result f rest in
      Ok (value :: values)

let session text =
  let session_error problem = Error (System_error.Protocol problem) in
  let required = function
    | Ok value -> Ok value
    | Error _ -> session_error System_error.Session_malformed
  in
  let* json = parse text in
  let* fields = required (assoc json) in
  let* capabilities =
    required (Result.bind (member "capabilities" fields) assoc)
  in
  let* primary_accounts =
    required (Result.bind (member "primaryAccounts" fields) assoc)
  in
  if
    not
      (List.mem_assoc mail_capability capabilities
      && List.mem_assoc mail_capability primary_accounts)
  then session_error System_error.Mail_capability_missing
  else
    let* core =
      required
        (Result.bind (member "urn:ietf:params:jmap:core" capabilities) assoc)
    in
    let* max_objects_in_get =
      required (Result.bind (member "maxObjectsInGet" core) non_negative)
    in
    let* account_id =
      Result.bind (member mail_capability primary_accounts) id
    in
    let* api_url = required (Result.bind (member "apiUrl" fields) string) in
    if max_objects_in_get < 1 then session_error System_error.Session_malformed
    else if not (String.starts_with ~prefix:"https://" api_url) then
      session_error System_error.Api_url_not_https
    else Ok { api_url; account_id; max_objects_in_get }

let method_error = function
  | "serverUnavailable" -> System_error.Server_unavailable
  | "serverFail" -> System_error.Server_fail
  | "serverPartialFail" -> System_error.Server_partial_fail
  | "unknownMethod" -> System_error.Unknown_method
  | "invalidArguments" -> System_error.Invalid_arguments
  | "invalidResultReference" -> System_error.Invalid_result_reference
  | "forbidden" -> System_error.Forbidden
  | "accountNotFound" -> System_error.Account_not_found
  | "accountNotSupportedByMethod" ->
      System_error.Account_not_supported_by_method
  | "accountReadOnly" -> System_error.Account_read_only
  | "requestTooLarge" -> System_error.Request_too_large
  | "anchorNotFound" -> System_error.Anchor_not_found
  | "unsupportedSort" -> System_error.Unsupported_sort
  | "unsupportedFilter" -> System_error.Unsupported_filter
  | _ -> System_error.Other_method_error

(* 呼び出し ID ごとの応答を 1 件だけ取り出す。["error"] ならメソッドエラーにする。 *)
let method_response ~name ~call_id responses =
  let matching =
    List.filter
      (function `List [ _; _; `String id ] -> id = call_id | _ -> false)
      responses
  in
  match matching with
  | [] -> Error (System_error.Protocol System_error.Missing_method_response)
  | [ `List [ `String "error"; arguments; _ ] ] ->
      let* fields = assoc arguments in
      let* error_type = Result.bind (member "type" fields) string in
      Error (System_error.Method_error (method_error error_type))
  | [ `List [ `String response_name; arguments; _ ] ] when response_name = name
    ->
      assoc arguments
  | _ -> Error (System_error.Protocol System_error.Unexpected_method_response)

let method_responses text =
  let* json = parse text in
  let* fields = assoc json in
  let* responses = Result.bind (member "methodResponses" fields) list in
  if
    List.for_all
      (function `List [ `String _; `Assoc _; `String _ ] -> true | _ -> false)
      responses
  then Ok responses
  else malformed

let mailbox json =
  let* fields = assoc json in
  let* id = Result.bind (member "id" fields) id in
  let* name = Result.bind (member "name" fields) string in
  let* role =
    match List.assoc_opt "role" fields with
    | Some (`String role) -> Ok (Some role)
    | Some `Null -> Ok None
    | Some _ | None -> malformed
  in
  Ok { id; name; role }

let mailboxes text =
  let* responses = method_responses text in
  let* arguments = method_response ~name:"Mailbox/get" ~call_id:"m" responses in
  let* items = Result.bind (member "list" arguments) list in
  map_result mailbox items

let from_property = "header:From:asAddresses:all"

(* README の抽出契約: 外側の空配列は From 欠落、欄は順に連結し、
   空の欄・解釈できない要素は除外せず Parse_failed にする。name は使わない。 *)
let from_input (json : Yojson.Safe.t) =
  let address : Yojson.Safe.t -> string option = function
    | `Assoc fields -> (
        match List.assoc_opt "email" fields with
        | Some (`String email) -> Some email
        | _ -> None)
    | _ -> None
  in
  let field : Yojson.Safe.t -> string list option = function
    | `List (_ :: _ as addresses) ->
        let emails = List.filter_map address addresses in
        if List.length emails = List.length addresses then Some emails else None
    | _ -> None
  in
  match json with
  | `List fields ->
      let parsed = List.filter_map field fields in
      if List.length parsed = List.length fields then
        Sender_input.Parsed (List.concat parsed)
      else Sender_input.Parse_failed
  | _ -> Sender_input.Parse_failed

let email json =
  let* fields = assoc json in
  let* id = Result.bind (member "id" fields) id in
  match List.assoc_opt from_property fields with
  | Some value -> Ok { id; from = from_input value }
  | None -> Error (System_error.Protocol System_error.Email_property_missing)

let page text =
  let* responses = method_responses text in
  let* query = method_response ~name:"Email/query" ~call_id:"q" responses in
  let* query_state = Result.bind (member "queryState" query) string in
  let* position = Result.bind (member "position" query) non_negative in
  let* total = Result.bind (member "total" query) non_negative in
  let* ids =
    Result.bind (Result.bind (member "ids" query) list) (map_result id)
  in
  let* get = method_response ~name:"Email/get" ~call_id:"g" responses in
  let* not_found =
    match List.assoc_opt "notFound" get with
    | Some (`List items) -> Ok items
    | Some _ | None -> malformed
  in
  if not_found <> [] then Error System_error.Email_not_found
  else
    let* emails =
      Result.bind (Result.bind (member "list" get) list) (map_result email)
    in
    let find id = List.find_all (fun (email : email) -> email.id = id) emails in
    let ordered = List.map find ids in
    if
      List.length emails = List.length ids
      && List.for_all (fun found -> List.length found = 1) ordered
    then Ok { query_state; position; total; emails = List.concat ordered }
    else Error (System_error.Protocol System_error.Email_ids_mismatch)
