(*
Copyright (c) 2013, Simon Cruanes
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  Redistributions in binary
form must reproduce the above copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(** {1 Generic term indexing} *)

type 'a scoped = 'a Substs.scoped

(** {2 Leaf} *)

(** A leaf maps terms to a set of elements *)

module type LEAF = sig
  type t
  type elt

  module S : Set.S with type elt = elt

  val empty : t
  val add : t -> Term.t -> elt -> t
  val remove : t -> Term.t -> elt -> t
  val is_empty : t -> bool
  val iter : t -> (Term.t -> S.t -> unit) -> unit
  val fold : t -> ('a -> Term.t -> S.t -> 'a) -> 'a -> 'a
  val size : t -> int

  val fold_unify : t scoped -> Term.t scoped -> 'a ->
                    ('a -> Term.t -> elt -> Substs.t -> 'a) -> 'a
    (** Unify the given term with indexed terms *)

  val fold_match: t scoped -> Term.t scoped -> 'a ->
                  ('a -> Term.t -> elt -> Substs.t -> 'a) -> 'a
    (** Match the indexed terms against the given query term *)

  val fold_matched: t scoped -> Term.t scoped -> 'a ->
                    ('a -> Term.t -> elt -> Substs.t -> 'a) -> 'a
    (** Match the query term against the indexed terms *)
end

module MakeLeaf(X : Set.OrderedType) : LEAF with type elt = X.t

(** {2 Term index} *)

module type TERM_IDX = sig
  type t
  type elt

  module Leaf : LEAF with type elt = elt

  val name : string

  val empty : t

  val is_empty : t -> bool

  val size : t -> int

  val add : t -> Term.t -> elt -> t

  val remove : t -> Term.t -> elt -> t

  val iter : t -> (Term.t -> Leaf.S.t -> unit) -> unit

  val fold : t -> ('a -> Term.t -> Leaf.S.t -> 'a) -> 'a -> 'a

  val retrieve_unifiables : t scoped -> Term.t scoped -> 'a ->
                            ('a -> Term.t -> elt -> Substs.t -> 'a) -> 'a

  val retrieve_generalizations : t scoped -> Term.t scoped -> 'a ->
                                ('a -> Term.t -> elt -> Substs.t -> 'a) -> 'a

  val retrieve_specializations : t scoped -> Term.t scoped -> 'a ->
                                 ('a -> Term.t -> elt -> Substs.t -> 'a) -> 'a

  val to_dot : (Buffer.t -> elt -> unit) -> Buffer.t -> t -> unit
    (** print oneself in DOT into the given file *)
end

(** {2 Subsumption Index} *)

module type CLAUSE = sig
  type t

  val cmp : t -> t -> int
    (** Compare two clauses *)

  val iter : t -> (Term.t -> Term.t -> bool -> unit) -> unit
    (** Iterate on literals of the clause *)
end

(** A subsumption index (non perfect!) *)

module type SUBSUMPTION_IDX = sig
  type t

  module C : CLAUSE

  val name : string

  val empty : t
    (** Empty index *)

  val add : t -> C.t -> t
    (** Index the clause *)

  val add_seq : t -> C.t Sequence.t -> t

  val remove : t -> C.t -> t
    (** Un-index the clause *)

  val remove_seq : t -> C.t Sequence.t -> t

  val retrieve_subsuming : t -> C.t -> 'a -> ('a -> C.t -> 'a) -> 'a
    (** Fold on a set of indexed candidate clauses, that may subsume
        the given clause. *)

  val retrieve_subsumed : t -> C.t -> 'a -> ('a -> C.t -> 'a) -> 'a
    (** Fold on a set of indexed candidate clauses, that may be subsumed by
        the given clause *)
end

(** {2 Specialized rewriting index} *)

module type EQUATION = sig
  type t

  val equal : t -> t -> bool

  val extract : t -> (Term.t * Term.t * bool)
    (** Obtain a representation of the (in)equation. The sign indicates
        whether it is an equation [l = r] (if true) or an inequation
        [l != r] (if false) *)

  val priority : t -> int
    (** How "useful" this equation is. Can be safely ignored by
        always returning the same number. *)
end

module type UNIT_IDX = sig
  type t

  module E : EQUATION
    (** Module that describes indexed equations *)

  val empty : t

  val is_empty : t -> bool
  
  val add : t -> E.t -> t
    (** Index the given (in)equation *)

  val remove : t -> E.t -> t

  val size : t -> int
    (** Number of indexed (in)equations *)

  val iter : t -> (Term.t -> E.t -> unit) -> unit
    (** Iterate on indexed equations *)

  val retrieve : sign:bool -> t scoped -> Term.t scoped -> 'a ->
                 ('a -> Term.t -> Term.t -> E.t -> Substs.t -> 'a) ->
                 'a
      (** [retrieve ~sign (idx,si) (t,st) acc] folds on
          (in)equations l ?= r of given [sign] and substitutions [subst],
          such that subst(l, si) = t.
          It therefore finds generalizations of the query term. *)

  val to_dot : Buffer.t -> t -> unit
    (** print the index in the DOT format *)
end

