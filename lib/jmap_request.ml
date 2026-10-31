let using =
  `List
    [ `String "urn:ietf:params:jmap:core"; `String "urn:ietf:params:jmap:mail" ]

let call name arguments call_id =
  `List [ `String name; `Assoc arguments; `String call_id ]

let request calls = `Assoc [ ("using", using); ("methodCalls", `List calls) ]
let strings values = `List (List.map (fun value -> `String value) values)

let mailbox_get ~account_id =
  request
    [
      call "Mailbox/get"
        [
          ("accountId", `String account_id);
          ("ids", `Null);
          ("properties", strings [ "id"; "name"; "role" ]);
        ]
        "m";
    ]

let email_page ~account_id ~mailbox_id ~position ~limit =
  request
    [
      call "Email/query"
        [
          ("accountId", `String account_id);
          ("filter", `Assoc [ ("inMailbox", `String mailbox_id) ]);
          ( "sort",
            `List
              [
                `Assoc
                  [
                    ("property", `String "receivedAt");
                    ("isAscending", `Bool true);
                  ];
              ] );
          ("position", `Int position);
          ("limit", `Int limit);
          ("calculateTotal", `Bool true);
        ]
        "q";
      call "Email/get"
        [
          ("accountId", `String account_id);
          ( "#ids",
            `Assoc
              [
                ("resultOf", `String "q");
                ("name", `String "Email/query");
                ("path", `String "/ids");
              ] );
          ("properties", strings [ "id"; "header:From:asAddresses:all" ]);
        ]
        "g";
    ]
