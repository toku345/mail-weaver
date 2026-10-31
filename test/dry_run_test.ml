module Dry_run = Mail_weaver.Dry_run
module Input = Mail_weaver.Sender_input

let failures = ref 0
let checks = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf "FAIL - %s\n" name
  end

let allowed = [ "alice@example.com" ]

(* 実際の判定関数を通して、各経路が出力で区別されることを確かめる。 *)
let entry id from =
  match Input.decide ~from ~allowed with
  | Ok outcome -> { Dry_run.id; outcome }
  | Error _ -> failwith "invalid test configuration"

let entries =
  [
    entry "M1" (Input.Parsed [ "alice@example.com" ]);
    entry "M2" (Input.Parsed [ "bob@example.com" ]);
    entry "M3" (Input.Parsed []);
    entry "M4" (Input.Parsed [ "alice@example.com"; "bob@example.com" ]);
    entry "M5" (Input.Parsed [ "Bob <bob@example.com>" ]);
    entry "M6" Input.Parse_failed;
    entry "M7" (Input.Parsed [ "carol@example.com" ]);
  ]

let expected =
  {|M1	inbox
M2	pending	Sender_not_allowed
M3	pending	Missing_from
M4	pending	Multiple_from
M5	pending	Invalid_from_address	index=0	Unsupported.Display_name_form
M6	pending	From_parse_failed
M7	pending	Sender_not_allowed
summary	processed=7	inbox=1	pending=6	limit_reached=true
pending_reason	Sender_not_allowed	2
pending_reason	Missing_from	1
pending_reason	Multiple_from	1
pending_reason	Invalid_from_address	1
pending_reason	From_parse_failed	1
|}

let contains text fragment =
  let n = String.length fragment in
  let rec loop i =
    i + n <= String.length text
    && (String.sub text i n = fragment || loop (i + 1))
  in
  loop 0

let () =
  let output = Dry_run.render ~limit_reached:true entries in
  check "全経路の出力" (output = expected);
  if output <> expected then prerr_string output;
  check "アドレスを出力しない"
    (not
       (List.exists (contains output)
          [ "@"; "alice"; "bob"; "carol"; "example" ]));
  check "0件"
    (Dry_run.render ~limit_reached:false []
    = "summary\tprocessed=0\tinbox=0\tpending=0\tlimit_reached=false\n");
  if !failures > 0 then exit 1;
  Printf.printf "dry_run tests passed: %d checks\n" !checks
