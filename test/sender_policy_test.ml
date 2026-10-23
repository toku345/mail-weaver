open Mail_weaver.Sender_policy

let string_of_reason = function
  | Missing_from -> "Missing_from"
  | Multiple_from -> "Multiple_from"
  | Sender_not_allowed -> "Sender_not_allowed"

let string_of_decision = function
  | Inbox -> "Inbox"
  | Pending reason -> "Pending " ^ string_of_reason reason

let failures = ref 0

let check name actual expected =
  if actual = expected then Printf.printf "ok   - %s\n" name
  else begin
    incr failures;
    Printf.printf "FAIL - %s\n" name;
    Printf.printf "       expected: %s\n" (string_of_decision expected);
    Printf.printf "       actual:   %s\n" (string_of_decision actual)
  end

let check_bool name actual =
  if actual then Printf.printf "ok   - %s\n" name
  else begin
    incr failures;
    Printf.printf "FAIL - %s\n" name
  end

let user = "user@example.com"

(* 内容のコピーを作る。in-place の文字列変更があれば比較で検出できる。
   OCaml 5.4 の stdlib に String.copy はないため String.sub を使う。 *)
let copy_string s = String.sub s 0 (String.length s)

type case = {
  name : string;
  from : string list;
  allowed : string list;
  expected : decision;
}

let cases =
  [
    (* From の件数を、許可リストへの一致より先に判定する。 *)
    {
      name = "1件・一致あり -> 受信箱";
      from = [ "user@example.com" ];
      allowed = [ "user@example.com"; "other@example.net" ];
      expected = Inbox;
    };
    {
      name = "1件・一致なし -> 承認待ち（未許可）";
      from = [ "user@example.com" ];
      allowed = [ "other@example.net" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "1件・許可リスト空 -> 承認待ち（未許可）";
      from = [ "user@example.com" ];
      allowed = [];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "欠落・0件（許可リスト空） -> 承認待ち（From欠落）";
      from = [];
      allowed = [];
      expected = Pending Missing_from;
    };
    {
      name = "欠落・0件（許可あり） -> 承認待ち（From欠落）";
      from = [];
      allowed = [ "user@example.com" ];
      expected = Pending Missing_from;
    };
    {
      name = "2件以上・一部が許可済み -> 承認待ち（From複数）";
      from = [ "user@example.com"; "other@example.net" ];
      allowed = [ "user@example.com" ];
      expected = Pending Multiple_from;
    };
    {
      name = "2件以上・全部が許可済み -> 承認待ち（From複数）";
      from = [ "user@example.com"; "other@example.net" ];
      allowed = [ "user@example.com"; "other@example.net" ];
      expected = Pending Multiple_from;
    };
    {
      name = "3件 -> 承認待ち（From複数）";
      from = [ "user@example.com"; "other@example.net"; "third@example.org" ];
      allowed = [ "user@example.com" ];
      expected = Pending Multiple_from;
    };
    {
      name = "同じ許可済み From が2件 -> 承認待ち（From複数）";
      from = [ "user@example.com"; "user@example.com" ];
      allowed = [ "user@example.com" ];
      expected = Pending Multiple_from;
    };
    {
      name = "2件以上・全部が未許可 -> 承認待ち（From複数）";
      from = [ "user@example.com"; "other@example.net" ];
      allowed = [ "allowed@example.org" ];
      expected = Pending Multiple_from;
    };
    (* ドメインの大小文字は同一視、ローカル部はそのまま比較する。 *)
    {
      name = "From ドメインが大文字 -> 一致して受信箱";
      from = [ "user@Example.COM" ];
      allowed = [ "user@example.com" ];
      expected = Inbox;
    };
    {
      name = "許可リスト ドメインが大文字 -> 一致して受信箱";
      from = [ "user@example.com" ];
      allowed = [ "user@EXAMPLE.com" ];
      expected = Inbox;
    };
    {
      name = "双方ドメインが大文字 -> 一致して受信箱";
      from = [ "user@EXAMPLE.COM" ];
      allowed = [ "user@Example.com" ];
      expected = Inbox;
    };
    {
      name = "From ローカル部が大文字 -> 区別して承認待ち（未許可）";
      from = [ "User@example.com" ];
      allowed = [ "user@example.com" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "許可リスト ローカル部が大文字 -> 区別して承認待ち（未許可）";
      from = [ "user@example.com" ];
      allowed = [ "User@example.com" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "ローカル部のみ大文字差（ドメインは一致） -> 承認待ち（未許可）";
      from = [ "User@Example.com" ];
      allowed = [ "user@example.com" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "双方が同じ大文字ローカル部 -> 一致して受信箱";
      from = [ "User@Example.COM" ];
      allowed = [ "User@example.com" ];
      expected = Inbox;
    };
    (* 有効なアドレス同士で、完全一致以外を誤って許可しないことを確認する。
       ドメインのみ・表示名混入などの前提外入力の検証は Issue #7 で扱う。 *)
    {
      name = "別ドメイン -> 承認待ち（未許可）";
      from = [ "user@example.com" ];
      allowed = [ "user@example.org" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "同じドメイン・別ローカル部 -> 承認待ち（未許可）";
      from = [ "user@example.com" ];
      allowed = [ "other@example.com" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "部分一致（許可リスト側が接尾辞） -> 承認待ち（未許可）";
      from = [ "user@example.com" ];
      allowed = [ "user@example.com.evil.example" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "部分一致（From側が接尾辞） -> 承認待ち（未許可）";
      from = [ "user@example.com.evil.example" ];
      allowed = [ "user@example.com" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "+タグ付きの From -> 承認待ち（未許可）";
      from = [ "user+news@example.com" ];
      allowed = [ "user@example.com" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "+タグ付きの許可リスト -> 承認待ち（未許可）";
      from = [ "user@example.com" ];
      allowed = [ "user+news@example.com" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "双方が同じ+タグ -> 一致して受信箱";
      from = [ "user+news@example.com" ];
      allowed = [ "user+news@example.com" ];
      expected = Inbox;
    };
    {
      name = "双方の+タグが異なる -> 承認待ち（未許可）";
      from = [ "user+news@example.com" ];
      allowed = [ "user+shop@example.com" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "Gmail のドット除去はしない -> 承認待ち（未許可）";
      from = [ "u.ser@gmail.com" ];
      allowed = [ "user@gmail.com" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "双方が同じドット付きローカル部 -> 一致して受信箱";
      from = [ "u.ser@gmail.com" ];
      allowed = [ "u.ser@gmail.com" ];
      expected = Inbox;
    };
    {
      name = "許可側だけローカル部にドット -> 承認待ち（未許可）";
      from = [ "user@gmail.com" ];
      allowed = [ "u.ser@gmail.com" ];
      expected = Pending Sender_not_allowed;
    };
    {
      name = "許可リストの後方に一致 -> 受信箱";
      from = [ "user@example.com" ];
      allowed = [ "other@example.net"; "user@example.com" ];
      expected = Inbox;
    };
  ]

let () =
  List.iter
    (fun { name; from; allowed; expected } ->
      check name (decide ~from ~allowed) expected)
    cases

(* 純粋性：同じ入力は同じ結果、入力は書き換えない *)
let () =
  let from = [ user ] in
  let allowed = [ "user@example.com"; "other@example.net" ] in
  (* 内容のコピーを取る。in-place の文字列変更があれば比較で検出できる。 *)
  let from_snapshot = List.map copy_string from in
  let allowed_snapshot = List.map copy_string allowed in
  let first = decide ~from ~allowed in
  let second = decide ~from ~allowed in
  check_bool "同じ入力は同じ結果（1回目=2回目）" (first = second);
  check_bool "From 一覧を書き換えない（値）" (from = from_snapshot);
  check_bool "許可リストを書き換えない（値）" (allowed = allowed_snapshot);
  check_bool "許可リストを書き換えない（長さ）" (List.length allowed = 2)

let () =
  if !failures = 0 then print_endline "sender_policy tests passed"
  else begin
    Printf.printf "sender_policy tests failed: %d\n" !failures;
    exit 1
  end
