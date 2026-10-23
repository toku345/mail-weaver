type invalid_reason =
  | Empty_address
  | Control_character
  | Invalid_at_count
  | Empty_local_part
  | Empty_domain
  | Invalid_local_part
  | Invalid_domain
  | Local_part_too_long
  | Domain_label_too_long
  | Address_too_long

type unsupported_reason =
  | Non_ascii
  | Quoted_form
  | Display_name_form
  | Domain_literal
  | Comment_form

type address_error =
  | Invalid of invalid_reason
  | Unsupported of unsupported_reason

type address_problem = { index : int; reason : address_error }
type configuration_error = Invalid_allowed_address of address_problem
type from_input = Parsed of string list | Parse_failed
type from_error = Invalid_from_address of address_problem | From_parse_failed

type outcome =
  | Decision of Sender_policy.decision
  | Pending_input of from_error

let is_alphanumeric = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true
  | _ -> false

let is_atext = function
  | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '/' | '=' | '?' | '^'
  | '_' | '`' | '{' | '|' | '}' | '~' ->
      true
  | c -> is_alphanumeric c

let valid_atom atom = String.length atom > 0 && String.for_all is_atext atom

let valid_label label =
  let length = String.length label in
  length > 0
  && is_alphanumeric label.[0]
  && is_alphanumeric label.[length - 1]
  && String.for_all (fun c -> is_alphanumeric c || c = '-') label

let validate_address address =
  let has = String.contains address in
  if address = "" then Error (Invalid Empty_address)
  else if String.exists (fun c -> Char.code c < 32 || Char.code c = 127) address
  then Error (Invalid Control_character)
  else if String.exists (fun c -> Char.code c > 127) address then
    Error (Unsupported Non_ascii)
  else if has '"' then Error (Unsupported Quoted_form)
  else if has '<' || has '>' then Error (Unsupported Display_name_form)
  else if has '[' || has ']' then Error (Unsupported Domain_literal)
  else if has '(' || has ')' then Error (Unsupported Comment_form)
  else if String.length address > 254 then Error (Invalid Address_too_long)
  else
    match String.split_on_char '@' address with
    | [ ""; _ ] -> Error (Invalid Empty_local_part)
    | [ _; "" ] -> Error (Invalid Empty_domain)
    | [ local; domain ] ->
        let labels = String.split_on_char '.' domain in
        if String.length local > 64 then Error (Invalid Local_part_too_long)
        else if not (List.for_all valid_atom (String.split_on_char '.' local))
        then Error (Invalid Invalid_local_part)
        else if List.exists (fun label -> String.length label > 63) labels then
          Error (Invalid Domain_label_too_long)
        else if not (List.for_all valid_label labels) then
          Error (Invalid Invalid_domain)
        else Ok ()
    | _ -> Error (Invalid Invalid_at_count)

let first_problem addresses =
  let rec loop index = function
    | [] -> None
    | address :: rest -> (
        match validate_address address with
        | Ok () -> loop (index + 1) rest
        | Error reason -> Some { index; reason })
  in
  loop 0 addresses

let decide ~from ~allowed =
  match first_problem allowed with
  | Some problem -> Error (Invalid_allowed_address problem)
  | None -> (
      match from with
      | Parse_failed -> Ok (Pending_input From_parse_failed)
      | Parsed addresses -> (
          match first_problem addresses with
          | Some problem -> Ok (Pending_input (Invalid_from_address problem))
          | None ->
              Ok (Decision (Sender_policy.decide ~from:addresses ~allowed))))
