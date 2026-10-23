open Mail_weaver.Sender_input
module Policy = Mail_weaver.Sender_policy

let string_of_invalid = function
  | Empty_address -> "Empty_address"
  | Control_character -> "Control_character"
  | Invalid_at_count -> "Invalid_at_count"
  | Empty_local_part -> "Empty_local_part"
  | Empty_domain -> "Empty_domain"
  | Invalid_local_part -> "Invalid_local_part"
  | Invalid_domain -> "Invalid_domain"
  | Local_part_too_long -> "Local_part_too_long"
  | Domain_label_too_long -> "Domain_label_too_long"
  | Address_too_long -> "Address_too_long"

let string_of_unsupported = function
  | Non_ascii -> "Non_ascii"
  | Quoted_form -> "Quoted_form"
  | Display_name_form -> "Display_name_form"
  | Domain_literal -> "Domain_literal"
  | Comment_form -> "Comment_form"

let string_of_problem { index; reason } =
  let reason =
    match reason with
    | Invalid reason -> "Invalid " ^ string_of_invalid reason
    | Unsupported reason -> "Unsupported " ^ string_of_unsupported reason
  in
  Printf.sprintf "index=%d, %s" index reason

let string_of_result = function
  | Error (Invalid_allowed_address problem) ->
      "Configuration_error " ^ string_of_problem problem
  | Ok (Pending_input From_parse_failed) -> "Pending_input From_parse_failed"
  | Ok (Pending_input (Invalid_from_address problem)) ->
      "Pending_input " ^ string_of_problem problem
  | Ok (Decision Policy.Inbox) -> "Inbox"
  | Ok (Decision (Policy.Pending reason)) -> (
      "Pending "
      ^
      match reason with
      | Policy.Missing_from -> "Missing_from"
      | Policy.Multiple_from -> "Multiple_from"
      | Policy.Sender_not_allowed -> "Sender_not_allowed")

let failures = ref 0
let checks = ref 0

let check name actual expected =
  incr checks;
  if actual <> expected then begin
    incr failures;
    Printf.eprintf "FAIL - %s\n  expected: %s\n  actual:   %s\n" name
      (string_of_result expected)
      (string_of_result actual)
  end

let alice = "alice@example.com"
let inbox = Ok (Decision Policy.Inbox)
let pending reason = Ok (Decision (Policy.Pending reason))

let bad_from ?(index = 0) reason =
  Ok (Pending_input (Invalid_from_address { index; reason }))

let bad_allowed ?(index = 0) reason =
  Error (Invalid_allowed_address { index; reason })

(* 期待値は対応形式の契約から定める。From と設定で検証ルールは共通だが、
   同じ不正文字列を両方に置いた場合も、設定エラーが優先される。 *)
let invalid_cases =
  [
    ("空の要素", "", Invalid Empty_address);
    ("@なし", "alice.example.com", Invalid Invalid_at_count);
    ("@複数", "alice@@example.com", Invalid Invalid_at_count);
    ("空ローカル部", "@example.com", Invalid Empty_local_part);
    ("空ドメイン", "alice@", Invalid Empty_domain);
    ("先頭ドット", ".alice@example.com", Invalid Invalid_local_part);
    ("末尾ドット", "alice.@example.com", Invalid Invalid_local_part);
    ("連続ドット", "a..b@example.com", Invalid Invalid_local_part);
    ("先頭空白", " alice@example.com", Invalid Invalid_local_part);
    ("末尾空白", "alice@example.com ", Invalid Invalid_domain);
    ("内部空白", "a b@example.com", Invalid Invalid_local_part);
    ("禁止記号", "a:b@example.com", Invalid Invalid_local_part);
    ("区切りカンマ", "a,b@example.com", Invalid Invalid_local_part);
    ("先頭空ラベル", "alice@.example.com", Invalid Invalid_domain);
    ("内部空ラベル", "alice@example..com", Invalid Invalid_domain);
    ("末尾空ラベル", "alice@example.com.", Invalid Invalid_domain);
    ("先頭ハイフン", "alice@-example.com", Invalid Invalid_domain);
    ("末尾ハイフン", "alice@example-.com", Invalid Invalid_domain);
    ("ドメイン下線", "alice@exam_ple.com", Invalid Invalid_domain);
    ("非ASCIIローカル部", "利用者@example.com", Unsupported Non_ascii);
    ("非ASCIIドメイン", "alice@例.example", Unsupported Non_ascii);
    ("quoted形式", "\"a b\"@example.com", Unsupported Quoted_form);
    ("表示名", "Alice <alice@example.com>", Unsupported Display_name_form);
    ("山括弧のみ", "<alice@example.com>", Unsupported Display_name_form);
    ("複数@と表示名", "x@y <alice@example.com>", Unsupported Display_name_form);
    ("コメント", "alice@example.com (Alice)", Unsupported Comment_form);
    ("IPv4形式", "alice@[192.0.2.1]", Unsupported Domain_literal);
    ("IPv6形式", "alice@[IPv6:2001:db8::1]", Unsupported Domain_literal);
    ("制御文字優先", "Alice <alice@example.com>\r\n", Invalid Control_character);
    ("ローカル部65", String.make 65 'a' ^ "@example.com", Invalid Local_part_too_long);
    ( "ラベル64",
      "a@" ^ String.make 64 'b' ^ ".example",
      Invalid Domain_label_too_long );
    ( "全体255",
      String.make 64 'a' ^ "@" ^ String.make 63 'b' ^ "." ^ String.make 63 'c'
      ^ "." ^ String.make 62 'd',
      Invalid Address_too_long );
  ]

let () =
  List.iter
    (fun (name, address, reason) ->
      check (name ^ "・From")
        (decide ~from:(Parsed [ address ]) ~allowed:[ alice ])
        (bad_from reason);
      check
        (name ^ "・同一不正文字列の設定を優先")
        (decide ~from:(Parsed [ address ]) ~allowed:[ address ])
        (bad_allowed reason))
    invalid_cases;
  List.iter
    (fun code ->
      let address = "alice" ^ String.make 1 (Char.chr code) ^ "@example.com" in
      check
        (Printf.sprintf "制御文字%d" code)
        (decide ~from:(Parsed [ address ]) ~allowed:[])
        (bad_from (Invalid Control_character)))
    (List.init 32 Fun.id @ [ 127 ])

let valid_addresses =
  [
    alice;
    "Alice@EXAMPLE.COM";
    "a.b+news@example.com";
    "!#$%&'*+-/=?^_`{|}~@example.com";
    "a@exam-ple.com";
    "a@example";
    "a@xn--r8jz45g.example";
    String.make 64 'a' ^ "@example.com";
    "a@" ^ String.make 63 'b' ^ ".example";
    (* 各要素の上限内で、アドレス全体がちょうど 254 バイト。 *)
    String.make 64 'a' ^ "@" ^ String.make 63 'b' ^ "." ^ String.make 63 'c'
    ^ "." ^ String.make 61 'd';
  ]

let () =
  List.iteri
    (fun index address ->
      check
        (Printf.sprintf "対応形式%d・双方同一" index)
        (decide ~from:(Parsed [ address ]) ~allowed:[ address ])
        inbox)
    valid_addresses

type case = {
  name : string;
  from : from_input;
  allowed : string list;
  expected : (outcome, configuration_error) result;
}

let cases =
  [
    {
      name = "From欠落";
      from = Parsed [];
      allowed = [ alice ];
      expected = pending Policy.Missing_from;
    };
    {
      name = "From複数";
      from = Parsed [ alice; "bob@example.com" ];
      allowed = [ alice ];
      expected = pending Policy.Multiple_from;
    };
    {
      name = "From重複も複数";
      from = Parsed [ alice; alice ];
      allowed = [ alice ];
      expected = pending Policy.Multiple_from;
    };
    {
      name = "複数内の不正を優先";
      from = Parsed [ alice; "bob@@example.com" ];
      allowed = [ alice ];
      expected = bad_from ~index:1 (Invalid Invalid_at_count);
    };
    {
      name = "許可先頭一致でも後方設定を検証";
      from = Parsed [ alice ];
      allowed = [ alice; "bad" ];
      expected = bad_allowed ~index:1 (Invalid Invalid_at_count);
    };
    {
      name = "From欠落より設定不正を優先";
      from = Parsed [];
      allowed = [ "" ];
      expected = bad_allowed (Invalid Empty_address);
    };
    {
      name = "解析失敗";
      from = Parse_failed;
      allowed = [ alice ];
      expected = Ok (Pending_input From_parse_failed);
    };
    {
      name = "解析失敗より設定不正を優先";
      from = Parse_failed;
      allowed = [ "bad" ];
      expected = bad_allowed (Invalid Invalid_at_count);
    };
    {
      name = "設定内の最初の問題";
      from = Parsed [ alice ];
      allowed = [ alice; "bad"; "" ];
      expected = bad_allowed ~index:1 (Invalid Invalid_at_count);
    };
    {
      name = "From内の最初の問題";
      from = Parsed [ "bad"; "" ];
      allowed = [];
      expected = bad_from (Invalid Invalid_at_count);
    };
    {
      name = "ドメインのみ大小文字を同一視";
      from = Parsed [ "alice@EXAMPLE.COM" ];
      allowed = [ "alice@Example.com" ];
      expected = inbox;
    };
    {
      name = "ローカル部の大小文字を区別";
      from = Parsed [ "Alice@example.com" ];
      allowed = [ alice ];
      expected = pending Policy.Sender_not_allowed;
    };
    {
      name = "+タグを保持";
      from = Parsed [ "alice+news@example.com" ];
      allowed = [ alice ];
      expected = pending Policy.Sender_not_allowed;
    };
    {
      name = "許可側の+タグも保持";
      from = Parsed [ alice ];
      allowed = [ "alice+news@example.com" ];
      expected = pending Policy.Sender_not_allowed;
    };
    {
      name = "ドットを保持";
      from = Parsed [ "a.lice@example.com" ];
      allowed = [ alice ];
      expected = pending Policy.Sender_not_allowed;
    };
    {
      name = "部分一致を許可しない";
      from = Parsed [ "alice@example.com.evil.example" ];
      allowed = [ alice ];
      expected = pending Policy.Sender_not_allowed;
    };
    {
      name = "空の許可設定";
      from = Parsed [ alice ];
      allowed = [];
      expected = pending Policy.Sender_not_allowed;
    };
    {
      name = "許可後方一致";
      from = Parsed [ alice ];
      allowed = [ "bob@example.com"; alice ];
      expected = inbox;
    };
  ]

let () =
  List.iter
    (fun { name; from; allowed; expected } ->
      check name (decide ~from ~allowed) expected)
    cases;
  let from = Parsed [ alice ] in
  let allowed = [ alice ] in
  check "同一入力で再現する" (decide ~from ~allowed) (decide ~from ~allowed);
  if !failures > 0 then exit 1;
  Printf.printf "sender_input tests passed: %d checks\n" !checks
