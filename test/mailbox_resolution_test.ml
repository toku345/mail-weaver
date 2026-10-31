open Mail_weaver.Mailbox_resolution
module Response = Mail_weaver.Jmap_response

let failures = ref 0
let checks = ref 0

let check name actual expected =
  incr checks;
  if actual <> expected then begin
    incr failures;
    Printf.eprintf "FAIL - %s\n" name
  end

let mailbox ?role id name : Response.mailbox = { id; name; role }
let inbox = mailbox ~role:"inbox" "I" "Inbox"
let unprocessed = mailbox "U" "未処理"
let pending = mailbox "P" "承認待ち"

let resolve mailboxes =
  resolve ~unprocessed_name:"未処理" ~pending_name:"承認待ち" mailboxes

let cases =
  [
    ( "一意に解決",
      [ inbox; unprocessed; pending; mailbox ~role:"archive" "A" "Archive" ],
      Ok { unprocessed = "U"; inbox = "I"; pending = "P" } );
    ( "受信箱は名前でなくroleで決まる",
      [
        mailbox ~role:"inbox" "I" "受信トレイ";
        mailbox "X" "Inbox";
        unprocessed;
        pending;
      ],
      Ok { unprocessed = "U"; inbox = "I"; pending = "P" } );
    ("未処理なし", [ inbox; pending ], Error (Mailbox_not_found Unprocessed));
    ("受信箱なし", [ unprocessed; pending ], Error (Mailbox_not_found Inbox));
    ("承認待ちなし", [ inbox; unprocessed ], Error (Mailbox_not_found Pending));
    ( "未処理が複数",
      [ inbox; unprocessed; mailbox "U2" "未処理"; pending ],
      Error (Mailbox_ambiguous Unprocessed) );
    ( "受信箱が複数",
      [ inbox; mailbox ~role:"inbox" "I2" "Inbox2"; unprocessed; pending ],
      Error (Mailbox_ambiguous Inbox) );
    ( "名前は完全一致",
      [ inbox; mailbox "U" "未処理 "; pending ],
      Error (Mailbox_not_found Unprocessed) );
    ( "未処理が受信箱と同じ",
      [ mailbox ~role:"inbox" "I" "未処理"; pending ],
      Error Mailbox_conflict );
  ]

let () =
  List.iter
    (fun (name, mailboxes, expected) -> check name (resolve mailboxes) expected)
    cases;
  if !failures > 0 then exit 1;
  Printf.printf "mailbox_resolution tests passed: %d checks\n" !checks
