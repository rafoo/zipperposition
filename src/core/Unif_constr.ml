
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Unification Constraint} *)

module T = InnerTerm

type t = InnerTerm.t * InnerTerm.t

let apply_subst ~renaming subst (sc1,sc2) (c:t): t =
  let t, u = c in
  Subst.apply ~renaming subst (t,sc1), Subst.apply ~renaming subst (u,sc2)

let apply_subst_l ~renaming subst (sc1,sc2) (l:_ list): _ list =
  List.map (apply_subst ~renaming subst (sc1,sc2)) l

let pp out (t,u) = CCFormat.fprintf out "(@[%a =?=@ %a@])" T.pp t T.pp u

let hash = Hash.pair T.hash T.hash
let equal = CCPair.equal T.equal T.equal
let compare = CCPair.compare T.compare T.compare
let to_string = CCFormat.to_string pp
