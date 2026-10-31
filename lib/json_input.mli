(** 外部から受け取った JSON 文字列を検証付きで読み込む。

    yojson の例外メッセージは入力の断片を含み得るため、定数のエラーへ変換して捨てる。 yojson
    は同じオブジェクト内の重複キーをすべて保持するため、ここで拒否する。 *)

type error =
  | Invalid_json
  | Duplicate_key of string
      (** 最初に見つかった重複キーのパス。オブジェクトのキーは [.]、配列の位置は [[n]] で連結する。 *)

val parse : string -> (Yojson.Safe.t, error) result
