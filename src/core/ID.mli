
(* This file is free software, part of Logtk. See file "license" for more details. *)

(** {1 Unique Identifiers}

  An {!ID.t} is a unique identifier (an integer) with a human-readable name.
  We use those to give names to variables that are not hashconsed (the hashconsing
  does not play nice with names)

  @since NEXT_RELEASE *)

type t = private {
  id: int;
  name: string;
}

val make : string -> t
(** Makes a fresh ID *)

val copy : t -> t
(** Copy with a new ID *)

val name : t -> string

include Interfaces.HASH with type t := t
include Interfaces.ORD with type t := t
include Interfaces.PRINT with type t := t

(** NOTE: default printer does not display the {!id} field *)

val pp_full : t CCFormat.printer
(** Prints the ID with its internal number *)

val gensym : unit -> t
(** Generate a new ID with a new, unique name *)

module Map : CCMap.S with type key = t
module Set : CCSet.S with type elt = t
module Tbl : CCHashtbl.S with type key = t


