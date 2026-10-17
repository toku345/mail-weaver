let () =
  if String.concat "-" [ "mail"; "weaver" ] <> "mail-weaver" then
    failwith "standard library smoke test failed";
  print_endline "smoke test passed"
