module Address_set = Set.Make (String)

type pending_reason =
  | Missing_from
  | Multiple_from
  | Unapproved_sender

type decision = Inbox | Pending of pending_reason

let normalize_domain address =
  let domain_start = String.index address '@' + 1 in
  let local = String.sub address 0 domain_start in
  let domain =
    String.sub address domain_start (String.length address - domain_start)
  in
  local ^ String.lowercase_ascii domain

let decide ~from ~allowlist =
  match from with
  | [] -> Pending Missing_from
  | [ address ] ->
      let normalized = normalize_domain address in
      if
        Address_set.exists
          (fun allowed -> String.equal normalized (normalize_domain allowed))
          allowlist
      then Inbox
      else Pending Unapproved_sender
  | _ -> Pending Multiple_from
