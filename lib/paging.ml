type request = { position : int; limit : int }

type t = {
  remaining : int;
  position : int;
  page_cap : int;
  query_state : string option;
  total : int option;
  finished : bool;
}

let page_size = 50

let start ~limit ~max_objects_in_get =
  {
    remaining = limit;
    position = 0;
    page_cap = min page_size max_objects_in_get;
    query_state = None;
    total = None;
    finished = false;
  }

let next t =
  if t.finished || t.remaining = 0 then None
  else Some { position = t.position; limit = min t.remaining t.page_cap }

let protocol problem = Error (System_error.Protocol problem)

let advance t (request : request) ~query_state ~position ~total ~returned =
  if position <> request.position then protocol System_error.Unexpected_position
  else if returned > request.limit then protocol System_error.Response_malformed
  else if Option.fold ~none:false ~some:(( <> ) query_state) t.query_state then
    Error System_error.Query_state_changed
  else if returned = 0 && position < total then
    protocol System_error.Unexpected_empty_page
  else
    let position = position + returned in
    let remaining = t.remaining - returned in
    Ok
      {
        t with
        remaining;
        position;
        query_state = Some query_state;
        total = Some total;
        finished = returned = 0 || position >= total || remaining = 0;
      }

let limit_reached t =
  match t.total with
  | Some total -> t.remaining = 0 && t.position < total
  | None -> false
