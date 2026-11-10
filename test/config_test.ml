open Mail_weaver.Config
module Input = Mail_weaver.Sender_input

let failures = ref 0
let checks = ref 0

let check name actual expected =
  incr checks;
  if actual <> expected then begin
    incr failures;
    Printf.eprintf "FAIL - %s\n" name
  end

(* 各ケースは有効な設定から 1 か所だけ変えた JSON を使う。 *)
let config ?(mailboxes = {|{"unprocessed": "未処理", "pending": "承認待ち"}|})
    ?(limit = "100") ?(allowed = {|["alice@example.com"]|}) ?(extra = "") () =
  Printf.sprintf {|{"mailboxes": %s, "limit": %s, "allowed": %s%s}|} mailboxes
    limit allowed extra

let valid =
  Ok
    {
      unprocessed_mailbox = "未処理";
      pending_mailbox = "承認待ち";
      limit = 100;
      allowed = [ "alice@example.com" ];
    }

let cases =
  [
    ("有効な設定", config (), valid);
    ( "空の許可リスト",
      config ~allowed:"[]" (),
      Result.map (fun t -> { t with allowed = [] }) valid );
    ( "limit下限",
      config ~limit:"1" (),
      Result.map (fun t -> { t with limit = 1 }) valid );
    ( "limit上限",
      config ~limit:"1000" (),
      Result.map (fun t -> { t with limit = max_limit }) valid );
    ("JSON破損", "{", Error Invalid_json);
    ("空文字", "", Error Invalid_json);
    ("ルートが配列", "[]", Error (Type_mismatch "(root)"));
    ("未知のキー", config ~extra:{|, "token": "x"|} (), Error (Unknown_key "token"));
    ( "入れ子の未知のキー",
      config ~mailboxes:{|{"unprocessed": "a", "pending": "b", "inbox": "c"}|}
        (),
      Error (Unknown_key "mailboxes.inbox") );
    ("重複キー", config ~extra:{|, "limit": 5|} (), Error (Duplicate_key "limit"));
    ( "入れ子の重複キー",
      config
        ~mailboxes:{|{"unprocessed": "a", "unprocessed": "b", "pending": "c"}|}
        (),
      Error (Duplicate_key "mailboxes.unprocessed") );
    ( "mailboxes欠落",
      {|{"limit": 1, "allowed": []}|},
      Error (Missing_key "mailboxes") );
    ( "pending欠落",
      config ~mailboxes:{|{"unprocessed": "a"}|} (),
      Error (Missing_key "mailboxes.pending") );
    ( "limit欠落",
      {|{"mailboxes": {"unprocessed": "a", "pending": "b"}, "allowed": []}|},
      Error (Missing_key "limit") );
    ( "allowed欠落",
      {|{"mailboxes": {"unprocessed": "a", "pending": "b"}, "limit": 1}|},
      Error (Missing_key "allowed") );
    ( "名前が数値",
      config ~mailboxes:{|{"unprocessed": 1, "pending": "b"}|} (),
      Error (Type_mismatch "mailboxes.unprocessed") );
    ( "空の名前",
      config ~mailboxes:{|{"unprocessed": "a", "pending": ""}|} (),
      Error (Empty_value "mailboxes.pending") );
    ( "同じ名前",
      config ~mailboxes:{|{"unprocessed": "a", "pending": "a"}|} (),
      Error Same_mailbox_name );
    ("limitが0", config ~limit:"0" (), Error (Out_of_range "limit"));
    ("limitが上限超過", config ~limit:"1001" (), Error (Out_of_range "limit"));
    ("limitが負", config ~limit:"-1" (), Error (Out_of_range "limit"));
    ( "limitが巨大",
      config ~limit:"99999999999999999999999" (),
      Error (Out_of_range "limit") );
    ("limitが小数", config ~limit:"1.5" (), Error (Type_mismatch "limit"));
    ("limitが文字列", config ~limit:{|"10"|} (), Error (Type_mismatch "limit"));
    ( "allowedが文字列",
      config ~allowed:{|"a@example.com"|} (),
      Error (Type_mismatch "allowed") );
    ( "allowedの要素が数値",
      config ~allowed:{|["alice@example.com", 1]|} (),
      Error (Type_mismatch "allowed[1]") );
    ( "allowedの表示名",
      config ~allowed:{|["alice@example.com", "Alice <alice@example.com>"]|} (),
      Error
        (Invalid_allowed
           { index = 1; reason = Input.Unsupported Input.Display_name_form }) );
    ( "allowedの空文字",
      config ~allowed:{|[""]|} (),
      Error
        (Invalid_allowed
           { index = 0; reason = Input.Invalid Input.Empty_address }) );
  ]

let () =
  List.iter
    (fun (name, text, expected) -> check name (parse text) expected)
    cases;
  if !failures > 0 then exit 1;
  Printf.printf "config tests passed: %d checks\n" !checks
