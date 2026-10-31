open Mail_weaver.Jmap_response
module Input = Mail_weaver.Sender_input
module E = Mail_weaver.System_error

let failures = ref 0
let checks = ref 0

let check name actual expected =
  incr checks;
  if actual <> expected then begin
    incr failures;
    Printf.eprintf "FAIL - %s\n" name
  end

let protocol problem = Error (E.Protocol problem)

(* Session *)

let session_json ?(mail = true)
    ?(api_url = {|"https://api.example.com/jmap/api/"|}) ?(max_objects = "500")
    ?(account = {|"A1"|}) () =
  Printf.sprintf
    {|{
  "capabilities": {
    "urn:ietf:params:jmap:core": {"maxObjectsInGet": %s, "maxSizeRequest": 10000000}%s
  },
  "primaryAccounts": {%s},
  "apiUrl": %s,
  "username": "user@example.com",
  "state": "s1"
}|}
    max_objects
    (if mail then {|, "urn:ietf:params:jmap:mail": {}|} else "")
    (if mail then {|"urn:ietf:params:jmap:mail": |} ^ account else "")
    api_url

let session_cases =
  [
    ( "有効なSession",
      session_json (),
      Ok
        {
          api_url = "https://api.example.com/jmap/api/";
          account_id = "A1";
          max_objects_in_get = 500;
        } );
    ("JSON破損", "{", Error E.Invalid_json);
    ("mail能力なし", session_json ~mail:false (), protocol E.Mail_capability_missing);
    ( "httpsでないapiUrl",
      session_json ~api_url:{|"http://api.example.com/"|} (),
      protocol E.Api_url_not_https );
    ( "maxObjectsInGetが0",
      session_json ~max_objects:"0" (),
      protocol E.Session_malformed );
    ( "maxObjectsInGetが文字列",
      session_json ~max_objects:{|"5"|} (),
      protocol E.Session_malformed );
    ("apiUrl欠落", session_json ~api_url:"null" (), protocol E.Session_malformed);
    ("不正なアカウントID", session_json ~account:{|"A 1"|} (), protocol E.Invalid_id);
    ("ルートが配列", "[]", protocol E.Session_malformed);
  ]

(* Mailbox/get *)

let mailbox_response list =
  Printf.sprintf
    {|{"methodResponses": [["Mailbox/get", {"accountId": "A1", "state": "1", "list": %s, "notFound": []}, "m"]], "sessionState": "s1"}|}
    list

let mailbox_cases =
  [
    ( "メールボックス一覧",
      mailbox_response
        {|[{"id": "I", "name": "Inbox", "role": "inbox"}, {"id": "U", "name": "未処理", "role": null}]|},
      Ok
        [
          { id = "I"; name = "Inbox"; role = Some "inbox" };
          { id = "U"; name = "未処理"; role = None };
        ] );
    ( "role欠落",
      mailbox_response {|[{"id": "I", "name": "Inbox"}]|},
      protocol E.Response_malformed );
    ( "メソッドエラー",
      {|{"methodResponses": [["error", {"type": "accountNotFound", "description": "user@example.com"}, "m"]]}|},
      Error (E.Method_error E.Account_not_found) );
    ( "未知のメソッドエラー",
      {|{"methodResponses": [["error", {"type": "somethingNew"}, "m"]]}|},
      Error (E.Method_error E.Other_method_error) );
    ( "呼び出しIDの不一致",
      {|{"methodResponses": [["Mailbox/get", {"list": []}, "x"]]}|},
      protocol E.Missing_method_response );
    ( "メソッド名の不一致",
      {|{"methodResponses": [["Email/get", {"list": []}, "m"]]}|},
      protocol E.Unexpected_method_response );
    ( "応答が重複",
      {|{"methodResponses": [["Mailbox/get", {"list": []}, "m"], ["Mailbox/get", {"list": []}, "m"]]}|},
      protocol E.Unexpected_method_response );
    ("methodResponses欠落", {|{}|}, protocol E.Response_malformed);
    ( "重複キー",
      {|{"methodResponses": [], "methodResponses": []}|},
      protocol E.Response_malformed );
  ]

(* Email/query + Email/get *)

let page_response ?(query_state = "qs1") ?(position = "0") ?(total = "2")
    ?(ids = {|["M1", "M2"]|}) ?(not_found = "[]") list =
  Printf.sprintf
    {|{"methodResponses": [
  ["Email/query", {"accountId": "A1", "queryState": "%s", "canCalculateChanges": false, "position": %s, "total": %s, "ids": %s}, "q"],
  ["Email/get", {"accountId": "A1", "state": "s", "list": %s, "notFound": %s}, "g"]
]}|}
    query_state position total ids list not_found

let email id from =
  Printf.sprintf {|{"id": "%s", "header:From:asAddresses:all": %s}|} id from

let alice = {|{"name": "Alice", "email": "alice@example.com"}|}
let bob = {|{"name": null, "email": "bob@example.com"}|}

(* README の抽出契約と 1 対 1 で対応させる。 *)
let from_cases =
  [
    ("From欄なしは欠落", "[]", Input.Parsed []);
    ("1欄1件", "[[" ^ alice ^ "]]", Input.Parsed [ "alice@example.com" ]);
    ( "1欄に複数件は順序を保つ",
      "[[" ^ alice ^ "," ^ bob ^ "]]",
      Input.Parsed [ "alice@example.com"; "bob@example.com" ] );
    ( "複数欄は順に連結",
      "[[" ^ bob ^ "],[" ^ alice ^ "]]",
      Input.Parsed [ "bob@example.com"; "alice@example.com" ] );
    ( "nameは比較に使わない",
      {|[[{"name": "Bob <bob@example.com>", "email": "alice@example.com"}]]|},
      Input.Parsed [ "alice@example.com" ] );
    ( "emailの表示名形式はそのまま渡す",
      {|[[{"name": null, "email": "Alice <alice@example.com>"}]]|},
      Input.Parsed [ "Alice <alice@example.com>" ] );
    ("空のemailは要素として残す", {|[[{"name": null, "email": ""}]]|}, Input.Parsed [ "" ]);
    ("空の欄", "[[]]", Input.Parse_failed);
    ("空の欄を除外しない", "[[" ^ alice ^ "],[]]", Input.Parse_failed);
    ("email欠落", {|[[{"name": "Alice"}]]|}, Input.Parse_failed);
    ("emailがnull", {|[[{"name": "Alice", "email": null}]]|}, Input.Parse_failed);
    ("要素が文字列", {|[["alice@example.com"]]|}, Input.Parse_failed);
    ("欄が配列でない", "[" ^ alice ^ "]", Input.Parse_failed);
    ("外側がnull", "null", Input.Parse_failed);
  ]

let page_cases =
  [
    ( "クエリ順に並べる",
      page_response
        ("[" ^ email "M2" "[]" ^ "," ^ email "M1" ("[[" ^ alice ^ "]]") ^ "]"),
      Ok
        {
          query_state = "qs1";
          position = 0;
          total = 2;
          emails =
            [
              { id = "M1"; from = Input.Parsed [ "alice@example.com" ] };
              { id = "M2"; from = Input.Parsed [] };
            ];
        } );
    ( "空のページ",
      page_response ~ids:"[]" ~total:"0" "[]",
      Ok { query_state = "qs1"; position = 0; total = 0; emails = [] } );
    ( "Fromのキー自体が無い",
      page_response ~ids:{|["M1"]|} {|[{"id": "M1"}]|},
      protocol E.Email_property_missing );
    ( "notFoundが空でない",
      page_response ~ids:{|["M1", "M2"]|} ~not_found:{|["M2"]|}
        ("[" ^ email "M1" "[]" ^ "]"),
      Error E.Email_not_found );
    ( "notFoundがnull",
      page_response ~ids:{|["M1"]|} ~not_found:"null"
        ("[" ^ email "M1" "[]" ^ "]"),
      protocol E.Response_malformed );
    ( "getの件数不足",
      page_response ("[" ^ email "M1" "[]" ^ "]"),
      protocol E.Email_ids_mismatch );
    ( "想定外のID",
      page_response ("[" ^ email "M1" "[]" ^ "," ^ email "M3" "[]" ^ "]"),
      protocol E.Email_ids_mismatch );
    ( "不正なメールID",
      page_response ~ids:{|["M\t1"]|} ("[" ^ email "M1" "[]" ^ "]"),
      protocol E.Invalid_id );
    ( "total欠落",
      {|{"methodResponses": [["Email/query", {"queryState": "qs1", "position": 0, "ids": []}, "q"], ["Email/get", {"list": [], "notFound": []}, "g"]]}|},
      protocol E.Response_malformed );
    ( "queryがメソッドエラー",
      {|{"methodResponses": [["error", {"type": "unsupportedSort"}, "q"], ["error", {"type": "invalidResultReference"}, "g"]]}|},
      Error (E.Method_error E.Unsupported_sort) );
    ( "getだけメソッドエラー",
      {|{"methodResponses": [["Email/query", {"queryState": "qs1", "position": 0, "total": 0, "ids": []}, "q"], ["error", {"type": "requestTooLarge"}, "g"]]}|},
      Error (E.Method_error E.Request_too_large) );
    ("JSON破損", "{\"methodResponses\": [", Error E.Invalid_json);
  ]

let () =
  List.iter
    (fun (name, text, expected) ->
      check ("session " ^ name) (session text) expected)
    session_cases;
  List.iter
    (fun (name, text, expected) ->
      check ("mailboxes " ^ name) (mailboxes text) expected)
    mailbox_cases;
  List.iter
    (fun (name, from, expected) ->
      check ("From " ^ name)
        (page
           (page_response ~ids:{|["M1"]|} ~total:"1"
              ("[" ^ email "M1" from ^ "]")))
        (Ok
           {
             query_state = "qs1";
             position = 0;
             total = 1;
             emails = [ { id = "M1"; from = expected } ];
           }))
    from_cases;
  List.iter
    (fun (name, text, expected) -> check ("page " ^ name) (page text) expected)
    page_cases;
  if !failures > 0 then exit 1;
  Printf.printf "jmap_response tests passed: %d checks\n" !checks
