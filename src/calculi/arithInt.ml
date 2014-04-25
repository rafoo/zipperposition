
(*
Zipperposition: a functional superposition prover for prototyping
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

(** {1 Cancellative Inferences} *)

open Logtk

module T = FOTerm
module Lit = Literal
module Lits = Literals
module S = Substs
module M = Monome
module MF = Monome.Focus
module AL = ArithLit
module ALF = ArithLit.Focus

(* TODO: check maximality of focused terms in literals after substitution
  (t + m1 R m2:  check that not (t < t') for t' in m1 and t' in m2 *)

(* TODO: purification of clauses *)

let stat_arith_sup = Util.mk_stat "arith.superposition"
let stat_arith_cancellation = Util.mk_stat "arith.arith_cancellation"
let stat_arith_eq_factoring = Util.mk_stat "arith.eq_factoring"
let stat_arith_ineq_factoring = Util.mk_stat "arith.ineq_factoring"
let stat_arith_ineq_chaining = Util.mk_stat "arith.ineq_chaining"
let stat_arith_reflexivity_resolution = Util.mk_stat "arith.reflexivity_resolution"
let stat_arith_case_switch = Util.mk_stat "arith.case_switch"
let stat_arith_inner_case_switch = Util.mk_stat "arith.inner_case_switch"
let stat_arith_purify = Util.mk_stat "arith.purify"

let prof_arith_sup = Util.mk_profiler "arith.superposition"
let prof_arith_cancellation = Util.mk_profiler "arith.arith_cancellation"
let prof_arith_eq_factoring = Util.mk_profiler "arith.eq_factoring"
let prof_arith_ineq_factoring = Util.mk_profiler "arith.ineq_factoring"
let prof_arith_ineq_chaining = Util.mk_profiler "arith.ineq_chaining"
let prof_arith_reflexivity_resolution = Util.mk_profiler "arith.reflexivity_resolution"
let prof_arith_case_switch = Util.mk_profiler "arith.case_switch"
let prof_arith_inner_case_switch = Util.mk_profiler "arith.inner_case_switch"
let prof_arith_purify = Util.mk_profiler "arith.purify"

let stat_arith_semantic_tautology = Util.mk_stat "arith.semantic_tauto"
let prof_arith_semantic_tautology = Util.mk_profiler "arith.semantic_tauto"

module type S = sig
  module Env : Env.S
  module C : module type of Env.C
  module PS : module type of Env.ProofState

  val idx_eq : unit -> PS.TermIndex.t   (** both sides of Eq/Ineq *)
  val idx_ineq : unit -> PS.TermIndex.t (** inequations *)
  val idx_div : unit -> PS.TermIndex.t  (** divisibility *)
  val idx_all : unit -> PS.TermIndex.t  (** all root terms under arith lits *)

  (** {3 Equations and Inequations} *)

  val canc_sup_active: Env.binary_inf_rule
    (** cancellative superposition where given clause is active *)

  val canc_sup_passive: Env.binary_inf_rule
    (** cancellative superposition where given clause is passive *)

  val cancellation: Env.unary_inf_rule
    (** cancellation (unifies some terms on both sides of a
        comparison operator) *)

  val canc_equality_factoring: Env.unary_inf_rule
    (** cancellative equality factoring *)

  val canc_ineq_chaining : Env.binary_inf_rule
    (** cancellative inequality chaining *)

  val canc_ineq_factoring : Env.unary_inf_rule
    (** Factoring between two inequation literals *)

  val canc_case_switch : Env.binary_inf_rule
    (** inference rule
            C1 or a <= b     C2 or b <= c
        -------------------------------------
            C1 or C2 or or_{i=a....c} (b = i)
        if a and c are integer linear expressions whose difference is
        a constant. If a > c, then the range a...c is empty and the literal
        is just removed. *)

  val canc_inner_case_switch : Env.unary_inf_rule
    (** inference rule
          C1 or a <= b or b <= c
          ----------------------
              C1 or b!=i
          for each i in [c...a]. See (a <= b or b <= c or C1) as
          the rule  (b < a and c < b) -> C1, then make the head of the rule
          true *)

  val canc_lesseq_to_less : Env.lit_rewrite_rule
    (** Simplification:  a <= b  ----> a < b+1 *)

  (** {3 Divisibility} *)

  val canc_div_chaining : Env.binary_inf_rule
    (** Chain together two divisibility literals, assuming they share the
        same prime *)

  val canc_div_case_switch : Env.simplify_rule
    (** Eliminate negative divisibility literals within a power-of-prime
        quotient of Z:
        not (d^i | m) -----> *)

  val canc_div_prime_decomposition : Env.multi_simpl_rule
    (** Eliminate divisibility literals with a non-power-of-prime
        quotient of Z (for instance  6 | a ---> { 2 | a, 3 | a }) *)

  (** {3 Other} *)

  val is_tautology : C.t -> bool
    (** is the clause a tautology w.r.t linear expressions? *)

  val purify : Env.simplify_rule
    (** Purify clauses by replacing arithmetic expressions occurring
        under terms by variables, and adding constraints *)

  val eliminate_unshielded : Env.multi_simpl_rule
    (** Eliminate unshielded variables using an adaptation of
        Cooper's algorithm *)

  (** {2 Contributions to Env} *)

  val register : unit -> unit
end

let theories = ["arith"]
type scope = S.scope

let _enable_arith = ref false
let _enable_ac = ref false
let _enable_semantic_tauto = ref false

let case_switch_limit = ref 30
let div_case_switch_limit = ref 100

module Make(E : Env.S) : S with module Env = E = struct
  module Env = E
  module Ctx = Env.Ctx
  module C = Env.C
  module PS = Env.ProofState

  let _idx_eq = ref (PS.TermIndex.empty ())
  let _idx_ineq = ref (PS.TermIndex.empty ())
  let _idx_div = ref (PS.TermIndex.empty ())
  let _idx_all = ref (PS.TermIndex.empty ())

  let idx_eq () = !_idx_eq
  let idx_ineq () = !_idx_ineq
  let idx_div () = !_idx_div
  let idx_all () = !_idx_all

  (* apply [f] to some subterms of [c] *)
  let update f c =
    let ord = Ctx.ord () in
    _idx_eq :=
      Lits.fold_terms ~vars:false ~which:`Max ~ord ~subterms:false
      ~eligible:C.Eligible.(filter Lit.is_arith_eqn ** max c)
      (C.lits c) !_idx_eq
      (fun acc t pos ->
        let with_pos = C.WithPos.( {term=t; pos; clause=c} ) in
        f acc t with_pos);
    _idx_ineq :=
      Lits.fold_terms ~vars:false ~which:`Max ~ord ~subterms:false
      ~eligible:C.Eligible.(filter Lit.is_arith_ineq** max c)
      (C.lits c) !_idx_ineq
      (fun acc t pos ->
        let with_pos = C.WithPos.( {term=t; pos; clause=c} ) in
        f acc t with_pos);
    _idx_div :=
      Lits.fold_terms ~vars:false ~which:`Max ~ord ~subterms:false
      ~eligible:C.Eligible.(filter Lit.is_arith_divides ** max c)
      (C.lits c) !_idx_div
      (fun acc t pos ->
        let with_pos = C.WithPos.( {term=t; pos; clause=c} ) in
        f acc t with_pos);
    _idx_all :=
      Lits.fold_terms ~vars:false ~which:`Max ~ord ~subterms:false
      ~eligible:C.Eligible.(filter Lit.is_arith ** max c)
      (C.lits c) !_idx_all
      (fun acc t pos ->
        let with_pos = C.WithPos.( {term=t; pos; clause=c} ) in
        f acc t with_pos);
    ()

  let () =
    Signal.on PS.ActiveSet.on_add_clause
      (fun c ->
        if !_enable_arith then update PS.TermIndex.add c;
        Signal.ContinueListening);
    Signal.on PS.ActiveSet.on_remove_clause
      (fun c ->
        if !_enable_arith then update PS.TermIndex.remove c;
        Signal.ContinueListening);
    ()

  (** {2 Utils} *)


  (* data required for superposition *)
  module SupInfo = struct
    type t = {
      active : C.t;
      active_pos : Position.t;
      active_lit : ArithLit.Focus.t;
      active_scope : scope;
      passive : C.t;
      passive_pos : Position.t;
      passive_lit : ArithLit.Focus.t;
      passive_scope : scope;
      subst : Substs.t;
    }
  end

  (* do cancellative superposition *)
  let _do_canc info acc =
    let open SupInfo in
    let ord = Ctx.ord () in
    let renaming = Ctx.renaming_clear () in
    let subst = info.subst in
    let idx_a, _ = Lits.Pos.cut info.active_pos in
    let idx_p, _ = Lits.Pos.cut info.passive_pos in
    let s_a = info.active_scope and s_p = info.passive_scope in
    let lit_a = ALF.apply_subst ~renaming subst info.active_lit s_a in
    let lit_p = ALF.apply_subst ~renaming subst info.passive_lit s_p in
    Util.debug 5 "arith superposition between %a[%d] and %a[%d] (subst %a)..."
      C.pp info.active s_a C.pp info.passive s_p Substs.pp subst;
    (* check ordering conditions *)
    if C.is_maxlit info.active s_a subst idx_a
    && C.is_maxlit info.passive s_p subst idx_p
    && ALF.is_max ~ord lit_a
    && ALF.is_max ~ord lit_p
    then begin
      (* the active literals *)
      let lit_a, lit_p = ALF.scale lit_a lit_p in
      (* other literals *)
      let lits_a = Util.array_except_idx (C.lits info.active) idx_a in
      let lits_a = Lit.apply_subst_list ~renaming subst lits_a s_a in
      let lits_p = Util.array_except_idx (C.lits info.passive) idx_p in
      let lits_p = Lit.apply_subst_list ~renaming subst lits_p s_p in
      (* new literal: lit_a=[t+m1=m2], lit_p=[t'+m1' R m2'] for some
        relation R. Now let's replace t' by [m2-m1] in lit', ie,
        build m = [m1'-m2'+(m2-m1) R 0]. *)
      let mf_a, m_a = match lit_a with
        | ALF.Left (AL.Equal, mf, m)
        | ALF.Right (AL.Equal, m, mf) -> mf, m
        | _ -> assert false
      in
      let new_lit = match lit_p with
        | ALF.Left (op, mf_p, m_p) ->
            Lit.mk_arith_op op
              (M.sum (MF.rest mf_p) m_a)
              (M.sum m_p (MF.rest mf_a))
        | ALF.Right (op, m_p, mf_p) ->
            Lit.mk_arith_op op
              (M.sum m_p (MF.rest mf_a))
              (M.sum (MF.rest mf_p) m_a)
        | ALF.Div d -> failwith "sup in div: not implemented"  (* FIXME *)
      in
      let all_lits = new_lit :: lits_a @ lits_p in
      (* build clause *)
      let proof cc = Proof.mk_c_inference ~theories
        ~info:[Substs.to_string subst; Util.sprintf "lhs(%a)" MF.pp mf_a]
        ~rule:"canc_sup" cc [C.proof info.active; C.proof info.passive] in
      let new_c = C.create ~parents:[info.active;info.passive] all_lits proof in
      Util.debug 5 "... gives %a" C.pp new_c;
      Util.incr_stat stat_arith_sup;
      new_c :: acc
    end else begin
      Util.debug 5 "... has bad ordering conditions";
      acc
    end

  let canc_sup_active c =
    Util.enter_prof prof_arith_sup;
    let ord = Ctx.ord () in
    let eligible = C.Eligible.(pos ** max c ** filter Lit.is_arith_eq) in
    let sc_a = 0 and sc_p = 1 in
    let res = Lits.fold_arith_terms ~eligible ~which:`Max ~ord (C.lits c) []
      (fun acc t active_lit active_pos ->
        assert (ALF.op active_lit = `Binary AL.Equal);
        Util.debug 5 "active canc. sup. with %a in %a" ALF.pp active_lit C.pp c;
        PS.TermIndex.retrieve_unifiables !_idx_all sc_p t sc_a acc
          (fun acc t' with_pos subst ->
            let passive = with_pos.C.WithPos.clause in
            let passive_pos = with_pos.C.WithPos.pos in
            let passive_lit = Lits.View.get_arith_exn (C.lits passive) passive_pos in
            Util.debug 5 "  possible match: %a in %a" ALF.pp passive_lit C.pp passive;
            (* now to unify active_lit and passive_lit further *)
            ALF.unify ~subst active_lit sc_a passive_lit sc_p
            |> Sequence.fold
              (fun acc (active_lit, passive_lit, subst) ->
                let info = SupInfo.({
                  active=c; active_pos; active_lit; active_scope=sc_a;
                  passive; passive_pos; passive_lit; passive_scope=sc_p; subst;
                }) in
                _do_canc info acc
              ) acc
          )
      )
    in
    Util.exit_prof prof_arith_sup;
    res

  let canc_sup_passive c =
    Util.enter_prof prof_arith_sup;
    let ord = Ctx.ord () in
    let eligible = C.Eligible.arith in
    let sc_a = 0 and sc_p = 1 in
    let res = Lits.fold_arith_terms ~eligible ~which:`Max ~ord (C.lits c) []
      (fun acc t passive_lit passive_pos ->
        Util.debug 5 "passive canc. sup. with %a in %a" ALF.pp passive_lit C.pp c;
        PS.TermIndex.retrieve_unifiables !_idx_eq sc_a t sc_p acc
          (fun acc t' with_pos subst ->
            let active = with_pos.C.WithPos.clause in
            let active_pos = with_pos.C.WithPos.pos in
            let active_lit = Lits.View.get_arith_exn (C.lits active) active_pos in
            (* must have an equation as active lit *)
            match ALF.op active_lit with
            | `Binary AL.Equal ->
              Util.debug 5 "  possible match: %a in %a" ALF.pp passive_lit C.pp c;
              (* unify literals further *)
              ALF.unify ~subst active_lit sc_a passive_lit sc_p
              |> Sequence.fold
                (fun acc (active_lit, passive_lit, subst) ->
                  let info = SupInfo.({
                    active; active_pos; active_lit; active_scope=sc_a;
                    passive=c; passive_pos; passive_lit; passive_scope=sc_p; subst;
                  }) in
                  _do_canc info acc
                ) acc
            | _ -> acc
          )
      )
    in
    Util.exit_prof prof_arith_sup;
    res

  let cancellation c =
    Util.enter_prof prof_arith_cancellation;
    let ord = Ctx.ord () in
    let eligible = C.Eligible.(max c ** arith) in
    let res = Lits.fold_arith ~eligible (C.lits c) []
      (fun acc a_lit pos ->
        let max_terms = AL.max_terms ~ord a_lit in
        let idx = Lits.Pos.idx pos in
        (* cancellation depends on what the literal looks like *)
        match a_lit with
        | AL.Binary (op, m1, m2) ->
            (* try to unify terms in [m1] and [m2] *)
            MF.unify_mm m1 0 m2 0
            |> Sequence.fold
              (fun acc (mf1, mf2, subst) ->
                let renaming = Ctx.renaming_clear () in
                let mf1' = MF.apply_subst ~renaming subst mf1 0 in
                let mf2' = MF.apply_subst ~renaming subst mf2 0 in
                if C.is_maxlit c 0 subst ~idx
                && MF.is_max ~ord mf1' && MF.is_max ~ord mf2'
                then begin
                  (* do the inference *)
                  let lits' = Util.array_except_idx (C.lits c) idx in
                  let lits' = Lit.apply_subst_list ~renaming subst lits' 0 in
                  let new_lit = Lit.mk_arith_op op (MF.rest mf1') (MF.rest mf2') in
                  let all_lits = new_lit :: lits' in
                  let proof cc = Proof.mk_c_inference
                    ~info:[Substs.to_string subst] ~theories
                    ~rule:"cancellation" cc [C.proof c] in
                  let new_c = C.create ~parents:[c] all_lits proof in
                  Util.debug 3 "cancellation of %a (with %a) into %a" C.pp c
                    Substs.pp subst C.pp new_c;
                  Util.incr_stat stat_arith_cancellation;
                  new_c :: acc
                end else
                  acc
              ) acc
        | AL.Divides d -> acc  (* TODO *)
      )
    in
    Util.exit_prof prof_arith_cancellation;
    res

  let canc_equality_factoring c =
    Util.enter_prof prof_arith_eq_factoring;
    let ord = Ctx.ord () in
    let eligible = C.Eligible.(max c ** filter Lit.is_arith_eq) in
    let res = Lits.fold_arith_terms ~which:`Max ~eligible ~ord (C.lits c) []
      (fun acc t1 lit1 pos1 ->
        assert(ALF.op lit1 = `Binary AL.Equal);
        let idx1 = Lits.Pos.idx pos1 in
        (* lit1 is the factored literal *)
        Lits.fold_arith_terms ~which:`Max ~ord
          ~eligible:C.Eligible.(filter Lit.is_arith_eq) (C.lits c) acc
          (fun acc t2 lit2 pos2 ->
            assert(ALF.op lit2 = `Binary AL.Equal);
            let idx2 = Lits.Pos.idx pos2 in
            let mf1 = ALF.focused_monome lit1
            and mf2 = ALF.focused_monome lit2 in
            try
              if idx1 = idx2 then raise Unif.Fail;  (* exit *)
              let subst = Unif.FO.unification t1 0 t2 0 in
              Util.debug 5
                "arith canc. eq. factoring: possible match in %a (at %d, %d)"
                C.pp c idx1 idx2;
              MF.unify_ff ~subst mf1 0 mf2 0
              |> Sequence.fold
                (fun acc (_, _, subst) ->
                  let renaming = Ctx.renaming_clear () in
                  let lit1' = ALF.apply_subst ~renaming subst lit1 0 in
                  let lit2' = ALF.apply_subst ~renaming subst lit2 0 in
                  if C.is_maxlit c 0 subst ~idx:idx1
                  && ALF.is_max ~ord lit1'
                  && ALF.is_max ~ord lit2'
                  then begin
                    (*  lit1 is   a.t + l1 = l2,
                        lit2 is   a'.t + l1' = l2',
                        so we scale them, and replace lit1 with
                        a'.l1 + a.l2' != a'.l2 + a.l1' *)
                    let lit1', lit2' = ALF.scale lit1' lit2' in
                    let m1 = ALF.opposite_monome_exn lit1'
                    and mf1 = ALF.focused_monome lit1'
                    and m2 = ALF.opposite_monome_exn lit2'
                    and mf2 = ALF.focused_monome lit2' in
                    let new_lit = Lit.mk_arith_neq
                      (M.sum m1 (MF.rest mf2))
                      (M.sum m2 (MF.rest mf1))
                    in
                    let other_lits = Util.array_except_idx (C.lits c) idx1 in
                    let other_lits = Lit.apply_subst_list
                      ~renaming subst other_lits 0 in
                    (* apply subst and build clause *)
                    let all_lits = new_lit :: other_lits in
                    let proof cc = Proof.mk_c_inference ~theories
                      ~info:[Substs.to_string subst;
                             Util.sprintf "idx(%d,%d)" idx1 idx2]
                      ~rule:"arith_eq_factoring" cc [C.proof c] in
                    let new_c = C.create all_lits proof in
                    Util.debug 5 "arith_eq_factoring: %a gives %a" C.pp c C.pp new_c;
                    Util.incr_stat stat_arith_eq_factoring;
                    new_c :: acc
                  end else acc
                ) acc
            with Unif.Fail ->
              acc
          )
      )
    in Util.exit_prof prof_arith_eq_factoring;
    res

  (** Data necessary to fully describe a chaining inference.
      [left] is basically the clause/literal in which the chained
      term is on the left of <,
      [right] is the other one. *)
  module ChainingInfo = struct
    type t = {
      left : C.t;
      left_scope : scope;
      left_pos : Position.t;
      left_lit : ArithLit.Focus.t;
      right : C.t;
      right_scope : scope;
      right_pos : Position.t;
      right_lit : ArithLit.Focus.t;
      subst : Substs.t;
    }
  end

  (* cancellative chaining *)
  let _do_chaining info acc =
    let open ChainingInfo in
    let ord = Ctx.ord () in
    let renaming = Ctx.renaming_clear () in
    let subst = info.subst in
    let idx_l, _ = Lits.Pos.cut info.left_pos in
    let idx_r, _ = Lits.Pos.cut info.right_pos in
    let s_l = info.left_scope and s_r = info.right_scope in
    let lit_l = ALF.apply_subst ~renaming subst info.left_lit s_l in
    let lit_r = ALF.apply_subst ~renaming subst info.right_lit s_r in
    Util.debug 5 "arith superposition between %a[%d] and %a[%d] (subst %a)..."
      C.pp info.left s_l C.pp info.right s_r Substs.pp subst;
    (* check ordering conditions *)
    if C.is_maxlit info.left s_l subst idx_l
    && C.is_maxlit info.right s_r subst idx_r
    && ALF.is_max ~ord lit_l
    && ALF.is_max ~ord lit_r
    then begin
      (* scale literals *)
      let lit_l, lit_r = ALF.scale lit_l lit_r in
      match lit_l, lit_r with
      | ALF.Left (AL.Less, mf_1, m1), ALF.Right (AL.Less, m2, mf_2) ->
        (* m2 < mf_2 and mf_1 < m1, with mf_1 and mf_2 sharing the same
          focused term. We deduce m2 + mf_1 + 1 < m1 + mf_2 and cancel the
          term out (after scaling) *)
        assert (Z.equal (MF.coeff mf_1) (MF.coeff mf_2));
        let new_lit = Lit.mk_arith_less
          (M.succ (M.sum m2 (MF.rest mf_1)))
          (M.sum m1 (MF.rest mf_2))
        in
        let lits_l = Util.array_except_idx (C.lits info.left) idx_l in
        let lits_l = Lit.apply_subst_list ~renaming subst lits_l s_l in
        let lits_r = Util.array_except_idx (C.lits info.right) idx_r in
        let lits_r = Lit.apply_subst_list ~renaming subst lits_r s_r in
        let all_lits = new_lit :: lits_l @ lits_r in
        let proof cc = Proof.mk_c_inference ~theories
          ~info:[Substs.to_string subst; Util.sprintf "idx(%d,%d)" idx_l idx_r
                ; Util.sprintf "left(%a)" T.pp (MF.term mf_2)
                ; Util.sprintf "right(%a)" T.pp (MF.term mf_1)]
          ~rule:"canc_ineq_chaining" cc [C.proof info.left; C.proof info.right] in
        let new_c = C.create ~parents:[info.left; info.right] all_lits proof in
        Util.debug 5 "ineq chaining of %a and %a gives %a"
          C.pp info.left C.pp info.right C.pp new_c;
        Util.incr_stat stat_arith_ineq_chaining;
        new_c :: acc
      | _ -> assert false
    end else
      acc

  let canc_ineq_chaining c =
    Util.enter_prof prof_arith_ineq_chaining;
    let ord = Ctx.ord () in
    let eligible = C.Eligible.(max c ** filter Lit.is_arith_less) in
    let sc_l = 0 and sc_r = 1 in
    let res = Lits.fold_arith_terms ~eligible ~ord ~which:`Max (C.lits c) []
      (fun acc t lit pos ->
        let idx = Lits.Pos.idx pos in
        match lit with
        | ALF.Left (AL.Less, mf_l, _) ->
          (* find a right-chaining literal in some other clause *)
          PS.TermIndex.retrieve_unifiables !_idx_ineq sc_r t sc_l acc
            (fun acc _t' with_pos subst ->
              let right = with_pos.C.WithPos.clause in
              let right_pos = with_pos.C.WithPos.pos in
              let lit_r = Lits.View.get_arith_exn (C.lits right) right_pos in
              match lit_r with
              | ALF.Right (AL.Less, _, mf_r) ->
                MF.unify_ff ~subst mf_l sc_l mf_r sc_r
                |> Sequence.fold
                  (fun acc (_, _, subst) ->
                    let info = ChainingInfo.({
                      left=c; left_scope=sc_l; left_lit=lit; left_pos=pos;
                      right; right_scope=sc_r; right_lit=lit_r; right_pos; subst;
                    }) in _do_chaining info acc
                  ) acc
              | _ -> acc
            )
        | ALF.Right (AL.Less, _, mf_r) ->
          (* find a right-chaining literal in some other clause *)
          PS.TermIndex.retrieve_unifiables !_idx_ineq sc_l t sc_r acc
            (fun acc _t' with_pos subst ->
              let left = with_pos.C.WithPos.clause in
              let left_pos = with_pos.C.WithPos.pos in
              let lit_l = Lits.View.get_arith_exn (C.lits left) left_pos in
              match lit_l with
              | ALF.Left (AL.Less, mf_l, _) ->
                MF.unify_ff ~subst mf_l sc_l mf_r sc_r
                |> Sequence.fold
                  (fun acc (_, _, subst) ->
                    let info = ChainingInfo.({
                      left; left_scope=sc_l; left_lit=lit_l; left_pos; subst;
                      right=c; right_scope=sc_r; right_lit=lit; right_pos=pos;
                    }) in _do_chaining info acc
                  ) acc
              | _ -> acc
            )
        | _ -> assert false
      )
    in
    Util.exit_prof prof_arith_ineq_chaining;
    res

  (* new inference, kind of the dual of inequality chaining for integer
     inequalities. See the .mli file for more explanations. *)
  let canc_case_switch c = [] (* TODO *)
  (*
    Util.enter_prof prof_canc_case_switch;
    let ctx = state#ctx in
    let ord = Ctx.ord ctx in
    (* try case switch between ~left and ~right.
      lit = [m1 + nt <| m2], lit' = [m2' <| m1' + nt],
      so [nt] lives within [m2'-m1', ..., m2-m1]. If those two bounds differ
      only by a constant, then we can enumerate the cases. *)
    let _case_switch ~left:(c,s_c,i,lit,strict) ~right:(c',s_c',j,lit',strict') subst acc =
      let lit, lit' = Foc.scale lit lit' in
      (* negation of strictness (range inclusive if bound was exclusive,
          because contrapositive) *)
      let strict_low = lit'.Foc.op = ArithLit.Lt in
      let strict_high = lit.Foc.op = ArithLit.Lt in
      (* apply subst and decompose *)
      let renaming = Ctx.renaming_clear ~ctx in
      let lit = Foc.apply_subst ~renaming subst lit s_c in
      let lit' = Foc.apply_subst ~renaming subst lit' s_c' in
      let m1, m2 = lit.Foc.same_side, lit.Foc.other_side in
      let m1', m2' = lit'.Foc.same_side, lit'.Foc.other_side in
      let m = M.difference (M.sum m2 m1') (M.sum m1 m2') in
      let n = lit.Foc.coeff in
      let t = lit.Foc.term in
      if M.is_const m
      && S.Arith.Op.less m.M.const !case_switch_limit
      && C.is_maxlit c s_c subst i
      && C.is_maxlit c' s_c' subst j
      && Foc.is_max ~ord (Foc.apply_subst ~renaming subst lit s_c)
      && Foc.is_max ~ord (Foc.apply_subst ~renaming subst lit' s_c')
      then begin
        let low = M.difference m2' m1' in
        Util.debug 5 "case_switch between %a at %d and %a at %d" C.pp c i C.pp c' j;
        let range = match m.M.const with
          | S.Int n -> n
          | _ -> assert false
        in
        let lits_left = Util.array_except_idx c.C.hclits i in
        let lits_left = Lit.apply_subst_list ~renaming ~ord subst lits_left s_c in
        let lits_right = Util.array_except_idx c'.C.hclits j in
        let lits_right = Lit.apply_subst_list ~renaming ~ord subst lits_right s_c' in
        (* the case switch on [nt]: for n=0...range, add literal  [nt=low + n] *)
        let lits_case = List.map
          (fun k ->
            let lit = Canon.to_lit ~ord
              (Canon.of_monome ArithLit.Eq
                (M.add
                  (M.add_const low (S.mk_bigint k))
                  (S.Arith.Op.uminus n) t))
            in
            lit)
          (AT.int_range ~strict_low ~strict_high range)
        in
        let new_lits = lits_left @ lits_right @ lits_case in
        let proof cc = Proof.mk_c_inference
          ~theories:["arith"] ~info:[Substs.FO.to_string subst]
          ~rule:"arith_case_switch" cc [c.C.hcproof; c'.C.hcproof] in
        let parents = [c; c'] in
        let new_c = C.create ~parents ~ctx new_lits proof in
        Util.debug 5 "  --> case switch gives clause %a" C.pp new_c;
        Util.incr_stat stat_canc_case_switch;
        new_c :: acc
      end else acc
    in
    let new_clauses = ArithLit.Arr.fold_focused ~ord c.C.hclits []
      (fun acc i lit ->
        match lit.Foc.op with
        | (ArithLit.Leq | ArithLit.Lt) when Type.eq Type.int (S.ty lit.Foc.coeff) ->
          let t = lit.Foc.term in
          let strict = lit.Foc.op = ArithLit.Lt in
          I.retrieve_unifiables state#idx_canc 0 t 1 acc
            (fun acc t' (c',j,lit') subst ->
              (* lit' = t' + m1' <| m2' ? *)
              match lit'.Foc.op, lit.Foc.side, lit'.Foc.side with
              | (ArithLit.Leq | ArithLit.Lt), ArithLit.Left, ArithLit.Right ->
                let strict' = lit'.Foc.op = ArithLit.Lt in
                _case_switch ~left:(c,1,i,lit,strict) ~right:(c',0,j,lit',strict') subst acc
              | (ArithLit.Leq | ArithLit.Lt), ArithLit.Right, ArithLit.Left ->
                let strict' = lit'.Foc.op = ArithLit.Lt in
                _case_switch ~left:(c',0,j,lit',strict') ~right:(c,1,i,lit,strict) subst acc
              | _ -> acc
            )
        | _ -> acc)
    in
    Util.exit_prof prof_canc_case_switch;
    new_clauses
  *)

  let canc_inner_case_switch c = []
  (*
    Util.enter_prof prof_canc_inner_case_switch;
    let ctx = c.C.hcctx in
    let ord = Ctx.ord ctx in
    (* lit = [t + m1 <| m2], lit' = [m2' <| t + m1']. In other words,
        [t > m2-m1 and t < m2'-m1' --> other_lits]. If
        [m2'-m1' - (m2-m1) is a constant, we can enumerate the possibilities
        by replacing lit and lit' by [n.t != m2'+m1-(m2+m1')+k]
        for k in [0... range] *)
    let _try_case_switch ~left:(lit,i,op) ~right:(lit',j,op') subst acc =
      assert (lit.Foc.side = ArithLit.Left);
      assert (lit'.Foc.side = ArithLit.Right);
      (* negation of strictness (range inclusive if bound was exclusive,
          because contrapositive) *)
      let strict_low = lit'.Foc.op = ArithLit.Leq in
      let strict_high = lit.Foc.op = ArithLit.Leq in
      (* apply subst and decompose *)
      let renaming = Ctx.renaming_clear ~ctx in
      let lit = Foc.apply_subst ~renaming subst lit 0 in
      let lit' = Foc.apply_subst ~renaming subst lit' 0 in
      let m1, m2 = lit.Foc.same_side, lit.Foc.other_side in
      let m1', m2' = lit'.Foc.same_side, lit'.Foc.other_side in
      let m = M.difference (M.sum m2' m1) (M.sum m1' m2) in
      let n = lit.Foc.coeff in
      let t = lit.Foc.term in
      if M.is_const m
      && S.Arith.Op.less m.M.const !case_switch_limit
      then begin
        let low = M.difference m2 m1 in
        let range = match m.M.const with
          | S.Int n -> n
          | _ -> assert false
        in
        Util.debug 5 "inner_case_switch in %a for %a·%a; subst is %a, range=%s"
          C.pp c S.pp n T.pp t Substs.FO.pp subst (Big_int.string_of_big_int range);
        (* remove lits i and j *)
        let other_lits = Util.array_foldi
          (fun acc i' lit -> if i' <> i && i' <> j then lit :: acc else acc)
          [] c.C.hclits
        in
        let other_lits = Literal.apply_subst_list ~renaming ~ord subst other_lits 0 in
        List.fold_left
          (fun acc k ->
            let lit = Canon.to_lit ~ord
              (Canon.of_monome ArithLit.Neq
                (M.add
                  (M.add_const low (S.mk_bigint k))
                  (S.Arith.Op.uminus n) t))
            in
            let new_lits = lit :: other_lits in
            let proof cc = Proof.mk_c_inference ~theories:["arith";"equality"]
              ~rule:"canc_inner_case_switch" cc [c.C.hcproof] in
            let parents = [c] in
            let new_clause = C.create ~parents ~ctx new_lits proof in
            Util.debug 5 "  --> inner case switch gives clause %a" C.pp new_clause;
            Util.incr_stat stat_canc_inner_case_switch;
            new_clause :: acc)
          acc (AT.int_range ~strict_low ~strict_high range)
      end else acc
    in
    (* focused view of arith literals *)
    let lits = ArithLit.Arr.view_focused ~ord c.C.hclits in
    (* fold on literals *)
    let new_clauses = Util.array_foldi
      (fun acc i lit -> match lit with
      | `Focused ((ArithLit.Leq|ArithLit.Lt) as op, l) ->
        List.fold_left
          (fun acc lit ->
            let side = lit.Foc.side in
            Util.array_foldi
              (fun acc j lit' -> match lit' with
              | `Focused ((ArithLit.Leq|ArithLit.Lt) as op', l') ->
                List.fold_left
                  begin fun acc lit' ->
                    let side' = lit'.Foc.side in
                    if side <> side' && Type.eq Type.int (T.ty lit.Foc.term) then try
                      (* unify the two terms, then scale them to the same coefficient *)
                      let subst = FOUnif.unification lit.Foc.term 0 lit'.Foc.term 0 in
                      let lit, lit' = Foc.scale lit lit' in
                      if side = ArithLit.Left
                        then _try_case_switch ~left:(lit,i,op) ~right:(lit',j,op') subst acc
                        else _try_case_switch ~left:(lit',j,op') ~right:(lit,i,op) subst acc
                    with FOUnif.Fail -> acc
                    else acc
                  end acc l'
              | _ -> acc)
            acc lits
          ) acc l
      | _ -> acc
      ) [] lits
    in
    Util.exit_prof prof_canc_inner_case_switch;
    new_clauses
  *)

  let canc_ineq_factoring c = [] (* TODO *)
  (*
    Util.enter_prof prof_canc_ineq_factoring;
    let ctx = c.C.hcctx in
    let ord = Ctx.ord ctx in
    (* factoring1 for lit, lit'. Let:
        lit = [t + m1 <| m2], and lit' = [t + m1' <| m2'].
        If [m2 - m1 < m2' - m1'], then the first lit doesn't
        contribute a constraint to the clause
        (a < 0 | a < 5 ----> a < 5), so by constraining this
        to be false we have
        [m2' - m1' <| m2 - m1 | lit'], in other words,
        [m2' + m1 <| m2 + m1' | lit'] *)
    let _factor1 ~info lit lit' other_lits acc =
      let strict = lit.Foc.op = ArithLit.Lt in
      let strict' = lit'.Foc.op = ArithLit.Lt in
      let m1, m2 = lit.Foc.same_side, lit.Foc.other_side in
      let m1', m2' = lit'.Foc.same_side, lit'.Foc.other_side in
      (* always using a "<" constraint is safe, so its negation is to always
          use "<=" as an alternative. But if both are strict, we know that
          using "<" is ok (see paper on cancellative sup/chaining). *)
      let new_op = if strict && strict' then ArithLit.Lt else ArithLit.Leq in
      (* build new literal (the guard) *)
      let new_lit = match lit.Foc.side, lit'.Foc.side with
        | ArithLit.Left, ArithLit.Left ->
          (* t on left, relation is a "lower than" relation *)
          Canon.to_lit ~ord
            (Canon.of_monome new_op
              (M.difference (M.sum m2' m1) (M.sum m2 m1')))
        | ArithLit.Right, ArithLit.Right ->
          (* t on right, relation is "bigger than" *)
          Canon.to_lit ~ord
            (Canon.of_monome new_op
              (M.difference (M.sum m2 m1') (M.sum m2' m1)))
        | _ -> assert false
      in
      let new_lits = new_lit :: other_lits in
      (* apply subst and build clause *)
      let proof cc = Proof.mk_c_inference ~theories ~info
        ~rule:"canc_ineq_factoring1" cc [c.C.hcproof] in
      let new_c = C.create ~ctx new_lits proof in
      Util.debug 5 "cancellative_ineq_factoring1: %a gives %a" C.pp c C.pp new_c;
      Util.incr_stat stat_canc_ineq_factoring;
      new_c :: acc
    (* slightly different: with same notation for lit and lit',
      but this time we eliminate lit' *)
    and _factor2 ~info lit lit' other_lits acc =
      let strict = lit.Foc.op = ArithLit.Lt in
      let strict' = lit'.Foc.op = ArithLit.Lt in
      let m1, m2 = lit.Foc.same_side, lit.Foc.other_side in
      let m1', m2' = lit'.Foc.same_side, lit'.Foc.other_side in
      let new_op = if strict && strict' then ArithLit.Lt else ArithLit.Leq in
      (* build new literal (the guard) *)
      let new_lit = match lit.Foc.side, lit'.Foc.side with
        | ArithLit.Left, ArithLit.Left ->
          (* t on left, relation is a "lower than" relation *)
          Canon.to_lit ~ord
            (Canon.of_monome new_op
              (M.difference (M.sum m1' m2) (M.sum m1 m2')))
        | ArithLit.Right, ArithLit.Right ->
          (* t on right, relation is "bigger than" *)
          Canon.to_lit ~ord
            (Canon.of_monome new_op
              (M.difference (M.sum m1 m2') (M.sum m1' m2)))
        | _ -> assert false
      in
      let new_lits = new_lit :: other_lits in
      (* apply subst and build clause *)
      let proof cc = Proof.mk_c_inference ~theories ~info
        ~rule:"canc_ineq_factoring2" cc [c.C.hcproof] in
      let new_c = C.create ~ctx new_lits proof in
      Util.debug 5 "cancellative_ineq_factoring2: %a gives %a" C.pp c C.pp new_c;
      Util.incr_stat stat_canc_ineq_factoring;
      new_c :: acc
    in
    (* factor lit and lit' (2 ways) *)
    let _factor ~left:(lit,i,op) ~right:(lit',j,op') subst acc =
      let renaming = Ctx.renaming_clear ~ctx in
      (* check maximality of left literal, and maximality of factored terms
        within their respective literals *)
      if C.is_maxlit c i subst 0
      && Foc.is_max ~ord (Foc.apply_subst ~renaming subst lit 0)
      && Foc.is_max ~ord (Foc.apply_subst ~renaming subst lit' 0)
      then begin
        let lit, lit' = Foc.scale lit lit' in
        let lit = Foc.apply_subst ~renaming subst lit 0 in
        let lit' = Foc.apply_subst ~renaming subst lit' 0 in
        let all_lits = Literal.Arr.apply_subst ~renaming ~ord subst c.C.hclits 0 in
        (* the two inferences (eliminate lit i/lit j respectively) *)
        let info = [Substs.FO.to_string subst; Util.sprintf "idx(%d,%d)" i j] in
        let acc = _factor1 ~info lit lit' (Util.array_except_idx all_lits i) acc in
        let acc = _factor2 ~info lit lit' (Util.array_except_idx all_lits j) acc in
        acc
      end else acc
    in
    (* pairwise unify terms of focused lits *)
    let eligible = C.Eligible.pos in
    let view = ArithLit.Arr.view_focused ~eligible ~ord c.C.hclits in
    let res = Util.array_foldi
      (fun acc i lit -> match lit with
      | `Focused ((ArithLit.Lt | ArithLit.Leq) as op, l) ->
        List.fold_left
          (fun acc lit ->
            Util.array_foldi
              (fun acc j lit' -> match lit' with
              | `Focused ((ArithLit.Lt | ArithLit.Leq) as op', l') when i <> j ->
                List.fold_left
                  (fun acc lit' ->
                    (* only work on same side of comparison *)
                    if lit'.Foc.side = lit.Foc.side
                      then try
                        (* unify the two terms *)
                        let subst = FOUnif.unification lit.Foc.term 0 lit'.Foc.term 0 in
                        _factor ~left:(lit,i,op) ~right:(lit',j,op') subst acc
                      with FOUnif.Fail -> acc
                    else acc)
                  acc l'
              | _ -> acc)
              acc view)
          acc l
        | _ -> acc)
      [] view
    in
    Util.exit_prof prof_canc_ineq_factoring;
    res
  *)

  (** {3 Divisibility} *)

  let canc_div_chaining c = []  (* TODO *)

  exception ReplaceLitByLitsInSameClause of int * Lit.t list
  exception ReplaceLitByLitsInManyClauses of int * Lit.t list

  let canc_div_case_switch c =
    let eligible = C.Eligible.(max c ** neg ** filter Lit.is_arith_divides) in
    try
      Lits.fold_arith ~eligible (C.lits c) ()
        (fun () lit pos -> match lit with
          | AL.Divides d ->
            assert (not (d.AL.sign));
            let n = d.AL.num and power = d.AL.power in
            (* check that [n] is a not-too-big prime *)
            if Z.gt n Z.one && AL.Util.is_prime n then
              if Z.leq n (Z.of_int !div_case_switch_limit)
                then begin
                  let idx = Lits.Pos.idx pos in
                  (* build the list of alternatives *)
                  let lits = ref [] in
                  for e = 0 to power-1 do
                    for i=1 to Z.to_int n - 1 do
                      (* new lit:   n^{e+1} | m + i·n^e *)
                      let m' = M.add_const d.AL.monome
                        Z.((n ** e) * of_int i)
                      in
                      let new_lit = Lit.mk_divides
                        n ~power:(e+1) m'
                      in
                      lits := new_lit :: !lits
                    done
                  done;
                  raise (ReplaceLitByLitsInSameClause (idx, !lits))
                end
                else Ctx.lost_completeness ()
              else ()
          | _ -> assert false
        );
      c
    with ReplaceLitByLitsInSameClause (i, lits) ->
      (* replace lit number [i] with [lits] *)
      let lits' = Util.array_except_idx (C.lits c) i in
      let all_lits = List.rev_append lits lits' in
      let proof cc = Proof.mk_c_inference ~rule:"div_case_switch"
        ~theories cc [C.proof c] in
      let new_c = C.create ~parents:[c] all_lits proof in
      Util.debug 5 "div_case_switch of %a into %a" C.pp c C.pp new_c;
      new_c

  let canc_div_prime_decomposition c =
    let eligible = C.Eligible.(max c ** filter Lit.is_arith_divides) in
    try
      Lits.fold_arith ~eligible (C.lits c) ()
        (fun () lit pos -> match lit with
          | AL.Divides d when d.AL.sign ->
            (* positive "divides" predicate *)
            let n = d.AL.num and power = d.AL.power in
            (* check that [n] is a composite number *)
            if Z.gt n Z.one && not (AL.Util.is_prime n) then begin
              let idx = Lits.Pos.idx pos in
              let divisors = AL.Util.prime_decomposition n in
              assert (List.length divisors >= 2);
              let lits = List.map
                (fun div -> Lit.mk_divides ~sign:true
                    div.AL.Util.prime ~power:div.AL.Util.power d.AL.monome)
                divisors
              in
              raise (ReplaceLitByLitsInManyClauses (idx, lits))
            end
          | AL.Divides d ->
            (* negative "divides" predicate *)
            let n = d.AL.num and power = d.AL.power in
            (* check that [n] is a composite number *)
            if Z.gt n Z.one && not (AL.Util.is_prime n) then begin
              let idx = Lits.Pos.idx pos in
              let divisors = AL.Util.prime_decomposition n in
              assert (List.length divisors >= 2);
              let lits = List.map
                (fun div -> Lit.mk_divides ~sign:false
                    div.AL.Util.prime ~power:div.AL.Util.power d.AL.monome)
                divisors
              in
              raise (ReplaceLitByLitsInSameClause (idx, lits))
            end
          | _ -> assert false
        );
      None
    with ReplaceLitByLitsInSameClause (i, lits) ->
      (* replace lit number [i] with [lits] *)
      let lits' = Util.array_except_idx (C.lits c) i in
      let all_lits = List.rev_append lits lits' in
      let proof cc = Proof.mk_c_inference ~rule:"div_prime_decomposition"
        ~theories cc [C.proof c] in
      let new_c = C.create ~parents:[c] all_lits proof in
      Util.debug 5 "prime_decomposition of %a into %a" C.pp c C.pp new_c;
      Some [new_c]
    | ReplaceLitByLitsInManyClauses (i, lits) ->
      let clauses = List.map
        (fun lit ->
          let all_lits = Array.copy (C.lits c) in
          all_lits.(i) <- lit;
          let proof cc = Proof.mk_c_inference ~theories
            ~rule:"div_prime_decomposition" cc [C.proof c] in
          let new_c = C.create_a ~parents:[c] all_lits proof in
          new_c)
        lits
      in
      Util.debug 5 "prime_decomposition of %a into [%a]"
        C.pp c (Util.pp_list C.pp) clauses;
      Some clauses

  (* a mod n = n' ----> divisibility literal *)
  let canc_div_of_remainder lit =
    let module TC = FOTerm.Classic in
    let module SA = Symbol.TPTP.Arith in
    match lit with
    | Lit.Equation (l, r, sign) ->
        begin match TC.view l, TC.view r with
        | (TC.App (s, _, [l'; r']), opp
        | opp, TC.App (s, _, [l'; r'])) when Symbol.eq s SA.remainder_e ->
            begin match Monome.Int.of_term l', T.view r', opp with
            | Some m, T.Const (Symbol.Int n), TC.App (Symbol.Int opp', _, []) ->
                (* remainder(l1, n) = opp ----> n | l1-opp *)
                Lit.mk_divides ~sign n ~power:1 (M.add_const m Z.(~- opp'))
            | _ -> lit
            end
        | _ -> lit
        end
    | _ -> lit

  (** {3 Others} *)

  (* redundancy criterion: if variables are replaced by constants,
     do equations and inequations in left part of =>
     always imply something on the right part of => ?

     e,g, transitivity is redundant, because we have
     ~ x<y | ~ y<z | x<z, once simplified and grounded,
     x < y & y < z ==> x < z is always trivial

     We consider that  a <= b is negation for b < a, and use the congruence
     closure (same as for {!Superposition.is_semantic_tautology}) *)
  let is_tautology c = false
  (* TODO
    Util.enter_prof prof_canc_semantic_tautology;
    let cc = Congruence.FO.create ~size:13 () in
    (* ineq to checks afterward *)
    let to_check = ref [] in
    (* monomes met so far (to compare them) *)
    let monomes = ref [] in
    (* build congruence *)
    ArithLit.Arr.fold_canonical c.C.hclits ()
      begin fun () i lit -> match lit with
        | Canon.True | Canon.False -> ()
        | Canon.Compare (op, m1, m2) ->
          monomes := m1 :: m2 :: !monomes;
          match op with
          | ArithLit.Neq ->
            Congruence.FO.mk_eq cc (M.to_term m1) (M.to_term m2)
          | ArithLit.Eq ->
            to_check := `Eq (M.to_term m1, M.to_term m2) :: !to_check
          | ArithLit.Leq ->
            Congruence.FO.mk_less cc (M.to_term m2) (M.to_term m1)
          | ArithLit.Lt ->
            to_check := `Lt (M.to_term m1, M.to_term m2) :: !to_check
      end;
    List.iter
      (fun (m1, m2) ->
        if m1 != m2 then
          (* m1 and m2 are comparable? *)
          match M.comparison m1 m2 with
          | Comparison.Eq ->
            Congruence.FO.mk_eq cc (M.to_term m1) (M.to_term m2)
          | Comparison.Lt ->
            Congruence.FO.mk_less cc (M.to_term m1) (M.to_term m2)
          | Comparison.Gt ->
            Congruence.FO.mk_less cc (M.to_term m2) (M.to_term m1)
          | Comparison.Incomparable -> ())
      (Util.list_diagonal !monomes);
    (* check if inequality holds in congruence OR congruence tautological *)
    let res =
      Congruence.FO.cycles cc ||
      List.exists
        (function
        | `Eq (l,r) -> Congruence.FO.is_eq cc l r
        | `Lt (l,r) -> Congruence.FO.is_less cc l r)
        !to_check
    in
    if res then begin
      Util.incr_stat stat_canc_semantic_tautology;
      Util.debug 2 "%a is a cancellative semantic tautology" C.pp c;
      end;
    Util.exit_prof prof_canc_semantic_tautology;
    res
  *)

  (* a <= b ----> a < b+1 *)
  let canc_lesseq_to_less = function
    | Lit.Arith (AL.Binary (AL.Lesseq, m1, m2)) ->
        Lit.mk_arith_less m1 (M.succ m2)
    | lit -> lit

  (* replace arith subterms with fresh variable + constraint *)
  let purify c =
    Util.enter_prof prof_arith_purify;
    (* set of new literals *)
    let new_lits = ref [] in
    let _add_lit lit = new_lits := lit :: !new_lits in
    let varidx = ref ((Lits.Seq.terms (C.lits c)
      |> Sequence.flatMap T.Seq.vars |> T.Seq.max_var) + 1) in
    (* purify a term (adding constraints to the list).  *)
    let rec purify_term t = match T.view t with
      | T.Const s when Symbol.is_numeric s -> t   (* keep constants *)
      | T.Const _
      | T.TyApp _
      | T.BVar _
      | T.Var _ -> t
      | T.App (hd, l) ->
        Util.debug 5 "purification at %a" T.pp t;
        match T.head hd with
        | Some s when Symbol.TPTP.Arith.is_arith s ->
          Util.debug 5 "need to purify term %a" T.pp t;
          (* purify the term and add a constraint *)
          let l' = List.map purify_term l in
          let t' = T.app hd l' in
          begin match M.Int.of_term t' with
          | None ->
            Util.debug 5 "could not purify %a (non linear)" T.pp t';
            t'  (* non linear, abort. *)
          | Some m ->
            (* purify this term out! *)
            let ty = T.ty t in
            let v = T.var ~ty !varidx in
            incr varidx;
            let lit = Lit.mk_arith_neq (M.Int.singleton Z.one v) m in
            _add_lit lit;
            (* return variable instead of literal *)
            v
          end
        | None -> Util.debug 5 "no head for %a" T.pp t; t
        | Some _ ->
          T.app hd (List.map purify_term l)
    in
    (* replace! *)
    let lits' = Lits.map purify_term (C.lits c) in
    let res = match !new_lits with
    | [] -> c (* no change *)
    | _::_ ->
        let all_lits = !new_lits @ (Array.to_list lits') in
        let proof cc = Proof.mk_c_inference ~theories ~rule:"purify" cc [C.proof c] in
        let new_c = C.create ~parents:[c] all_lits proof in
        Util.debug 5 "purify %a into %a" C.pp c C.pp new_c;
        Util.incr_stat stat_arith_purify;
        new_c
    in
    Util.exit_prof prof_arith_purify;
    res

  let is_shielded lits ~var =
    let rec shielded_by_term ~root t = match T.view t with
      | T.Var _ when T.eq t var -> not root
      | T.Var _
      | T.BVar _
      | T.Const _
      | T.TyApp _ -> false
      | T.App (hd, l) ->
          match T.head hd with
          | Some s when Symbol.TPTP.Arith.is_arith s ->
            (* arithmetic term, [root] may continue to be true *)
            List.exists (shielded_by_term ~root) l
          | None
          | Some _ ->
            List.exists (shielded_by_term ~root:false) l
    in
    (* is there a term, directly under a literal, that shields the variable? *)
    lits
      |> Lits.Seq.terms
      |> Sequence.exists (shielded_by_term ~root:true)

  let naked_vars lits =
    let vars = Lits.vars lits in
    List.filter (fun var -> not (is_shielded lits ~var)) vars

  let eliminate_unshielded c = None  (* TODO *)

  (** {2 Setup} *)

  let register () =
    Util.debug 2 "cancellative inf: setup env";
    Env.add_binary_inf "canc_sup_active" canc_sup_active;
    Env.add_binary_inf "canc_sup_passive" canc_sup_passive;
    Env.add_unary_inf "cancellation" cancellation;
    Env.add_unary_inf "canc_eq_factoring" canc_equality_factoring;
    Env.add_binary_inf "canc_ineq_chaining" canc_ineq_chaining;
    Env.add_unary_inf "canc_ineq_factoring" canc_ineq_factoring;
    Env.add_binary_inf "canc_case_switch" canc_case_switch;
    Env.add_unary_inf "canc_inner_case_switch" canc_inner_case_switch;
    Env.add_binary_inf "div_chaining" canc_div_chaining;
    Env.add_simplify canc_div_case_switch;
    Env.add_multi_simpl_rule canc_div_prime_decomposition;
    Env.add_lit_rule "div_of_remainder" canc_div_of_remainder;
    Env.add_lit_rule "lesseq_to_less" canc_lesseq_to_less;
    Env.add_is_trivial is_tautology;
    Env.add_simplify purify;
    Env.add_multi_simpl_rule eliminate_unshielded;
    Ctx.Lit.add_from_hook Lit.Conv.arith_hook_from;
    (* enable AC-property of sum *)
    if !_enable_ac then begin
      let sum = Symbol.TPTP.Arith.sum in
      let ty = Signature.find_exn Signature.TPTP.Arith.full sum in
      Ctx.Theories.AC.add ~ty sum;
    end;
    ()
end

let setup_penv penv =
  Util.debug 2 "arith inf: setup penv";
  ()

let extension =
  let module DOIT(Env : Env.S) = struct
    include Extensions.MakeAction(Env)
    module I = Make(Env)
    let actions =
      [ Ext_general I.register
      ]
  end
  in
  { Extensions.name="arith_int";
    Extensions.penv_actions = [Extensions.Ext_penv_do setup_penv];
    Extensions.make=(module DOIT : Extensions.ENV_TO_S);
  }

let _enable_arith () =
  if not !_enable_arith then begin
    _enable_arith := true;
    (* enable arith printing of terms *)
    T.add_hook T.TPTP.Arith.arith_hook;
    (* enrich signature with arith operators *)
    Params.signature := Signature.merge
      !Params.signature Signature.TPTP.Arith.full;
    Extensions.register extension;
  end

let () =
  Params.add_opts
    [ "-arith-semantic-tauto"
      , Arg.Unit (fun () -> _enable_arith (); _enable_semantic_tauto := true)
      , "enable arithmetic semantic tautology check"
    ; "-arith"
      , Arg.Unit _enable_arith
      , "enable axiomatic integer arithmetic"
    ; "-arith-ac"
      , Arg.Set _enable_ac
      , "enable AC axioms for arithmetic (sum)"
    ];
  ()