type t = {
  unprocessed_mailbox : string;
  pending_mailbox : string;
  limit : int;
  allowed : string list;
}

type error =
  | Invalid_json
  | Duplicate_key of string
  | Unknown_key of string
  | Missing_key of string
  | Type_mismatch of string
  | Out_of_range of string
  | Empty_value of string
  | Same_mailbox_name
  | Invalid_allowed of Sender_input.address_problem

let max_limit = 1000
let ( let* ) = Result.bind
let join path key = if path = "" then key else path ^ "." ^ key

(* 未知のキーを先に検出し、続けて必須キーを定義順に取り出す。 *)
let fields path known (json : Yojson.Safe.t) =
  match json with
  | `Assoc fields -> (
      match List.find_opt (fun (key, _) -> not (List.mem key known)) fields with
      | Some (key, _) -> Error (Unknown_key (join path key))
      | None -> Ok fields)
  | _ -> Error (Type_mismatch (if path = "" then "(root)" else path))

let member path fields key =
  match List.assoc_opt key fields with
  | Some value -> Ok value
  | None -> Error (Missing_key (join path key))

let mailbox_name path : Yojson.Safe.t -> _ = function
  | `String "" -> Error (Empty_value path)
  | `String name -> Ok name
  | _ -> Error (Type_mismatch path)

let limit : Yojson.Safe.t -> _ = function
  | `Int limit when 1 <= limit && limit <= max_limit -> Ok limit
  | `Int _ | `Intlit _ -> Error (Out_of_range "limit")
  | _ -> Error (Type_mismatch "limit")

let allowed : Yojson.Safe.t -> _ = function
  | `List items ->
      let rec loop index acc = function
        | [] -> Ok (List.rev acc)
        | `String address :: rest -> loop (index + 1) (address :: acc) rest
        | _ :: _ -> Error (Type_mismatch (Printf.sprintf "allowed[%d]" index))
      in
      loop 0 [] items
  | _ -> Error (Type_mismatch "allowed")

let decode json =
  let* root = fields "" [ "mailboxes"; "limit"; "allowed" ] json in
  let* mailboxes_json = member "" root "mailboxes" in
  let* mailboxes =
    fields "mailboxes" [ "unprocessed"; "pending" ] mailboxes_json
  in
  let* unprocessed_json = member "mailboxes" mailboxes "unprocessed" in
  let* unprocessed_mailbox =
    mailbox_name "mailboxes.unprocessed" unprocessed_json
  in
  let* pending_json = member "mailboxes" mailboxes "pending" in
  let* pending_mailbox = mailbox_name "mailboxes.pending" pending_json in
  let* limit_json = member "" root "limit" in
  let* limit = limit limit_json in
  let* allowed_json = member "" root "allowed" in
  let* allowed = allowed allowed_json in
  if unprocessed_mailbox = pending_mailbox then Error Same_mailbox_name
  else
    match Sender_input.validate_allowed allowed with
    | Error (Sender_input.Invalid_allowed_address problem) ->
        Error (Invalid_allowed problem)
    | Ok () -> Ok { unprocessed_mailbox; pending_mailbox; limit; allowed }

let parse text =
  match Json_input.parse text with
  | Error Json_input.Invalid_json -> Error Invalid_json
  | Error (Json_input.Duplicate_key path) -> Error (Duplicate_key path)
  | Ok json -> decode json
