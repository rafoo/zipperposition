
(* This file is free software, part of Logtk. See file "license" for more details. *)

(** {1 Reduction to CNF and simplifications} *)

type term = TypedSTerm.t
type form = TypedSTerm.t
type type_ = TypedSTerm.t
type lit = term SLiteral.t

(** See "computing small normal forms", in the handbook of automated reasoning.
    All transformations are made on curried terms and formulas. *)

exception Error of string

exception NotCNF of form

val miniscope : ?distribute_exists:bool -> form -> form
(** Apply miniscoping transformation to the term.
    @param distribute_exists see whether ?X:(p(X)|q(X)) should be
      transformed into (?X: p(X) | ?X: q(X)). Default: [false] *)

(** Options are used to tune the behavior of the CNF conversion. *)
type options =
  | DistributeExists
  (** if enabled, will distribute existential quantifiers over
      disjunctions. This can make skolem symbols smaller (smaller arity) but
      introduce more of them. *)

  | DisableRenaming
  (** disables formula renaming. Can re-introduce the worst-case
      exponential behavior of CNF. *)

  | InitialProcessing of (form -> form)
  (** any processing, at the beginning, before CNF starts  *)

  | PostNNF of (form -> form)
  (** any processing that keeps negation at leaves,
      just after reduction to NNF. Its output
      must not break the NNF form (negation at root only). *)

  | PostSkolem of (form -> form)
  (** transformation applied just after skolemization. It must not
      break skolemization nor NNF (no quantifier, no non-leaf negation). *)

type clause = lit list
(** Basic clause representation, as list of literals *)

val clause_to_fo :
  ?ctx:FOTerm.Conv.ctx ->
  clause ->
  FOTerm.t SLiteral.t list

type f_statement = (term, term, type_) Statement.t
(** A statement before CNF *)

type c_statement = (clause, term, type_) Statement.t
(** A statement after CNF *)

val pp_f_statement : f_statement CCFormat.printer
val pp_c_statement : c_statement CCFormat.printer
val pp_fo_c_statement : (FOTerm.t SLiteral.t list, FOTerm.t, Type.t) Statement.t CCFormat.printer


val is_clause : form -> bool
val is_cnf : form -> bool

(** {2 Main Interface} *)

val cnf_of :
  ?opts:options list ->
  ?ctx:Skolem.ctx ->
  f_statement ->
  c_statement CCVector.ro_vector
(** Transform the clause into proper CNF; returns a list of statements,
    including type declarations for new Skolem symbols or formulas proxys.
    Options are used to tune the behavior. *)

val cnf_of_seq :
  ?opts:options list ->
  ?ctx:Skolem.ctx ->
  f_statement Sequence.t ->
  c_statement CCVector.ro_vector

val type_declarations :
  c_statement Sequence.t ->
  type_ ID.Map.t
(** Compute the types declared in the statement sequence *)

(** {2 Conversions} *)

val convert :
  c_statement Sequence.t ->
  Statement.clause_t CCVector.ro_vector
(** Converts statements based on {!TypedSTerm} into statements
    based on {!FOTerm} and {!Type} *)
