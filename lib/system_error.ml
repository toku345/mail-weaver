type method_error =
  | Server_unavailable
  | Server_fail
  | Server_partial_fail
  | Unknown_method
  | Invalid_arguments
  | Invalid_result_reference
  | Forbidden
  | Account_not_found
  | Account_not_supported_by_method
  | Account_read_only
  | Request_too_large
  | Anchor_not_found
  | Unsupported_sort
  | Unsupported_filter
  | Other_method_error

type protocol_problem =
  | Session_malformed
  | Mail_capability_missing
  | Api_url_not_https
  | Response_malformed
  | Missing_method_response
  | Unexpected_method_response
  | Invalid_id
  | Email_property_missing
  | Email_ids_mismatch
  | Unexpected_position
  | Unexpected_empty_page

type t =
  | Invalid_json
  | Protocol of protocol_problem
  | Method_error of method_error
  | Email_not_found
  | Query_state_changed
