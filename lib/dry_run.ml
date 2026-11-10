type entry = { id : string; outcome : Sender_input.outcome }

let string_of_address_error = function
  | Sender_input.Invalid reason -> (
      "Invalid."
      ^
      match reason with
      | Sender_input.Empty_address -> "Empty_address"
      | Control_character -> "Control_character"
      | Invalid_at_count -> "Invalid_at_count"
      | Empty_local_part -> "Empty_local_part"
      | Empty_domain -> "Empty_domain"
      | Invalid_local_part -> "Invalid_local_part"
      | Invalid_domain -> "Invalid_domain"
      | Local_part_too_long -> "Local_part_too_long"
      | Domain_label_too_long -> "Domain_label_too_long"
      | Address_too_long -> "Address_too_long")
  | Sender_input.Unsupported reason -> (
      "Unsupported."
      ^
      match reason with
      | Sender_input.Non_ascii -> "Non_ascii"
      | Quoted_form -> "Quoted_form"
      | Display_name_form -> "Display_name_form"
      | Domain_literal -> "Domain_literal"
      | Comment_form -> "Comment_form")

(* 保留理由の集計キーと、行末に付ける詳細。受信箱なら None。 *)
let pending_reason = function
  | Sender_input.Decision Sender_policy.Inbox -> None
  | Decision (Pending Sender_policy.Missing_from) -> Some ("Missing_from", [])
  | Decision (Pending Multiple_from) -> Some ("Multiple_from", [])
  | Decision (Pending Sender_not_allowed) -> Some ("Sender_not_allowed", [])
  | Pending_input From_parse_failed -> Some ("From_parse_failed", [])
  | Pending_input (Invalid_from_address { index; reason }) ->
      Some
        ( "Invalid_from_address",
          [ Printf.sprintf "index=%d" index; string_of_address_error reason ] )

let render ~limit_reached entries =
  let reasons = List.map (fun entry -> pending_reason entry.outcome) entries in
  let lines =
    List.map2
      (fun entry reason ->
        match reason with
        | None -> String.concat "\t" [ entry.id; "inbox" ]
        | Some (key, details) ->
            String.concat "\t" (entry.id :: "pending" :: key :: details))
      entries reasons
  in
  let keys = List.filter_map (Option.map fst) reasons in
  let pending = List.length keys in
  let summary =
    Printf.sprintf
      "summary\tprocessed=%d\tinbox=%d\tpending=%d\tlimit_reached=%b"
      (List.length entries)
      (List.length entries - pending)
      pending limit_reached
  in
  (* 初出順に理由ごとの件数を出す。 *)
  let distinct =
    List.fold_left
      (fun acc key -> if List.mem key acc then acc else acc @ [ key ])
      [] keys
  in
  let counts =
    List.map
      (fun key ->
        Printf.sprintf "pending_reason\t%s\t%d" key
          (List.length (List.filter (( = ) key) keys)))
      distinct
  in
  String.concat "\n" (lines @ (summary :: counts)) ^ "\n"
