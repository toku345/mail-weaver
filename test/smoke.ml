let () =
  if String.concat "-" [ "mail"; "weaver" ] <> "intentional-ci-failure" then
    failwith "standard library smoke test failed";
  print_endline "smoke test passed"
