
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Unification Constraint} *)

(** A constraint delayed because unification for this pair of terms is
      not syntactic *)
type t = InnerTerm.t * InnerTerm.t

(** Apply a substitution to a delayed constraint *)
val apply_subst :
  renaming:Subst.Renaming.t ->
  Subst.t ->
  Scoped.scope * Scoped.scope ->
  t ->
  t

(** Apply a substitution to delayed constraints *)
val apply_subst_l :
  renaming:Subst.Renaming.t ->
  Subst.t ->
  Scoped.scope * Scoped.scope ->
  t list ->
  t list

include Interfaces.HASH with type t := t
include Interfaces.ORD with type t := t
include Interfaces.PRINT with type t := t

