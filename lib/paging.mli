(** [Email/query] のページングを進める純粋な状態機械。

    ページサイズは「残りの処理件数・[page_size]・Session の [maxObjectsInGet]」の最小値。
    次の位置は実際に返った件数だけ進め、サーバーが件数を縮めても取り残さない。 設定上限・[total] への到達、または 0 件のページで終了する。
    [queryState] がページの途中で変わった場合は、取得漏れ・重複があり得るためエラーにする。 *)

type request = { position : int; limit : int }
type t

val page_size : int

val start : limit:int -> max_objects_in_get:int -> t
(** [limit] と [max_objects_in_get] は 1 以上であること（設定・Session の解釈で検証済み）。 *)

val next : t -> request option
(** 次に送る要求。終了していれば [None]。 *)

val advance :
  t ->
  request ->
  query_state:string ->
  position:int ->
  total:int ->
  returned:int ->
  (t, System_error.t) result
(** [request] に対する応答で状態を進める。 *)

val limit_reached : t -> bool
(** 設定上限で止まり、未取得のメールが残っている。 *)
