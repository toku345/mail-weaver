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

(* 実装仕様の判定表 *)
let () =
  check "1件・一致あり -> 受信箱"
    (decide
       ~from:[ "user@example.com" ]
       ~allowed:[ "user@example.com"; "other@example.net" ])
    Inbox;
  check "1件・一致なし -> 承認待ち（未許可）"
    (decide ~from:[ "user@example.com" ] ~allowed:[ "other@example.net" ])
    (Pending Sender_not_allowed);
  check "1件・許可リスト空 -> 承認待ち（未許可）"
    (decide ~from:[ "user@example.com" ] ~allowed:[])
    (Pending Sender_not_allowed);
  check "欠落・0件（許可リスト空） -> 承認待ち（From欠落）"
    (decide ~from:[] ~allowed:[])
    (Pending Missing_from);
  check "欠落・0件（許可あり） -> 承認待ち（From欠落）"
    (decide ~from:[] ~allowed:[ "user@example.com" ])
    (Pending Missing_from);
  check "2件以上・一部が許可済み -> 承認待ち（From複数）"
    (decide
       ~from:[ "user@example.com"; "other@example.net" ]
       ~allowed:[ "user@example.com" ])
    (Pending Multiple_from);
  check "2件以上・全部が許可済み -> 承認待ち（From複数）"
    (decide
       ~from:[ "user@example.com"; "other@example.net" ]
       ~allowed:[ "user@example.com"; "other@example.net" ])
    (Pending Multiple_from);
  check "3件 -> 承認待ち（From複数）"
    (decide
       ~from:[ "user@example.com"; "other@example.net"; "third@example.org" ]
       ~allowed:[ "user@example.com" ])
    (Pending Multiple_from)

(* ドメインの大小文字は同一視、ローカル部は区別する *)
let () =
  check "From ドメインが大文字 -> 一致して受信箱"
    (decide ~from:[ "user@Example.COM" ] ~allowed:[ "user@example.com" ])
    Inbox;
  check "許可リスト ドメインが大文字 -> 一致して受信箱"
    (decide ~from:[ "user@example.com" ] ~allowed:[ "user@EXAMPLE.com" ])
    Inbox;
  check "双方ドメインが大文字 -> 一致して受信箱"
    (decide ~from:[ "user@EXAMPLE.COM" ] ~allowed:[ "user@Example.com" ])
    Inbox;
  check "From ローカル部が大文字 -> 区別して承認待ち（未許可）"
    (decide ~from:[ "User@example.com" ] ~allowed:[ "user@example.com" ])
    (Pending Sender_not_allowed);
  check "許可リスト ローカル部が大文字 -> 区別して承認待ち（未許可）"
    (decide ~from:[ "user@example.com" ] ~allowed:[ "User@example.com" ])
    (Pending Sender_not_allowed);
  check "ローカル部のみ大文字差（ドメインは一致） -> 承認待ち（未許可）"
    (decide ~from:[ "User@Example.com" ] ~allowed:[ "user@example.com" ])
    (Pending Sender_not_allowed)

(* 誤って許可しないこと *)
let () =
  check "別ドメイン -> 承認待ち（未許可）"
    (decide ~from:[ "user@example.com" ] ~allowed:[ "user@example.org" ])
    (Pending Sender_not_allowed);
  check "許可リストがドメインのみ -> 承認待ち（未許可）"
    (decide ~from:[ "user@example.com" ] ~allowed:[ "example.com" ])
    (Pending Sender_not_allowed);
  check "部分一致（許可リスト側が接尾辞） -> 承認待ち（未許可）"
    (decide
       ~from:[ "user@example.com" ]
       ~allowed:[ "user@example.com.evil.example" ])
    (Pending Sender_not_allowed);
  check "部分一致（From側が接尾辞） -> 承認待ち（未許可）"
    (decide
       ~from:[ "user@example.com.evil.example" ]
       ~allowed:[ "user@example.com" ])
    (Pending Sender_not_allowed);
  check "+タグ付きの From -> 承認待ち（未許可）"
    (decide ~from:[ "user+news@example.com" ] ~allowed:[ "user@example.com" ])
    (Pending Sender_not_allowed);
  check "+タグ付きの許可リスト -> 承認待ち（未許可）"
    (decide ~from:[ "user@example.com" ] ~allowed:[ "user+news@example.com" ])
    (Pending Sender_not_allowed);
  check "Gmail のドット除去はしない -> 承認待ち（未許可）"
    (decide ~from:[ "u.ser@gmail.com" ] ~allowed:[ "user@gmail.com" ])
    (Pending Sender_not_allowed);
  check "表示名つきは解析しない -> 承認待ち（未許可）"
    (decide ~from:[ "User <user@example.com>" ] ~allowed:[ "user@example.com" ])
    (Pending Sender_not_allowed)

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
