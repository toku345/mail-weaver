open Mail_weaver.Sender_policy

let show_decision = function
  | Inbox -> "Inbox"
  | Pending Missing_from -> "Pending Missing_from"
  | Pending Multiple_from -> "Pending Multiple_from"
  | Pending Unapproved_sender -> "Pending Unapproved_sender"

let check_decision name expected actual =
  if expected <> actual then
    failwith
      (Printf.sprintf "%s: expected %s, got %s" name (show_decision expected)
         (show_decision actual))

let cases =
  [
    ("single allowed", [ "alice@example.test" ], [ "alice@example.test" ], Inbox);
    ( "single unapproved",
      [ "bob@example.test" ],
      [ "alice@example.test" ],
      Pending Unapproved_sender );
    ("single empty allowlist", [ "alice@example.test" ], [], Pending Unapproved_sender);
    ("missing empty allowlist", [], [], Pending Missing_from);
    ("missing populated allowlist", [], [ "alice@example.test" ], Pending Missing_from);
    ( "multiple none allowed",
      [ "alice@example.test"; "bob@example.test" ],
      [],
      Pending Multiple_from );
    ( "multiple partly allowed",
      [ "alice@example.test"; "bob@example.test" ],
      [ "alice@example.test" ],
      Pending Multiple_from );
    ( "multiple all allowed",
      [ "alice@example.test"; "bob@example.test" ],
      [ "alice@example.test"; "bob@example.test" ],
      Pending Multiple_from );
    ( "duplicate From entries still multiple",
      [ "alice@example.test"; "alice@example.test" ],
      [ "alice@example.test" ],
      Pending Multiple_from );
    ( "three From entries",
      [ "alice@example.test"; "bob@example.test"; "carol@example.test" ],
      [ "alice@example.test" ],
      Pending Multiple_from );
    ("From domain case", [ "alice@EXAMPLE.TEST" ], [ "alice@example.test" ], Inbox);
    ("allowlist domain case", [ "alice@example.test" ], [ "alice@EXAMPLE.TEST" ], Inbox);
    ("both domain cases", [ "alice@ExAmPlE.TeSt" ], [ "alice@eXaMpLe.tEsT" ], Inbox);
    ( "local case differs",
      [ "Alice@example.test" ],
      [ "alice@example.test" ],
      Pending Unapproved_sender );
    ( "allowlist local case differs",
      [ "alice@example.test" ],
      [ "Alice@EXAMPLE.TEST" ],
      Pending Unapproved_sender );
    ("same uppercase local", [ "ALICE@example.test" ], [ "ALICE@EXAMPLE.TEST" ], Inbox);
    ( "different domain",
      [ "alice@other.test" ],
      [ "alice@example.test" ],
      Pending Unapproved_sender );
    ( "same domain different local",
      [ "bob@example.test" ],
      [ "alice@example.test" ],
      Pending Unapproved_sender );
    ( "local substring",
      [ "malice@example.test" ],
      [ "alice@example.test" ],
      Pending Unapproved_sender );
    ( "reverse local substring",
      [ "alice@example.test" ],
      [ "malice@example.test" ],
      Pending Unapproved_sender );
    ( "domain suffix",
      [ "alice@sub.example.test" ],
      [ "alice@example.test" ],
      Pending Unapproved_sender );
    ( "domain prefix",
      [ "alice@example.test.other.test" ],
      [ "alice@example.test" ],
      Pending Unapproved_sender );
    ( "added plus tag",
      [ "alice+news@example.test" ],
      [ "alice@example.test" ],
      Pending Unapproved_sender );
    ( "removed plus tag",
      [ "alice@example.test" ],
      [ "alice+news@example.test" ],
      Pending Unapproved_sender );
    ( "different plus tags",
      [ "alice+news@example.test" ],
      [ "alice+alerts@example.test" ],
      Pending Unapproved_sender );
    ("same plus tag", [ "alice+news@example.test" ], [ "alice+news@EXAMPLE.TEST" ], Inbox);
    ( "local dots preserved",
      [ "alice.smith@example.test" ],
      [ "alicesmith@example.test" ],
      Pending Unapproved_sender );
    ( "match among several allowed addresses",
      [ "alice@example.test" ],
      [ "bob@other.test"; "alice@EXAMPLE.TEST"; "carol@example.test" ],
      Inbox );
  ]

let () =
  List.iter
    (fun (name, from, addresses, expected) ->
      let allowlist = Address_set.of_list addresses in
      let before = Address_set.elements allowlist in
      check_decision name expected (decide ~from ~allowlist);
      check_decision (name ^ " repeated") expected (decide ~from ~allowlist);
      if Address_set.elements allowlist <> before then
        failwith (name ^ ": allowlist was changed"))
    cases;
  Printf.printf "sender policy: %d cases passed (including repeat and immutability checks)\n"
    (List.length cases)
