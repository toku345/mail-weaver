type error = Invalid_json | Duplicate_key of string

let join path key = if path = "" then key else path ^ "." ^ key

let rec find_duplicate path (json : Yojson.Safe.t) =
  match json with
  | `Assoc fields ->
      let rec loop seen = function
        | [] -> None
        | (key, value) :: rest -> (
            if List.mem key seen then Some (join path key)
            else
              match find_duplicate (join path key) value with
              | Some _ as duplicate -> duplicate
              | None -> loop (key :: seen) rest)
      in
      loop [] fields
  | `List items ->
      List.find_map Fun.id
        (List.mapi
           (fun index item ->
             find_duplicate (Printf.sprintf "%s[%d]" path index) item)
           items)
  | _ -> None

let parse text =
  match Yojson.Safe.from_string text with
  | exception Yojson.Json_error _ -> Error Invalid_json
  | json -> (
      match find_duplicate "" json with
      | Some path -> Error (Duplicate_key path)
      | None -> Ok json)
