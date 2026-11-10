type target = Unprocessed | Inbox | Pending
type ids = { unprocessed : string; inbox : string; pending : string }

type error =
  | Mailbox_not_found of target
  | Mailbox_ambiguous of target
  | Mailbox_conflict

let ( let* ) = Result.bind

let find target matches mailboxes =
  match List.filter matches mailboxes with
  | [ (mailbox : Jmap_response.mailbox) ] -> Ok mailbox.id
  | [] -> Error (Mailbox_not_found target)
  | _ -> Error (Mailbox_ambiguous target)

let resolve ~unprocessed_name ~pending_name mailboxes =
  let by_name name (mailbox : Jmap_response.mailbox) = mailbox.name = name in
  let* unprocessed = find Unprocessed (by_name unprocessed_name) mailboxes in
  let* inbox =
    find Inbox
      (fun (mailbox : Jmap_response.mailbox) -> mailbox.role = Some "inbox")
      mailboxes
  in
  let* pending = find Pending (by_name pending_name) mailboxes in
  if unprocessed = inbox || unprocessed = pending || inbox = pending then
    Error Mailbox_conflict
  else Ok { unprocessed; inbox; pending }
