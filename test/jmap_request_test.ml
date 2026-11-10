module Request = Mail_weaver.Jmap_request

let failures = ref 0
let checks = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf "FAIL - %s\n" name
  end

let member key (json : Yojson.Safe.t) =
  match json with `Assoc fields -> List.assoc_opt key fields | _ -> None

let calls json =
  match member "methodCalls" json with
  | Some (`List calls) ->
      List.filter_map
        (function
          | `List [ `String name; (`Assoc _ as arguments); `String call_id ] ->
              Some (name, arguments, call_id)
          | _ -> None)
        calls
  | _ -> []

let arguments name json =
  List.find_map
    (fun (call_name, arguments, _) ->
      if call_name = name then Some arguments else None)
    (calls json)

let using =
  Some
    (`List
       [
         `String "urn:ietf:params:jmap:core";
         `String "urn:ietf:params:jmap:mail";
       ])

let () =
  let mailbox = Request.mailbox_get ~account_id:"A1" in
  check "Mailbox/getのusing" (member "using" mailbox = using);
  check "Mailbox/getだけを呼ぶ"
    (List.map (fun (name, _, id) -> (name, id)) (calls mailbox)
    = [ ("Mailbox/get", "m") ]);
  check "Mailbox/getの取得項目"
    (Option.bind (arguments "Mailbox/get" mailbox) (member "properties")
    = Some (`List [ `String "id"; `String "name"; `String "role" ]));
  let page =
    Request.email_page ~account_id:"A1" ~mailbox_id:"MB1" ~position:50 ~limit:25
  in
  check "ページのusing" (member "using" page = using);
  check "読み取りメソッドだけを呼ぶ"
    (List.map (fun (name, _, id) -> (name, id)) (calls page)
    = [ ("Email/query", "q"); ("Email/get", "g") ]);
  check "methodCallsは2件だけ"
    (match member "methodCalls" page with
    | Some (`List calls) -> List.length calls = 2
    | _ -> false);
  let query = arguments "Email/query" page in
  let get = arguments "Email/get" page in
  check "accountId"
    (Option.bind query (member "accountId") = Some (`String "A1")
    && Option.bind get (member "accountId") = Some (`String "A1"));
  check "未処理フォルダで絞り込む"
    (Option.bind query (member "filter")
    = Some (`Assoc [ ("inMailbox", `String "MB1") ]));
  check "受信日時の昇順"
    (Option.bind query (member "sort")
    = Some
        (`List
           [
             `Assoc
               [
                 ("property", `String "receivedAt"); ("isAscending", `Bool true);
               ];
           ]));
  check "position" (Option.bind query (member "position") = Some (`Int 50));
  check "limit" (Option.bind query (member "limit") = Some (`Int 25));
  check "calculateTotal"
    (Option.bind query (member "calculateTotal") = Some (`Bool true));
  check "queryの結果を参照する"
    (Option.bind get (member "#ids")
    = Some
        (`Assoc
           [
             ("resultOf", `String "q");
             ("name", `String "Email/query");
             ("path", `String "/ids");
           ]));
  check "本文を要求せずFromだけを取得する"
    (Option.bind get (member "properties")
    = Some (`List [ `String "id"; `String "header:From:asAddresses:all" ]));
  check "本文取得の指定がない"
    (Option.bind get (member "fetchTextBodyValues") = None
    && Option.bind get (member "fetchAllBodyValues") = None
    && Option.bind get (member "bodyProperties") = None);
  let text = Yojson.Safe.to_string page ^ Yojson.Safe.to_string mailbox in
  let contains fragment =
    let n = String.length fragment in
    let rec loop i =
      i + n <= String.length text
      && (String.sub text i n = fragment || loop (i + 1))
    in
    loop 0
  in
  check "変更系メソッドを含まない"
    (not (List.exists contains [ "/set"; "/import"; "/copy"; "/changes" ]));
  if !failures > 0 then exit 1;
  Printf.printf "jmap_request tests passed: %d checks\n" !checks
