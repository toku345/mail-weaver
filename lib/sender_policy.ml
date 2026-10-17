type pending_reason = Missing_from | Multiple_from | Sender_not_allowed
type decision = Inbox | Pending of pending_reason

(* 比較用の正規化。ドメイン部分だけ ASCII 小文字化し、ローカル部はそのまま残す。
   入力は local-part@domain 形式で '@' を 1 つだけ含む前提なので、最初の '@' で分割する。 *)
let canonicalize address =
  match String.index_opt address '@' with
  | None -> address
  | Some i ->
      let local = String.sub address 0 i in
      let domain = String.sub address (i + 1) (String.length address - i - 1) in
      local ^ "@" ^ String.lowercase_ascii domain

let is_allowed ~allowed canonical_from =
  List.exists (fun candidate -> canonicalize candidate = canonical_from) allowed

let decide ~from ~allowed =
  match from with
  | [] -> Pending Missing_from
  | [ sender ] ->
      let canonical_from = canonicalize sender in
      if is_allowed ~allowed canonical_from then Inbox
      else Pending Sender_not_allowed
  | _ :: _ :: _ -> Pending Multiple_from
