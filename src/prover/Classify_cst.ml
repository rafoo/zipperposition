
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Classification of Constants} *)

open Logtk

type res =
  | Ty of Ind_ty.t
  | Cstor of Ind_ty.constructor * Ind_ty.t
  | Inductive_cst of Ind_cst.t option
  | Projector of ID.t (** projector of some constructor (id: type) *)
  | DefinedCst of int * Statement.definition
  | Other

let classify id = match ID.payload id with
  | Ind_ty.Payload_ind_cstor (c,t) -> Cstor (c,t)
  | Ind_ty.Payload_ind_type x -> Ty x
  | Skolem.Attr_skolem Skolem.K_ind -> Inductive_cst None
  | Ind_cst.Payload_cst c -> Inductive_cst (Some c)
  | Ind_ty.Payload_ind_projector id -> Projector id
  | Rewrite.Payload_defined_cst cst ->
    DefinedCst (Rewrite.Defined_cst.level cst, Rewrite.Defined_cst.rules cst)
  | _ -> Other

let id_is_cstor id = match classify id with Cstor _ -> true | _ -> false
let id_is_projector id = match classify id with Projector _ -> true | _ -> false
let id_is_defined id = match classify id with DefinedCst _ -> true | _ -> false

let pp_res out = function
  | Ty _ -> Format.fprintf out "ind_ty"
  | Cstor (_, ity) -> Format.fprintf out "cstor of %a" Ind_ty.pp ity
  | Inductive_cst _ -> Format.fprintf out "ind_cst"
  | Projector id -> Format.fprintf out "projector_%a" ID.pp id
  | DefinedCst (lev,_) -> Format.fprintf out "defined (level %d)" lev
  | Other -> CCFormat.string out "other"

let pp_signature out sigma =
  let pp_pair out (id,ty) =
    Format.fprintf out "(@[%a : %a (%a)@])" ID.pp id Type.pp ty pp_res (classify id)
  in
  Format.fprintf out
    "{@[<hv>%a@]}" (Util.pp_list ~sep:"," pp_pair) (Signature.to_list sigma)

let dominates_ opt_c opt_sub =
  CCOpt.(get_or ~default:false (map2 Ind_cst.dominates opt_c opt_sub))

let prec_constr_ a b =
  let to_int_ = function
    | Ty _ -> 0
    | Projector _ -> 1
    | Cstor _ -> 2
    | Inductive_cst _ -> 3
    | Other -> 4
    | DefinedCst _ -> 5 (* defined: biggest *)
  in
  let c_a = classify a in
  let c_b = classify b in
  match c_a, c_b with
    | Ty _, Ty _
    | Cstor _, Cstor _
    | Projector _, Projector _
    | Other, Other -> 0
    | Inductive_cst c1, Inductive_cst c2 ->
      (* Inductive_cst cases should be compared by "sub-case" order (i.e. `x
         sub-cst-of y` means `x < y`); this is a stable ordering. *)
      if dominates_ c1 c2 then 1
      else if dominates_ c2 c1 then -1
      else 0
    | DefinedCst (l1,_), DefinedCst (l2,_) ->
      (* bigger level means defined later *)
      CCInt.compare l1 l2
    | Ty _, _
    | Cstor _, _
    | Inductive_cst _, _
    | Projector _, _
    | DefinedCst _, _
    | Other, _ -> CCInt.compare (to_int_ c_a) (to_int_ c_b)

let prec_constr = Precedence.Constr.make prec_constr_

let weight_fun (id:ID.t): Precedence.Weight.t =
  let module W = Precedence.Weight in
  begin match classify id with
    | Ty _ -> W.int 1
    | Projector _ -> W.int 1
    | Cstor _ -> W.int 1
    | Inductive_cst _ -> W.int 2
    | Other -> W.omega_plus 4
    | DefinedCst _ -> W.omega_plus 5 (* defined: biggest *)
  end
