
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Perfect Discrimination Tree} *)

module ST = InnerTerm
module T = FOTerm
module S = Substs

let prof_dtree_retrieve = Util.mk_profiler "dtree_retrieve"

(** {2 Term traversal}
Term traversal in prefix order. This is akin to lazy transformation
to a flatterm. *)

type character =
  | Symbol of ID.t
  | BoundVariable of int
  | Variable of Type.t HVar.t
  | NonFO

type iterator = {
  cur_char : character;
  cur_term : T.t;
  stack : T.t list list; (* skip: drop head, next: first of head *)
}

let char_to_int_ = function
  | Symbol _ -> 0
  | BoundVariable _ -> 1
  | Variable _ -> 2
  | NonFO -> 3

let compare_char c1 c2 =
  (* compare variables by index *)
  let compare_vars v1 v2 =
    let c = HVar.compare v1 v2 in
    if c=0 then Type.compare (HVar.ty v1) (HVar.ty v2) else c
  in
  match c1, c2 with
  | Symbol s1, Symbol s2 -> ID.compare s1 s2
  | BoundVariable i, BoundVariable j -> i - j
  | Variable v1, Variable v2 -> compare_vars v1 v2
  | NonFO, NonFO -> 0
  | _ -> char_to_int_ c1 - char_to_int_ c2

let eq_char c1 c2 = compare_char c1 c2 = 0

(** first symbol of t, or variable *)
let term_to_char t =
  match T.Classic.view t with
  | T.Classic.Var v -> Variable v
  | T.Classic.DB i -> BoundVariable i
  | T.Classic.App (f, _) -> Symbol f
  | T.Classic.AppBuiltin _
  | T.Classic.NonFO -> NonFO

let pp_char out = function
  | Variable v -> HVar.pp out v
  | BoundVariable i -> Format.fprintf out "Y%d" i
  | Symbol f -> ID.pp out f
  | NonFO -> CCFormat.string out "<nonfo>"

let open_term ~stack t =
  let cur_char = term_to_char t in
  match T.view t with
  | T.Var _
  | T.DB _
  | T.AppBuiltin _
  | T.Const _ ->
      Some {cur_char; cur_term=t; stack=[]::stack;}
  | T.App (_, l) ->
      Some {cur_char; cur_term=t; stack=l::stack;}

let rec next_rec stack = match stack with
  | [] -> None
  | []::stack' -> next_rec stack'
  | (t::next')::stack' ->
      open_term ~stack:(next'::stack') t

let skip iter = match iter.stack with
  | [] -> None
  | _next::stack' -> next_rec stack'
and next iter = next_rec iter.stack

(* Iterate on a term *)
let iterate term = open_term ~stack:[] term

(* convert term to list of var/symbol *)
let to_list t =
  let rec getnext acc iter =
    let acc' = iter.cur_char :: acc in
    match next iter with
    | None -> List.rev acc'
    | Some iter' ->
        getnext acc' iter'
  in
  match iterate t with
  | None -> assert false
  | Some i ->
    let l = getnext [] i in
    Util.debugf 5 "dtree.to_list %a = [%a]"
      (fun k->k T.pp t (Util.pp_list pp_char) l);
    l

module CharMap = Map.Make(struct
  type t = character
  let compare = compare_char
end)

(** {2 Discrimination tree} *)

module Make(E : Index.EQUATION) = struct
  module E = E

  type rhs = E.rhs

  type trie =
    | TrieNode of trie CharMap.t       (** map atom -> trie *)
    | TrieLeaf of (T.t * E.t * int) list
      (** leaf with (term, value, priority) list *)

  let empty_trie n = match n with
    | TrieNode m when CharMap.is_empty m -> true
    | TrieLeaf [] -> true
    | _ -> false

  (** get/add/remove the leaf for the given flatterm. The
      continuation k takes the leaf, and returns a leaf option
      that replaces the old leaf.
      This function returns the new trie. *)
  let goto_leaf trie t k =
    (* the root of the tree *)
    let root = trie in
    (* function to go to the given leaf, building it if needed *)
    let rec goto trie t rebuild =
      match trie, t with
      | (TrieLeaf l) as leaf, [] -> (* found leaf *)
        begin match k l with
        | new_leaf when leaf == new_leaf -> root  (* no change, return same tree *)
        | new_leaf -> rebuild new_leaf           (* replace by new leaf *)
        end
      | TrieNode m, c::t' ->
        begin try  (* insert in subtrie *)
          let subtrie = CharMap.find c m in
          let rebuild' subtrie = match subtrie with
            | _ when empty_trie subtrie -> rebuild (TrieNode (CharMap.remove c m))
            | _ -> rebuild (TrieNode (CharMap.add c subtrie m))
          in
          goto subtrie t' rebuild'
        with Not_found -> (* no subtrie found *)
          let subtrie = if t' = [] then TrieLeaf [] else TrieNode CharMap.empty
          and rebuild' subtrie = match subtrie with
            | _ when empty_trie subtrie -> root  (* same tree *)
            | _ -> rebuild (TrieNode (CharMap.add c subtrie m))
          in
          goto subtrie t' rebuild'
        end
      | TrieNode _, [] -> assert false (* ill-formed term *)
      | TrieLeaf _, _ -> assert false  (* wrong arity *)
  in
  goto trie t (fun t -> t)

  type t = trie

  let empty () = TrieNode CharMap.empty

  let is_empty = empty_trie

  let add dt eqn =
    let t, _, _ = E.extract eqn in
    let priority = E.priority eqn in
    let chars = to_list t in
    let k l =
      let l' = (t, eqn, priority)::l in
      TrieLeaf (List.stable_sort (fun (_, _, p1) (_, _, p2) -> p1 - p2) l')
      (* TODO: linear-time insertion into a sorted list *)
    in
    let tree = goto_leaf dt chars k in
    tree

  let remove dt eqn =
    let t, _, _ = E.extract eqn in
    let chars = to_list t in
    let k l =
      (* remove tuples that match *)
      let l' = List.filter
        (fun (t', eqn', _) -> t' != t || E.compare eqn eqn' <> 0) l
      in
      TrieLeaf l'
    in
    let tree = goto_leaf dt chars k in
    tree

  let add_seq dt seq =
    Sequence.fold add dt seq

  let remove_seq dt seq =
    Sequence.fold remove dt seq

  let retrieve ?(subst=S.empty) ~sign dt t k =
    Util.enter_prof prof_dtree_retrieve;
    (* recursive traversal of the trie, following paths compatible with t *)
    let rec traverse trie iter subst =
      match trie, iter with
      | TrieLeaf l, None ->  (* yield all equations, they all match *)
        List.iter
          (fun (_, eqn, _) ->
            let l, r, sign' = E.extract eqn in
            if sign = sign' then k (l, r, eqn, subst))
          l
      | TrieNode m, Some i ->
        (* "lazy" transformation to flatterm *)
        let t_pos = i.cur_term in
        let c1 = i.cur_char in
        CharMap.iter
          (fun c2 subtrie ->
            (* explore branch that has the same symbol, if any *)
            if eq_char c2 c1 && not (T.is_var t_pos)
              then traverse subtrie (next i) subst;
            match c2 with
            | Variable v2 when S.mem subst (Scoped.set t (v2:>ST.t HVar.t)) ->
              (* already bound, check consistency *)
              let t' = S.FO.find_exn subst (Scoped.set t (v2:>ST.t HVar.t)) in
              if Unif.FO.equal ~subst t t'
              then traverse subtrie (skip i) subst
            | Variable v2 ->
              (* try to bind and continue *)
              begin try
                let subst = Unif.FO.bind subst
                  (Scoped.set dt v2) (Scoped.set t t_pos) in
                traverse subtrie (skip i) subst
              with Unif.Fail -> () (* incompatible binding *)
              end
            | _ -> ())
          m
      | TrieNode _, None
      | TrieLeaf _, Some _ -> ()
    in
    traverse (fst dt) (iterate (fst t)) subst;
    Util.exit_prof prof_dtree_retrieve;
    ()

  (** iterate on all (term -> value) in the tree *)
  let iter dt k =
    let rec iter trie =
      match trie with
      | TrieNode m -> CharMap.iter (fun _ sub_dt -> iter sub_dt) m
      | TrieLeaf l -> List.iter (fun (t, v, _) -> k t v) l
    in iter dt

  let size dt =
    let n = ref 0 in
    iter dt (fun _ _ -> incr n);
    !n

  let to_dot _out _t =
    failwith "DTree.to_dot: not implemented"
end

module Default = Make(Index.BasicEquation)