
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Unification Substitution} *)

(** A tuple containing:

    - the substitution itself
    - delayed constraints
*)

type term = Subst.term
type var = Subst.var

type t

val empty : t
(** Empty *)

val subst : t -> Subst.t
(** Substitution *)

val constr_l : t -> Unif_constr.t list
(** Constraints *)

val has_constr : t -> bool
(** Is there any constraint? *)

val make : Subst.t -> Unif_constr.t list -> t

val of_subst : Subst.t -> t

val map_subst : f:(Subst.t -> Subst.t) -> t -> t

val add_constr : Unif_constr.t -> t -> t

val deref : t -> term Scoped.t -> term Scoped.t

val bind : t -> var Scoped.t -> term Scoped.t -> t

include Interfaces.HASH with type t := t
include Interfaces.ORD with type t := t
include Interfaces.PRINT with type t := t
