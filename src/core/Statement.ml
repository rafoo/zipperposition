
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Statement} *)


(** A datatype declaration *)
type 'ty data = {
  data_id: ID.t;
  (** Name of the type *)
  data_args: 'ty Var.t list;
  (** type parameters *)
  data_ty: 'ty;
  (** type of Id, that is,   [type -> type -> ... -> type] *)
  data_cstors: (ID.t * 'ty) list;
  (** Each constructor is [id, ty]. [ty] must be of the form
      [ty1 -> ty2 -> ... -> id args] *)
}

type attr =
  | A_AC

type attrs = attr list

type 'ty skolem = ID.t * 'ty

type ('t, 'ty) term_rule = 'ty Var.t list * ID.t * 'ty * 't list * 't
(** [forall vars, id args = rhs] *)

type ('f, 't, 'ty) form_rule = 'ty Var.t list * 't SLiteral.t * 'f list
(** [forall vars, lhs <=> bigand rhs] *)

type ('f, 't, 'ty) def_rule =
  | Def_term of ('t, 'ty) term_rule
  | Def_form of ('f, 't, 'ty) form_rule

type ('f, 't, 'ty) def = {
  def_id: ID.t;
  def_ty: 'ty; (* def_ty = def_vars -> def_ty_ret *)
  def_rules: ('f, 't, 'ty) def_rule list;
  def_rewrite: bool; (* rewrite rule or mere assertion? *)
}

type ('f, 't, 'ty) view =
  | TyDecl of ID.t * 'ty (** id: ty *)
  | Data of 'ty data list
  | Def of ('f, 't, 'ty) def list
  | RewriteTerm of ('t, 'ty) term_rule
  | RewriteForm of ('f, 't, 'ty) form_rule
  | Assert of 'f (** assert form *)
  | Lemma of 'f list (** lemma to prove and use, using Avatar cut *)
  | Goal of 'f (** goal to prove *)
  | NegatedGoal of 'ty skolem list * 'f list (** goal after negation, with skolems *)

(* a statement in a file *)
type from_file = {
  file : string;
  name : string option;
  loc: ParseLocation.t option;
}

type lit = FOTerm.t SLiteral.t
type formula = TypedSTerm.t
type clause = lit list

type role =
  | R_assert
  | R_goal
  | R_def
  | R_decl

type ('f, 't, 'ty) t = {
  id: int;
  view: ('f, 't, 'ty) view;
  attrs: attrs;
  src: source;
}

and source = {
  src_id: int;
  src_view: source_view;
}
and source_view =
  | Input of UntypedAST.attrs * role
  | From_file of from_file * role
  | Internal of role
  | Neg of sourced_t
  | CNF of sourced_t
  | Renaming of sourced_t * ID.t * formula (* renamed this formula *)
  | Preprocess of sourced_t * string

and result =
  | Sourced_input of TypedSTerm.t
  | Sourced_clause of clause
  | Sourced_statement of input_t

and sourced_t = result * source

and input_t = (TypedSTerm.t, TypedSTerm.t, TypedSTerm.t) t
and clause_t = (clause, FOTerm.t, Type.t) t

let compare a b = CCInt.compare a.id b.id
let view t = t.view
let attrs t = t.attrs
let src t = t.src

let mk_data id ~args ty cstors =
  {data_id=id; data_args=args; data_ty=ty; data_cstors=cstors; }

let mk_def ?(rewrite=false) id ty rules =
  { def_id=id; def_ty=ty; def_rules=rules; def_rewrite=rewrite; }

let id_n_ = ref 0
let mk_ ?(attrs=[]) ~src view: (_,_,_) t =
  {id=CCRef.incr_then_get id_n_; src; view; attrs; }

let ty_decl ?attrs ~src id ty = mk_ ?attrs ~src (TyDecl (id,ty))
let def ?attrs ~src l = mk_ ?attrs ~src (Def l)
let rewrite_term ?attrs ~src r = mk_ ?attrs ~src (RewriteTerm r)
let rewrite_form ?attrs ~src r = mk_ ?attrs ~src (RewriteForm r)
let data ?attrs ~src l = mk_ ?attrs ~src (Data l)
let assert_ ?attrs ~src c = mk_ ?attrs ~src (Assert c)
let lemma ?attrs ~src l = mk_ ?attrs ~src (Lemma l)
let goal ?attrs ~src c = mk_ ?attrs ~src (Goal c)
let neg_goal ?attrs ~src ~skolems l = mk_ ?attrs ~src (NegatedGoal (skolems, l))

let map_data ~ty:fty d =
  { d with
      data_args = List.map (Var.update_ty ~f:fty) d.data_args;
      data_ty = fty d.data_ty;
      data_cstors = List.map (fun (id,ty) -> id, fty ty) d.data_cstors;
  }

let map_def ~form:fform ~term:fterm ~ty:fty d =
  { d with
      def_ty=fty d.def_ty;
      def_rules=
        List.map
          (function
            | Def_term (vars,id,ty,args,rhs) ->
              let vars = List.map (Var.update_ty ~f:fty) vars in
              Def_term (vars, id, fty ty, List.map fterm args, fterm rhs)
            | Def_form (vars,lhs,rhs) ->
              let vars = List.map (Var.update_ty ~f:fty) vars in
              Def_form (vars, SLiteral.map ~f:fterm lhs, List.map fform rhs))
          d.def_rules;
  }

let map ~form ~term ~ty st =
  let map_view ~form ~term ~ty:fty = function
    | Def l ->
      let l = List.map (map_def ~form ~term ~ty) l in
      Def l
    | RewriteTerm (vars, id, ty, args, rhs) ->
      let vars = List.map (Var.update_ty ~f:fty) vars in
      RewriteTerm (vars, id, fty ty, List.map term args, term rhs)
    | RewriteForm (vars,lhs,rhs) ->
      let vars = List.map (Var.update_ty ~f:fty) vars in
      RewriteForm (vars, SLiteral.map ~f:term lhs, List.map form rhs)
    | Data l ->
      let l = List.map (map_data ~ty:fty) l in
      Data l
    | Lemma l -> Lemma (List.map form l)
    | Goal f -> Goal (form f)
    | NegatedGoal (sk,l) ->
      let sk = List.map (fun (i,ty)->i, fty ty) sk in
      NegatedGoal (sk,List.map form l)
    | Assert f -> Assert (form f)
    | TyDecl (id, ty) -> TyDecl (id, fty ty)
  in
  {st with view = map_view ~form ~term ~ty st.view; }

(** {2 Statement Source} *)

module Src = struct
  type t = source

  let file x = x.file
  let name x = x.name
  let loc x = x.loc

  let equal a b = a.src_id = b.src_id
  let hash a = a.src_id
  let view a = a.src_view

  let mk_ =
    let n = ref 0 in
    fun src_view -> {src_view; src_id=CCRef.get_then_incr n}

  let from_input attrs r : t = mk_ (Input (attrs, r))
  let from_file ?loc ?name file r : t = mk_ (From_file ({ name; loc; file; }, r))
  let internal r : t = mk_ (Internal r)
  let neg x : t = mk_ (Neg x)
  let cnf x : t = mk_ (CNF x)
  let renaming x id f : t = mk_ (Renaming (x, id, f))
  let preprocess x str : t = mk_ (Preprocess (x,str))

  let neg_input f src = neg (Sourced_input f, src)
  let neg_clause c src = neg (Sourced_clause c, src)

  let cnf_input f src = cnf (Sourced_input f, src)
  let cnf_clause c src = cnf (Sourced_clause c, src)

  let renaming_input input id f =
    renaming (Sourced_statement input, input.src) id f
  let preprocess_input input str =
    preprocess (Sourced_statement input, input.src) str

  let pp_from_file out x =
    let pp_name out = function
      | None -> ()
      | Some n -> Format.fprintf out "at %s " n
    in
    Format.fprintf out "@[<2>%ain@ `%s`@,%a@]"
      pp_name x.name x.file ParseLocation.pp_opt x.loc

  let pp_role out = function
    | R_decl -> CCFormat.string out "decl"
    | R_assert -> CCFormat.string out "assert"
    | R_goal -> CCFormat.string out "goal"
    | R_def -> CCFormat.string out "def"

  let rec pp_tstp out src = match view src with
    | Internal _
    | Input _ -> ()
    | From_file (src,_) ->
      let file = src.file in
      begin match src.name with
        | None -> Format.fprintf out "file('%s')" file
        | Some name -> Format.fprintf out "file('%s', '%s')" file name
      end
    | Neg (_,src') ->
      Format.fprintf out "inference(@['negate_goal',@ [status(thm)],@ [%a]@])"
        pp_tstp src'
    | CNF (_,src') ->
      Format.fprintf out "inference(@['clausify',@ [status(esa)],@ [%a]@])"
        pp_tstp src'
    | Preprocess ((_,src'),msg) ->
      Format.fprintf out
        "inference(@['%s',@ [status(esa)],@ [%a]@])" msg pp_tstp src'
    | Renaming ((_,src'), id, form) ->
      Format.fprintf out
        "inference(@['renaming',@ [status(esa)],@ [%a],@ on(@[%a<=>%a@])@])"
        pp_tstp src' ID.pp id TypedSTerm.TPTP.pp form

  let rec pp out src = match view src with
    | Internal _
    | Input _ -> ()
    | From_file (src,_) ->
      let file = src.file in
      begin match src.name with
        | None -> Format.fprintf out "'%s'" file
        | Some name -> Format.fprintf out "'%s' in '%s'" name file
      end
    | Neg (_,src') ->
      Format.fprintf out "(@[neg@ %a@])" pp src'
    | CNF (_,src') ->
      Format.fprintf out "(@[CNF@ %a@])" pp src'
    | Renaming ((_,src'), id, form) ->
      Format.fprintf out "(@[renaming@ [%a]@ :name %a@ :on @[%a@]@])"
        pp src' ID.pp id TypedSTerm.pp form
    | Preprocess ((_,src'),msg) ->
      Format.fprintf out "(@[preprocess@ [%a]@ :msg %S@])" pp src' msg
end

(** {2 Defined Constants} *)

type definition = Rewrite.rule_set

let as_defined_cst id = match ID.payload id with
  | Rewrite.Payload_defined_cst c ->
    Some (Rewrite.Defined_cst.level c, Rewrite.Defined_cst.rules c)
  | _ -> None

let as_defined_cst_level id = CCOpt.map fst @@ as_defined_cst id

let is_defined_cst id = as_defined_cst id <> None

let declare_defined_cst id ~level (rules:definition) : unit =
  let _ = Rewrite.Defined_cst.declare ~level id rules in
  ()

let conv_term_rule (r:_ term_rule): Rewrite.Term.rule =
  let _, id, ty, args, rhs = r in
  Rewrite.Term.Rule.make id ty args rhs

(* returns either a term or a lit rule (depending on whether RHS is atomic) *)
let conv_lit_rule (r:_ form_rule): Rewrite.rule =
  let _, lhs, rhs = r in
  let lhs = Literal.Conv.of_form lhs in
  let rhs = List.map (List.map Literal.Conv.of_form) rhs in
  Rewrite.Rule.make_lit lhs rhs

(* convert rules *)
let conv_rules (l:_ def_rule list): definition =
  assert (l <> []);
  List.map
    (function
      | Def_term r -> Rewrite.Rule.of_term (conv_term_rule r)
      | Def_form r -> conv_lit_rule r)
    l
  |> Rewrite.Rule_set.of_list

let terms_of_rule (d:_ def_rule): _ Sequence.t = match d with
  | Def_term (_, _, _, args, rhs) ->
    Sequence.of_list (rhs::args)
  | Def_form (_, lhs, rhs) ->
    Sequence.cons lhs (Sequence.of_list rhs |> Sequence.flat_map Sequence.of_list)
    |> Sequence.flat_map SLiteral.to_seq

let level_of_rule (d:_ def_rule): int =
  terms_of_rule d
  |> Sequence.flat_map FOTerm.Seq.symbols
  |> Sequence.filter_map as_defined_cst_level
  |> Sequence.max
  |> CCOpt.get_or ~default:0

let max_exn seq =
  seq
  |> Sequence.max
  |> CCOpt.get_lazy (fun () -> assert false)

let scan_stmt_for_defined_cst (st:(clause,FOTerm.t,Type.t) t): unit = match view st with
  | Def [] -> assert false
  | Def l ->
    (* define all IDs at the same level (the max of those computed) *)
    let ids_and_levels =
      l
      |> List.filter
        (fun {def_ty=ty; def_rewrite=b; _} ->
           (* definitions require [b=true] or the LHS be a constant *)
           let _, args, _ = Type.open_poly_fun ty in
           b || CCList.is_empty args)
      |> List.map
        (fun {def_id; def_rules; _} ->
           let lev =
             Sequence.of_list def_rules
             |> Sequence.map level_of_rule
             |> max_exn
           and def =
             conv_rules def_rules
           in
           def_id, lev, def)
    in
    let level =
      Sequence.of_list ids_and_levels
      |> Sequence.map (fun (_,l,_) -> l)
      |> max_exn
      |> succ
    in
    List.iter
      (fun (id,_,def) ->
         let _ = Rewrite.Defined_cst.declare ~level id def in
         ())
      ids_and_levels
  | RewriteTerm rule ->
    (* declare the rule, possibly making its head defined *)
    let r = conv_term_rule rule in
    let id = Rewrite.Term.Rule.head_id r in
    Rewrite.Defined_cst.declare_or_add id (Rewrite.T_rule r)
  | RewriteForm r ->
    let r = conv_lit_rule r in
    begin match r with
      | Rewrite.T_rule tr ->
        let id = Rewrite.Term.Rule.head_id tr in
        Rewrite.Defined_cst.declare_or_add id r
      | Rewrite.L_rule lr ->
        begin match Rewrite.Lit.Rule.head_id lr with
          | Some id ->
            Rewrite.Defined_cst.declare_or_add id r
          | None ->
            assert (Rewrite.Lit.Rule.is_equational lr);
            Rewrite.Defined_cst.add_eq_rule lr
        end
    end
  | _ -> ()

(** {2 Inductive Types} *)

let scan_stmt_for_ind_ty st = match view st with
  | Data l ->
    List.iter
      (fun d ->
         let ty_vars =
           List.mapi (fun i v -> HVar.make ~ty:(Var.ty v) i) d.data_args
         and cstors =
           List.map (fun (c,ty) -> {Ind_ty.cstor_name=c; cstor_ty=ty;}) d.data_cstors
         in
         let _ = Ind_ty.declare_ty d.data_id ~ty_vars cstors in
         ())
      l
  | _ -> ()

let scan_simple_stmt_for_ind_ty st = match view st with
  | Data l ->
    let conv = Type.Conv.create() in
    let conv_ty = Type.Conv.of_simple_term_exn conv in
    List.iter
      (fun d ->
         let ty_vars =
           List.mapi (fun i v -> HVar.make ~ty:(Var.ty v |> conv_ty) i) d.data_args
         and cstors =
           List.map (fun (c,ty) -> {Ind_ty.cstor_name=c; cstor_ty=conv_ty ty;}) d.data_cstors
         in
         let _ = Ind_ty.declare_ty d.data_id ~ty_vars cstors in
         ())
      l
  | _ -> ()

(** {2 Iterators} *)

module Seq = struct
  let mk_term t = `Term t
  let mk_form f = `Form f

  let seq_of_rule (d:_ def_rule): _ Sequence.t = fun k -> match d with
    | Def_term (vars, _, ty, args, rhs) ->
      k (`Ty ty);
      List.iter (fun v->k (`Ty (Var.ty v))) vars;
      List.iter (fun t->k (`Term t)) (rhs::args);
    | Def_form (vars, lhs, rhs) ->
      List.iter (fun v->k (`Ty (Var.ty v))) vars;
      SLiteral.to_seq lhs |> Sequence.map mk_term |> Sequence.iter k;
      Sequence.of_list rhs |> Sequence.map mk_form |> Sequence.iter k

  let to_seq st k =
    let decl id ty = k (`ID id); k (`Ty ty) in
    match view st with
      | TyDecl (id,ty) -> decl id ty;
      | Def l ->
        List.iter
          (fun {def_id; def_ty; def_rules; _} ->
             decl def_id def_ty;
             Sequence.of_list def_rules
             |> Sequence.flat_map seq_of_rule |> Sequence.iter k)
          l
      | RewriteTerm (_,_,ty,args,rhs) ->
        k (`Ty ty);
        List.iter (fun t -> k (`Term t)) args;
        k (`Term rhs)
      | RewriteForm (_,lhs,rhs) ->
        SLiteral.iter ~f:(fun t -> k (`Term t)) lhs;
        List.iter (fun f -> k (`Form f)) rhs
      | Data l ->
        List.iter
          (fun d ->
             decl d.data_id d.data_ty;
             List.iter (CCFun.uncurry decl) d.data_cstors)
          l
      | Lemma l -> List.iter (fun f -> k (`Form f)) l
      | Assert f
      | Goal f -> k (`Form f)
      | NegatedGoal (_,l) -> List.iter (fun f -> k (`Form f)) l

  let ty_decls st k = match view st with
    | Def l ->
      List.iter
        (fun {def_id; def_ty; _} -> k (def_id, def_ty))
        l
    | TyDecl (id, ty) -> k (id,ty)
    | Data l ->
      List.iter
        (fun d ->
           k (d.data_id, d.data_ty);
           List.iter k d.data_cstors)
        l
    | RewriteTerm _
    | RewriteForm _
    | Lemma _
    | Goal _
    | NegatedGoal _
    | Assert _ -> ()

  let forms st k = match view st with
    | Def _
    | RewriteTerm _
    | Data _
    | TyDecl _ -> ()
    | Goal c -> k c
    | RewriteForm (_,_, _) -> ()
    | Lemma l
    | NegatedGoal (_, l) -> List.iter k l
    | Assert c -> k c

  let lits st = forms st |> Sequence.flat_map Sequence.of_list

  let terms st = lits st |> Sequence.flat_map SLiteral.to_seq

  let symbols st =
    to_seq st
    |> Sequence.flat_map
      (function
        | `ID id -> Sequence.return id
        | `Form f ->
          Sequence.of_list f
          |> Sequence.flat_map SLiteral.to_seq
          |> Sequence.flat_map FOTerm.Seq.symbols
        | `Term t -> FOTerm.Seq.symbols t
        | `Ty ty -> Type.Seq.symbols ty)
end

let signature ?(init=Signature.empty) seq =
  seq
  |> Sequence.flat_map Seq.ty_decls
  |> Sequence.fold (fun sigma (id,ty) -> Signature.declare sigma id ty) init

let add_src ~file st = match st.src.src_view with
  | Input (attrs,r) ->
    let module A = UntypedAST in
    let attrs =
      CCList.filter_map
        (function A.A_AC -> Some A_AC | A.A_name _ -> None)
        attrs
    and name =
      CCList.find_map
        (function A.A_name n-> Some n | _ -> None)
        attrs
    in
    { st with
        src=Src.from_file ?name file r;
        attrs;
    }
  | _ -> st

(** {2 IO} *)

let fpf = Format.fprintf

let pp_attr out = function
  | A_AC -> fpf out "AC"

let pp_attrs out = function
  | [] -> ()
  | l -> fpf out "@ [@[%a@]]" (Util.pp_list ~sep:"," pp_attr) l

let pp_typedvar ppty out v = fpf out "(%a:%a)" Var.pp v ppty (Var.ty v)
let pp_typedvar_l ppty = Util.pp_list ~sep:" " (pp_typedvar ppty)

let pp_def_rule ppf ppt ppty out d =
  let pp_arg = CCFormat.within "(" ")" ppt in
  let pp_args out = function
    | [] -> ()
    | l -> fpf out "@ %a" (Util.pp_list ~sep:" " pp_arg) l
  and pp_vars out = function
    | [] -> ()
    | l -> fpf out "forall %a.@ " (pp_typedvar_l ppty) l
  in
  begin match d with
    | Def_term (vars,id,_,args,rhs) ->
      fpf out "@[<2>%a@[<2>%a%a@] =@ %a@]"
        pp_vars vars ID.pp id pp_args args ppt rhs
    | Def_form (vars,lhs,rhs) ->
      fpf out "@[<2>%a%a =@ (@[<hv>%a@])@]"
        pp_vars vars
        (SLiteral.pp ppt) lhs
        (Util.pp_list ~sep:" && " ppf) rhs
  end

let pp_def ppf ppt ppty out d =
  fpf out "@[<2>@[%a : %a@]@ where@ @[<hv>%a@]@]"
    ID.pp d.def_id ppty d.def_ty
    (Util.pp_list ~sep:";" (pp_def_rule ppf ppt ppty)) d.def_rules

let pp ppf ppt ppty out st = match st.view with
  | TyDecl (id,ty) ->
    fpf out "@[<2>val%a %a :@ @[%a@]@]." pp_attrs st.attrs ID.pp id ppty ty
  | Def l ->
    fpf out "@[<2>def%a %a@]."
      pp_attrs st.attrs (Util.pp_list ~sep:" and " (pp_def ppf ppt ppty)) l
  | RewriteTerm (_, id, _, args, rhs) ->
    fpf out "@[<2>rewrite%a @[%a %a@]@ = @[%a@]@]" pp_attrs st.attrs
      ID.pp id (Util.pp_list ~sep:" " ppt) args ppt rhs
  | RewriteForm (_, lhs, rhs) ->
    fpf out "@[<2>rewrite%a @[%a@]@ <=> @[%a@]@]" pp_attrs st.attrs
      (SLiteral.pp ppt) lhs (Util.pp_list ~sep:" && " ppf) rhs
  | Data l ->
    let pp_cstor out (id,ty) =
      fpf out "@[<2>| %a :@ @[%a@]@]" ID.pp id ppty ty in
    let pp_data out d =
      fpf out "@[<hv2>@[%a : %a@] :=@ %a@]"
        ID.pp d.data_id ppty d.data_ty (Util.pp_list ~sep:"" pp_cstor) d.data_cstors
    in
    fpf out "@[<hv2>data%a@ %a@]" pp_attrs st.attrs (Util.pp_list ~sep:" and " pp_data) l
  | Assert f ->
    fpf out "@[<2>assert%a@ @[%a@]@]." pp_attrs st.attrs ppf f
  | Lemma l ->
    fpf out "@[<2>lemma%a@ @[%a@]@]."
      pp_attrs st.attrs (Util.pp_list ~sep:" && " ppf) l
  | Goal f ->
    fpf out "@[<2>goal%a@ @[%a@]@]." pp_attrs st.attrs ppf f
  | NegatedGoal (sk, l) ->
    let pp_sk out (id,ty) = fpf out "(%a:%a)" ID.pp id ppty ty in
    fpf out "@[<hv2>negated_goal%a@ @[<hv>%a@]@ # skolems: [@[<hv>%a@]]@]."
      pp_attrs st.attrs
      (Util.pp_list ~sep:", " (CCFormat.hovbox ppf)) l
      (Util.pp_list pp_sk) sk

let to_string ppf ppt ppty = CCFormat.to_string (pp ppf ppt ppty)

let pp_clause =
  pp (Util.pp_list ~sep:" ∨ " (SLiteral.pp FOTerm.pp)) FOTerm.pp Type.pp

let pp_input = pp TypedSTerm.pp TypedSTerm.pp TypedSTerm.pp

module TPTP = struct
  let pp ppf ppt ppty out st =
    let name = match st.src.src_view with
      | From_file (f,_) -> CCOpt.get_or ~default:"no_name" (Src.name f)
      | _ -> "no_name"
    in
    let pp_decl out (id,ty) =
      fpf out "@[<2>tff(%s, type,@ %a :@ @[%a@])@]." name ID.pp id ppty ty
    and pp_quant_vars out = function
      | [] -> ()
      | l ->
        let pp_typedvar out v =
          fpf out "%a:%a" Var.pp v ppty (Var.ty v)
        in
        fpf out "@[<2>![@[%a@]]:@ " (Util.pp_list pp_typedvar) l
    in
    (* print a single definition as an axiom *)
    let pp_def_axiom out d =
      let pp_args out = function
        | [] -> ()
        | l -> fpf out "(@[%a@])" (Util.pp_list ~sep:"," ppt) l
      in
      let pp_rule out = function
        | Def_term (vars,id,_,args,rhs) ->
          fpf out "%a(@[%a%a@] =@ %a)" pp_quant_vars vars ID.pp id pp_args args ppt rhs
        | Def_form (vars,lhs,rhs) ->
          fpf out "%a(@[%a@] <=>@ (@[<hv>%a@]))" pp_quant_vars vars (SLiteral.pp ppt) lhs
            (Util.pp_list ~sep:" & " ppf) rhs
      in
      let pp_top_rule out r =
        fpf out "@[<2>tff(%s, axiom,@ %a)@].@," name pp_rule r
      in
      fpf out "@[<hv>%a@]" (Util.pp_list ~sep:"" pp_top_rule) d.def_rules
    in
    match st.view with
      | TyDecl (id,ty) -> pp_decl out (id,ty)
      | Assert f ->
        let role = "axiom" in
        fpf out "@[<2>tff(%s, %s,@ (@[%a@]))@]." name role ppf f
      | Lemma l ->
        let role = "lemma" in
        fpf out "@[<2>tff(%s, %s,@ (@[%a@]))@]." name role
          (Util.pp_list ~sep:" & " ppf) l
      | Goal f ->
        let role = "conjecture" in
        fpf out "@[<2>tff(%s, %s,@ (@[%a@]))@]." name role ppf f
      | NegatedGoal (_,l) ->
        let role = "negated_conjecture" in
        List.iter
          (fun f ->
             fpf out "@[<2>tff(%s, %s,@ (@[%a@]))@]." name role ppf f)
          l
      | Def l ->
        (* declare *)
        List.iter
          (fun {def_id; def_ty; _} -> pp_decl out (def_id,def_ty))
          l;
        (* define *)
        List.iter (pp_def_axiom out) l
      | RewriteTerm (_, id, _, args, rhs) ->
        fpf out "@[<2>tff(%s, axiom,@ %a(%a) =@ @[%a@])@]."
          name ID.pp id (Util.pp_list ~sep:", " ppt) args ppt rhs
      | RewriteForm (_, lhs, rhs) ->
        fpf out "@[<2>tff(%s, axiom,@ %a <=>@ (@[%a@]))@]."
          name (SLiteral.TPTP.pp ppt) lhs (Util.pp_list ~sep:" & " ppf) rhs
      | Data _ -> failwith "cannot print `data` to TPTP"

  let to_string ppf ppt ppty = CCFormat.to_string (pp ppf ppt ppty)
end

