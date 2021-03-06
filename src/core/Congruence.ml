
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Simple and Lightweight Congruence and order} *)

module type S = Congruence_intf.S

(** The graph used for the congruence *)

module type TERM = sig
  type t

  val equal : t -> t -> bool

  val hash : t -> int

  val subterms : t -> t list
  (** Subterms of the term (possibly empty list) *)

  val update_subterms : t -> t list -> t
  (** Replace immediate subterms by the given list.
      This is used to test for equality *)
end

module Make(T : TERM) = struct
  type term = T.t

  (** Definition of the congruence closure graph nodes *)

  type node = {
    term : term;
    mutable subnodes : node array;  (* subnodes *)
    mutable lower : node list; (* only for representative *)
    mutable next : node;  (* union-find representative *)
    mutable waiters : (int * int * node) list
    (* (arity,position, waiter) list, only for representative *)
  } (** node of the graph *)

  module H = Hashtbl.Make(struct
      type t = term
      let equal = T.equal
      let hash = T.hash
    end)

  type t = {
    tbl : node H.t; (* table of nodes *)
    stack : (unit -> unit) CCVector.vector; (* backtrack stack. *)
  }

  let create ?(size=64) () =
    let cc = {
      tbl = H.create size;
      stack = CCVector.create ();
    } in
    cc

  let clear h =
    H.clear h.tbl;
    CCVector.clear h.stack;
    ()

  type level = int

  let save h = CCVector.length h.stack

  let restore h lev =
    while CCVector.length h.stack > lev do
      let f = CCVector.pop_exn h.stack in
      f ();
    done

  (* push an action on the undo stack *)
  let _push_undo cc f = CCVector.push cc.stack f

  (* update [node.next] to be [next] *)
  let _set_next cc node next =
    let old_next = node.next in
    _push_undo cc (fun () -> node.next <- old_next);
    node.next <- next;
    ()

  (* update [node.lower] to be [lower] *)
  let _set_lower cc node lower =
    let old_lower = node.lower in
    _push_undo cc (fun () -> node.lower <- old_lower);
    node.lower <- lower;
    ()

  (* update [node.waiters] to be [waiters] *)
  let _set_waiters cc node waiters =
    let old_waiters = node.waiters in
    _push_undo cc (fun () -> node.waiters <- old_waiters);
    node.waiters <- waiters;
    ()

  (* add a node to the table *)
  let _add_node cc t node =
    _push_undo cc (fun () -> H.remove cc.tbl t);
    H.add cc.tbl t node;
    ()

  (* find representative *)
  let rec _find cc node =
    if node.next == node
    then node  (* root *)
    else begin
      let root = _find cc node.next in
      (* path compression *)
      if root != node.next then _set_next cc node root;
      root
    end

  (* are two nodes, with their subterm lists, congruent? To
      check this, we compute the representative of subnodes
      and we check whether updated subterms are equal *)
  let _are_congruent cc n1 n2 =
    assert (Array.length n1.subnodes = Array.length n2.subnodes);
    let l1' = List.map (fun n -> (_find cc n).term) (Array.to_list n1.subnodes) in
    let l2' = List.map (fun n -> (_find cc n).term) (Array.to_list n2.subnodes) in
    try
      let t1 = T.update_subterms n1.term l1' in
      let t2 = T.update_subterms n2.term l2' in
      T.equal t1 t2
    with Type.ApplyError _ ->
      false

  (* check whether all congruences of [node] are computed, by
      looking at equivalence classes of [subnodes] *)
  let rec _check_congruence cc node =
    let arity = Array.length node.subnodes in
    for i = 0 to arity - 1 do
      let subnode = _find cc node.subnodes.(i) in
      List.iter
        (fun (arity', i', node') ->
           if i = i' && arity = arity' && _are_congruent cc node node'
           then _merge cc node node')
        subnode.waiters
    done

  (* merge n1 and n2 equivalence classes *)
  and _merge cc n1 n2 =
    (* get representatives *)
    let n1 = _find cc n1 in
    let n2 = _find cc n2 in
    if n1 != n2 then begin
      _set_next cc n1 n2;
      (* n1 now points to n2, put every class information in n2 *)
      _set_lower cc n2 (List.rev_append n1.lower n2.lower);
      _set_lower cc n1 [];
      let left, right = n1.waiters, n2.waiters in
      _set_waiters cc n2 (List.rev_append n1.waiters n2.waiters);
      _set_waiters cc n1 [];
      (* check congruence of waiters of n1 and n2 *)
      List.iter
        (fun (arity1, i1, n1') ->
           List.iter
             (fun (arity2, i2, n2') ->
                if arity1 = arity2 && i1 = i2 && _are_congruent cc n1' n2'
                then _merge cc n1' n2')
             right)
        left
    end

  (* obtain the node for this term. If not present, create it *)
  let rec _get cc t =
    try H.find cc.tbl t
    with Not_found ->
      let rec node = {
        term = t;
        subnodes = [| |];  (* updated later *)
        lower = [];
        next = node;
        waiters = [];
      } in
      _add_node cc t node;
      (* register the node to its subterms *)
      let subterms = T.subterms t in
      let arity = List.length subterms in
      (* obtain subnodes' current equiv classes (no need to undo) *)
      let subnodes = List.map (_get cc) subterms in
      let subnodes = Array.of_list subnodes in
      node.subnodes <- subnodes;
      (* possibly, merge with other nodes *)
      _check_congruence cc node;
      (* register to future merges of subnodes *)
      Array.iteri
        (fun i subnode ->
           let subnode = _find cc subnode in
           _set_waiters cc subnode ((arity, i, node) :: subnode.waiters))
        subnodes;
      (* return node *)
      node

  let find cc t =
    let n = _get cc t in
    let n = _find cc n in
    n.term

  let iter cc f =
    H.iter
      (fun mem node ->
         let repr = (_find cc node).term in
         f ~mem ~repr)
      cc.tbl

  let _iter_roots_node cc f =
    H.iter
      (fun _ node ->
         if node == node.next then f node)
      cc.tbl

  let iter_roots cc f = _iter_roots_node cc (fun node -> f node.term)

  let mk_eq cc t1 t2 =
    let n1 = _get cc t1 in
    let n2 = _get cc t2 in
    _merge cc n1 n2

  let mk_less cc t1 t2 =
    let n1 = _find cc (_get cc t1) in
    let n2 = _find cc (_get cc t2) in
    if not (List.memq n1 n2.lower)
    then _set_lower cc n2 (n1 :: n2.lower);
    ()

  let is_eq cc t1 t2 =
    let n1 = _find cc (_get cc t1) in
    let n2 = _find cc (_get cc t2) in
    n1 == n2

  let is_less cc t1 t2 =
    let n1 = _find cc (_get cc t1) in
    let n2 = _find cc (_get cc t2) in
    (* follow [.lower] links, from [current], until we find [target].
        [explored] is used to break cycles, if any *)
    let rec search explored target current =
      if List.memq current explored
      then false
      else if target == current
      then true
      else
        let explored = current :: explored in
        List.exists
          (fun cur' -> search explored target (_find cc cur'))
          current.lower
    in
    (* search. target=n1, current=n2 *)
    search [] n1 n2

  let cycles cc =
    try
      let explored = H.create 7 in
      (* starting from each root, explore "less" graph in DFS *)
      _iter_roots_node cc
        (fun root ->
           H.clear explored;
           let s = Stack.create () in
           (* initial step *)
           H.add explored root.term ();
           List.iter (fun node' -> Stack.push (node', [root]) s) root.lower;
           (* explore *)
           while not (Stack.is_empty s) do
             let node, path = Stack.pop s in
             if not (H.mem explored node.term) then begin
               H.add explored node.term ();
               (* explore children *)
               List.iter
                 (fun node' ->
                    if List.memq node' path
                    then raise Exit (* found cycle *)
                    else Stack.push (node', node::path) s)
                 node.lower
             end;
           done);
      false
    with Exit ->
      true
end

module FO = Make(struct
    module T = FOTerm

    type t = T.t
    let equal = T.equal
    let hash = T.hash

    let subterms t = match T.Classic.view t with
      | T.Classic.App (_, l) -> l
      | _ -> []

    let update_subterms t l = match T.view t, l with
      | T.App (hd, l), l' when List.length l = List.length l' ->
        T.app hd l'
      | _, [] -> t
      | _ -> assert false
  end)
