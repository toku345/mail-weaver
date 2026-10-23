(** 生入力から送信者判定へ進むための検証境界。

    From と [allowed] に共通の検証を行う。対応形式は ASCII の dot-atom
    ローカル部と英数字・ハイフンによるドメインラベルに限る。 ローカル部は 64、各ラベルは 63、全体は 254 バイトまで。
    単一ラベルも受け付けるが、DNS・実在・送信者認証は検証しない。 補正は行わず、比較用の正規化は [Sender_policy] に任せる。 *)

type invalid_reason =
  | Empty_address
  | Control_character
  | Invalid_at_count
  | Empty_local_part
  | Empty_domain
  | Invalid_local_part
  | Invalid_domain
  | Local_part_too_long
  | Domain_label_too_long
  | Address_too_long

type unsupported_reason =
  | Non_ascii
  | Quoted_form
  | Display_name_form
  | Domain_literal
  | Comment_form

(** [Unsupported] は対応範囲外の特徴を表し、RFC 上の正当性は保証しない。 検査順は制御文字、非
    ASCII、引用符、山括弧、角括弧、丸括弧、全体長、構文詳細の順。 複数の問題があれば最初の理由を返す。 *)
type address_error =
  | Invalid of invalid_reason
  | Unsupported of unsupported_reason

type address_problem = { index : int; reason : address_error }
(** [index] は一覧内の 0 始まりの位置。原文や入力由来の文字は保持しない。 *)

type configuration_error = Invalid_allowed_address of address_problem

(** [Parsed] は取得元から抽出できた一覧であり、検証済みを意味しない。 欠落は [Parsed []]、空の要素は [Parsed [""]]
    と区別する。 [Parse_failed] はメッセージ固有の構造を解釈できなかった場合に使う。 未取得・通信障害・認証障害・レスポンス全体の JSON
    破損には使わず、 呼び出し側のシステムエラーとして処理する。JMAP の抽出契約は README を参照。 *)
type from_input = Parsed of string list | Parse_failed

type from_error = Invalid_from_address of address_problem | From_parse_failed

type outcome =
  | Decision of Sender_policy.decision
  | Pending_input of from_error

val decide :
  from:from_input ->
  allowed:string list ->
  (outcome, configuration_error) result
(** [allowed]、From の順で検証し、両方に問題がなければ既存の判定関数を呼ぶ。 [allowed] の問題は [Error]、From の問題は
    [Ok (Pending_input ...)] を返す。 各一覧では最初の問題を返す。有効な From が複数なら既存の
    [Multiple_from]、 不正な要素を含めば入力エラーが優先する。 生入力を使う連携では、この入口を使用すること。

    入力は変更せず、ネットワーク・ファイル・DB・ログ出力に依存しない。 *)
