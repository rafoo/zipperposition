
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Unification Substitution} *)

(** A tuple containing:

    - the substitution itself
    - delayed constraints
*)

type term = Subst.term
type var = Subst.var

type t = {
  subst: Subst.t;
  cstr_l: Unif_constr.t list;
}

let subst t = t.subst
let constr_l t = t.cstr_l

let make subst cstr_l = {subst; cstr_l}

let empty : t = make Subst.empty []

let map_subst ~f t = {t with subst=f t.subst}
let of_subst s = make s []

let bind t v u = {t with subst=Subst.bind t.subst v u}
let deref t v = Subst.deref t.subst v

let has_constr t: bool = constr_l t <> []

let add_constr c t = {t with cstr_l = c :: t.cstr_l}

let pp out t: unit =
  if has_constr t
  then Format.fprintf out "(@[%a@ :constr_l (@[<hv>%a@])@])"
      Subst.pp (subst t) (Util.pp_list ~sep:"" Unif_constr.pp) (constr_l t)
  else Subst.pp out (subst t)

let equal a b =
  Subst.equal (subst a) (subst b) &&
  CCList.equal Unif_constr.equal (constr_l a) (constr_l b)

let hash a =
  Hash.combine2 (Subst.hash @@ subst a)
    (Hash.list Unif_constr.hash @@ constr_l a)

let compare a b =
  let open CCOrd.Infix in
  Subst.compare (subst a)(subst b)
  <?> (CCList.compare Unif_constr.compare, constr_l a, constr_l b)

let to_string = CCFormat.to_string pp
