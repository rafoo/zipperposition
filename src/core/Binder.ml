
(* This file is free software, part of Libzipperposition. See file "license" for more details. *)

(** {1 Binders} *)

type t =
  | Exists
  | Forall
  | ForallTy
  | Lambda

let forall = Forall
let exists = Exists
let lambda = Lambda
let forall_ty = ForallTy

let compare (a:t) b = Pervasives.compare a b
let equal (a:t) b = a=b
let hash (a:t) = Hashtbl.hash a
let hash_fun a h = CCHash.int (hash a) h

let to_string = function
  | Exists -> "∃"
  | Forall -> "∀"
  | Lambda -> "λ"
  | ForallTy -> "Π"
let pp out t = CCFormat.string out (to_string t)

module TPTP = struct
  let to_string = function
    | Exists -> "?"
    | Forall -> "!"
    | ForallTy -> "!>"
    | Lambda -> "^"
  let pp out t = CCFormat.string out (to_string t)
end
