(*
Zipperposition: a functional superposition prover for prototyping
Copyright (C) 2012 Simon Cruanes

This is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 USA.
*)

(** {2 Representation of patterns: higher-order terms} *)

open Symbols
open Types

module T = Terms
module S = FoSubst
module Utils = FoUtils
module Lits = Literals

(** The datalog provers reasons over first-order formulas. However, to make
    those formulas signature-independent, we curryfy them and abstract their
    symbols into lambda-bound variables.

    This way, the pattern for "f(X,Y)=f(Y,X)"
    is "\F. ((= @ ((F @ x) @ y)) @ ((F @ y) @ x))" *)

type pattern = term * varlist
  (** A pattern is a curryfied formula, along with a list of variables
      whose order matters. *)

let eq_pattern (t1,v1) (t2, v2) =
  t1 == t2 &&
    try List.for_all2 (==) v1 v2 with Invalid_argument _ -> false

let hash_pattern (t,vars) =
  let h = T.hash_term t in
  Hash.hash_list T.hash_term h vars

let pp_pattern formatter (p:pattern) =
  Format.fprintf formatter "@[<h>(%a)[%a]@]"
    !T.pp_term#pp (fst p) (Utils.pp_list !T.pp_term#pp) (snd p)

let pattern_to_json (p : pattern) : json =
  `Assoc [
    "term", T.to_json (fst p);
    "vars", `List (List.map T.to_json (snd p))]

let pattern_of_json (json : json) : pattern = match json with
  | `Assoc ["term", t; "vars", `List vars]
  | `Assoc ["vars", `List vars; "term", t] ->
    let t = T.of_json t
    and vars = List.map T.of_json vars in
    (t, vars)
  | _ -> raise (Json.Util.Type_error ("expected pattern", json))

type atom =
  | MString of string     (** Just a string *)
  | MPattern of pattern   (** A pattern, ie a signature-independent formula *)
  | MTerm of term         (** A ground term (constant...) *)
  (** A Datalog atom, in which we may want to fit any structure we want *)

let equal_atom a1 a2 = match a1, a2 with
  | MString s1, MString s2 -> s1 = s2
  | MPattern p1, MPattern p2 -> eq_pattern p1 p2
  | MTerm t1, MTerm t2 -> t1 == t2
  | _ -> false

let hash_atom = function
  | MString s -> Hash.hash_string s
  | MPattern p -> hash_pattern p
  | MTerm t -> T.hash_term t

let pp_atom formatter a = match a with
  | MString s -> Format.pp_print_string formatter s
  | MPattern p -> pp_pattern formatter p
  | MTerm t -> T.pp_term_debug#pp formatter t

let atom_to_json a = failwith "todo: Pattern.atom_to_json"

let atom_of_json json = failwith "todo: Pattern.atom_of_json"

(** The Datalog prover that reasons over atoms. *)
module Logic = Datalog.Logic.Make(struct
  type t = atom
  let equal = equal_atom
  let hash = hash_atom
  let to_string a = Utils.sprintf "%a" pp_atom a
  let of_string s = atom_of_json s  (* XXX should not happen *)
end)

type lemma =
  [ `Lemma of (pattern * varlist) * ((pattern * varlist) list) ]
  (** A lemma is the implication of a pattern by other patterns,
      but with some variable renamings to correlate the
      bindings of the distinct patterns. For instance,
      (F(x,y)=x, [F], [Mult]) may be implied by
      (F(y,x)=y, [F], [MyMult]) and
      (F(x,y)=G(y,x), [F,G], [Mult,MyMult]). *)

type theory =
  [ `Theory of string * varlist * ((pattern * varlist) list) ]
  (** A theory, like a lemma, needs to correlate the variables
      in several patterns via renaming. It outputs an assertion
      about the theory being present for some symbols. *)

type gnd_convergent =
  [ `GndConvergent of gnd_convergent_spec ]
and gnd_convergent_spec = {
  gc_vars : varlist;
  gc_ord : string;
  gc_prec : varlist;
  gc_eqns : pattern list;
} (** Abstract equations that form a ground convergent rewriting system
      when instantiated. They contain free variables, listed in gc_vars,
      such that replacing variables by symbols yields first-order equations.
      The order of variables matter.
      gc_ord and gc_prec, once instantiated, give a constraint on the ordering
      that must be satisfied for the system to be a decision procedure. *)

type item = [lemma | theory | gnd_convergent]
  (** Any meta-object *)

(* TODO *)
let pp_item formatter (item : [< item]) = match item with
  | `Lemma l -> ()
  | `Theory _ -> ()
  | `GndConvergent _ -> ()

(* TODO *)
let item_to_json (item : [< item]) = failwith "todo: Pattern.item_to_json"

(* TODO *)
let item_of_json json : [> item] = failwith "todo: Pattern.item_of_json"

(** {2 Conversion pattern <-> clause, and matching *)

(** Find constant/function symbols in the term *)
let find_symbols t =
  (* traverse term *)
  let rec search set t = match t.term with
  | Var _ | BoundVar _ -> set
  | Bind (s, t') -> search set t'
  | Node (s, [a;b]) when s == at_symbol ->
    search (search set a) b
  | Node (s, []) when not (SMap.mem s base_signature) ->
    T.TSet.add t set  (* found symbol *)
  | Node _ -> assert false
  in search T.TSet.empty t

(** Abstracts the clause out *)
let abstract_clause lits : pattern =
  let t = Lits.term_of_lits lits in
  let t = T.curry t in
  (* now replace symbols by variables *)
  let set = find_symbols t in
  let offset = T.max_var (T.vars t) + 1 in
  (* list of symbol,variable to replace the symbol *)
  let vars = Sequence.to_list
    (Sequence.mapi
      (fun i t' -> t', T.mk_var (i+offset) t'.sort)
      (T.TSet.to_seq set)) in
  let t = List.fold_left
    (fun t (symb,var) -> T.replace t ~old:symb ~by:var)
    t vars in
  let vars = List.map snd vars in
  let p = t, vars in
  Utils.debug 2 (lazy (Utils.sprintf "%% @[<h>%a@] abstracted into @[<h>%a@]"
                Lits.pp_lits lits pp_pattern p));
  p

(** number of arguments that have to be provided
    to instantiate the pattern *)
let arity (p : pattern)  = List.length (snd p)

(** This applies the pattern to the given arguments, beta-reduces,
    and uncurry the term back. It will fail if the result is not
    first-order. *)
let instantiate ~ctx (p : pattern) terms =
  assert (List.length terms = arity p);
  let t, vars = p in
  let offset = T.max_var (T.vars t) + 1 in
  (* build the substitution that replaces variables by the given terms *)
  let subst = List.fold_left2
    (fun subst v t' -> S.bind subst (v,0) (t',offset))
    S.id_subst vars terms in
  let t = S.apply_subst ~recursive:true subst (t,0) in
  if T.is_fo t
    then T.uncurry t
    else failwith "non-FO pattern instantiation"

(** [matching p lits] attempts to match the literals against the pattern.
    It yields a list of solutions, each solution [s1,...,sn] satisfying
    [instantiate p [s1,...,sn] =_AC c] modulo associativity and commutativity
    of "or" and "=". *)
let matching p lits = []  (* TODO *)