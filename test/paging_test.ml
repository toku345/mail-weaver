module Paging = Mail_weaver.Paging
module E = Mail_weaver.System_error

let failures = ref 0
let checks = ref 0

let check name actual expected =
  incr checks;
  if actual <> expected then begin
    incr failures;
    Printf.eprintf "FAIL - %s\n" name
  end

type outcome = {
  requests : (int * int) list;  (** 送った (position, limit) *)
  fetched : int;
  limit_reached : bool;
}

(* 架空のサーバーに対してページングを最後まで回す。[respond] は何回目の要求かと要求を受け取り、
   (queryState, position, total, 返す件数) を返す。無限ループを防ぐため要求回数に上限を置く。 *)
let run ~limit ~max_objects_in_get respond =
  let rec loop state call requests fetched =
    if call > 100 then failwith "paging did not terminate"
    else
      match Paging.next state with
      | None ->
          Ok
            {
              requests = List.rev requests;
              fetched;
              limit_reached = Paging.limit_reached state;
            }
      | Some request -> (
          let query_state, position, total, returned = respond call request in
          match
            Paging.advance state request ~query_state ~position ~total ~returned
          with
          | Error _ as error -> error
          | Ok state ->
              loop state (call + 1)
                ((request.Paging.position, request.limit) :: requests)
                (fetched + returned))
  in
  loop (Paging.start ~limit ~max_objects_in_get) 0 [] 0

(* 一覧が変わらない通常のサーバー。1 回に最大 [cap] 件だけ返す。 *)
let server ?(cap = max_int) total _call (request : Paging.request) =
  ( "qs",
    request.position,
    total,
    min (min request.limit cap) (max 0 (total - request.position)) )

let cases =
  [
    ( "1ページで全件",
      run ~limit:100 ~max_objects_in_get:500 (server 30),
      Ok { requests = [ (0, 50) ]; fetched = 30; limit_reached = false } );
    ( "0件で終了",
      run ~limit:100 ~max_objects_in_get:500 (server 0),
      Ok { requests = [ (0, 50) ]; fetched = 0; limit_reached = false } );
    ( "ちょうどページ境界",
      run ~limit:100 ~max_objects_in_get:500 (server 50),
      Ok { requests = [ (0, 50) ]; fetched = 50; limit_reached = false } );
    ( "サーバーが件数を縮めても取り残さない",
      run ~limit:100 ~max_objects_in_get:500 (server ~cap:20 70),
      Ok
        {
          requests = [ (0, 50); (20, 50); (40, 50); (60, 40) ];
          fetched = 70;
          limit_reached = false;
        } );
    ( "上限をまたぐ最終ページ",
      run ~limit:120 ~max_objects_in_get:500 (server 500),
      Ok
        {
          requests = [ (0, 50); (50, 50); (100, 20) ];
          fetched = 120;
          limit_reached = true;
        } );
    ( "上限ちょうどで残りなし",
      run ~limit:100 ~max_objects_in_get:500 (server 100),
      Ok
        {
          requests = [ (0, 50); (50, 50) ];
          fetched = 100;
          limit_reached = false;
        } );
    ( "maxObjectsInGetがページサイズより小さい",
      run ~limit:25 ~max_objects_in_get:10 (server 100),
      Ok
        {
          requests = [ (0, 10); (10, 10); (20, 5) ];
          fetched = 25;
          limit_reached = true;
        } );
    ( "queryStateの変化で中断",
      run ~limit:100 ~max_objects_in_get:500 (fun call request ->
          let _, position, total, returned = server 120 call request in
          ((if call = 0 then "qs" else "qs2"), position, total, returned)),
      Error E.Query_state_changed );
    ( "位置の不一致",
      run ~limit:100 ~max_objects_in_get:500 (fun _ _ -> ("qs", 5, 120, 10)),
      Error (E.Protocol E.Unexpected_position) );
    ( "要求より多く返る",
      run ~limit:100 ~max_objects_in_get:500 (fun _ request ->
          ("qs", request.position, 500, 51)),
      Error (E.Protocol E.Response_malformed) );
    ( "totalが残っているのに空ページ",
      run ~limit:100 ~max_objects_in_get:500 (fun _ request ->
          ("qs", request.position, 10, 0)),
      Error (E.Protocol E.Unexpected_empty_page) );
  ]

let () =
  List.iter (fun (name, actual, expected) -> check name actual expected) cases;
  check "ページサイズ" Paging.page_size 50;
  check "設定1000とmaxObjectsInGet500で複数ページ"
    (Result.map
       (fun outcome ->
         (List.length outcome.requests, outcome.fetched, outcome.limit_reached))
       (run ~limit:1000 ~max_objects_in_get:500 (server 2000)))
    (Ok (20, 1000, true));
  if !failures > 0 then exit 1;
  Printf.printf "paging tests passed: %d checks\n" !checks
