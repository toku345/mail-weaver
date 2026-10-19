(lang dune 3.24)
(name mail_weaver)
(generate_opam_files true)
(maintainers "toku345")
(authors "toku345")
(source (github toku345/mail-weaver))
(package
 (name mail_weaver)
 ; 依存管理用のパッケージであり、ライブラリの公開対象は追加しない。
 (allow_empty)
 (synopsis "Mail-weaver メール整理アシスタント")
 (depends
  (ocaml (= 5.4.1))
  (dune (= 3.24.2))
  (ocamlformat (= 0.29.0))))
(formatting (enabled_for ocaml))
