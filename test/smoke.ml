let expected_name unused = "mail-weaver"

let () =
  if String.concat "-" [ "mail"; "weaver" ] <> expected_name () then
    failwith "standard library smoke test failed";
  print_endline "smoke test passed"
