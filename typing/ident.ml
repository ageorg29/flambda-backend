(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           *)
(*                                                                        *)
(*   Copyright 1996 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

open Local_store

let lowest_scope  = 0
let highest_scope = 100000000

type t =
  | Local of { name: string; stamp: int }
  | Scoped of { name: string; stamp: int; scope: int }
  | Global of string
      (* separate from [Global_with_args] for efficiency *)
  | Predef of { name: string; stamp: int }
      (* the stamp is here only for fast comparison, but the name of
         predefined identifiers is always unique. *)
  | Global_with_args of global
      (* must have non-empty [args] *)
and global = Global_module.Name.t = private
  { head: string; args: Global_module.Name.argument list }

(* A stamp of 0 denotes a persistent identifier *)

let currentstamp = s_ref 0
let predefstamp = s_ref 0

let create_scoped ~scope s =
  incr currentstamp;
  Scoped { name = s; stamp = !currentstamp; scope }

let create_local s =
  incr currentstamp;
  Local { name = s; stamp = !currentstamp }

let create_predef s =
  incr predefstamp;
  Predef { name = s; stamp = !predefstamp }

let create_persistent s =
  Global s

let create_global glob =
  match glob with
  | { head; args = [] } -> Global head
  | _ -> Global_with_args glob

let create_local_binding_for_global glob =
  create_local (Global_module.Name.to_string glob)

let create_instance head args =
  create_global (Global_module.Name.create_exn head args)

let global_name g = Global_module.Name.to_string g

let name = function
  | Local { name; _ }
  | Scoped { name; _ }
  | Global name
  | Predef { name; _ } -> name
  | Global_with_args g -> global_name g

let rename = function
  | Local { name; stamp = _ }
  | Scoped { name; stamp = _; scope = _ } ->
      incr currentstamp;
      Local { name; stamp = !currentstamp }
  | id ->
      Misc.fatal_errorf "Ident.rename %s" (name id)

let unique_name = function
  | Local { name; stamp }
  | Scoped { name; stamp } -> name ^ "_" ^ Int.to_string stamp
  | Global name ->
      (* we're adding a fake stamp, because someone could have named his unit
         [Foo_123] and since we're using unique_name to produce symbol names,
         we might clash with an ident [Local { "Foo"; 123 }]. *)
      name ^ "_0"
  | Predef { name; _ } ->
      (* we know that none of the predef names (currently) finishes in
         "_<some number>", and that their name is unique. *)
      name
  | Global_with_args g -> global_name g

let unique_toplevel_name = function
  | Local { name; stamp }
  | Scoped { name; stamp } -> name ^ "/" ^ Int.to_string stamp
  | Global name
  | Predef { name; _ } -> name
  | Global_with_args g -> global_name g

let equal i1 i2 =
  match i1, i2 with
  | Local { name = name1; _ }, Local { name = name2; _ }
  | Scoped { name = name1; _ }, Scoped { name = name2; _ }
  | Global name1, Global name2 ->
      name1 = name2
  | Predef { stamp = s1; _ }, Predef { stamp = s2 } ->
      (* if they don't have the same stamp, they don't have the same name *)
      s1 = s2
  | Global_with_args g1, Global_with_args g2 -> Global_module.Name.equal g1 g2
  | _ ->
      false

let same i1 i2 =
  match i1, i2 with
  | Local { stamp = s1; _ }, Local { stamp = s2; _ }
  | Scoped { stamp = s1; _ }, Scoped { stamp = s2; _ }
  | Predef { stamp = s1; _ }, Predef { stamp = s2 } ->
      s1 = s2
  | Global name1, Global name2 ->
      name1 = name2
  | Global_with_args g1, Global_with_args g2 -> Global_module.Name.equal g1 g2
  | _ ->
      false

let stamp = function
  | Local { stamp; _ }
  | Scoped { stamp; _ } -> stamp
  | _ -> 0

let scope = function
  | Scoped { scope; _ } -> scope
  | Local _ -> highest_scope
  | Global _ | Predef _ | Global_with_args _ -> lowest_scope

let reinit_level = ref (-1)

let reinit () =
  if !reinit_level < 0
  then reinit_level := !currentstamp
  else currentstamp := !reinit_level

let is_global = function
  | Global _ -> true
  | Global_with_args _ -> true
  | _ -> false

let is_global_or_predef = function
  | Local _
  | Scoped _ -> false
  | Global _
  | Predef _
  | Global_with_args _ -> true

let is_predef = function
  | Predef _ -> true
  | _ -> false

let is_instance = function
  | Global_with_args _ -> true
  | _ -> false

let to_global = function
  | Global head -> Some (Global_module.Name.create_no_args head)
  | Global_with_args g -> Some g
  | _ -> None

let print ~with_scope ppf =
  let open Format in
  function
  | Global name -> fprintf ppf "%s!" name
  | Predef { name; stamp = n } ->
      fprintf ppf "%s%s!" name
        (if !Clflags.unique_ids then sprintf "/%i" n else "")
  | Local { name; stamp = n } ->
      fprintf ppf "%s%s" name
        (if !Clflags.unique_ids then sprintf "/%i" n else "")
  | Scoped { name; stamp = n; scope } ->
      fprintf ppf "%s%s%s" name
        (if !Clflags.unique_ids then sprintf "/%i" n else "")
        (if with_scope then sprintf "[%i]" scope else "")
  | Global_with_args g ->
      fprintf ppf "%a!" Global_module.Name.print g

let print_with_scope ppf id = print ~with_scope:true ppf id

let print ppf id = print ~with_scope:false ppf id

let to_global_exn id =
  match to_global id with
  | Some global -> global
  | None -> Misc.fatal_errorf "Not global: %a" print id

(* For the documentation of ['a Ident.tbl], see ident.mli.

   The implementation is a copy-paste specialization of
   a balanced-tree implementation similar to Map.
     ['a tbl]
   is a slightly more compact version of
     [(Ident.t * 'a) list Map.Make(String)]

   This implementation comes from Caml Light where duplication was
   unavoidable in absence of functors. It works well enough, and so
   far we have not had strong incentives to do the deduplication work
   (implementation, tests, benchmarks, etc.).
*)
type 'a tbl =
    Empty
  | Node of 'a tbl * 'a data * 'a tbl * int

and 'a data =
  { ident: t;
    data: 'a;
    previous: 'a data option }

let empty = Empty

(* Inline expansion of height for better speed
 * let height = function
 *     Empty -> 0
 *   | Node(_,_,_,h) -> h
 *)

let mknode l d r =
  let hl = match l with Empty -> 0 | Node(_,_,_,h) -> h
  and hr = match r with Empty -> 0 | Node(_,_,_,h) -> h in
  Node(l, d, r, (if hl >= hr then hl + 1 else hr + 1))

let balance l d r =
  let hl = match l with Empty -> 0 | Node(_,_,_,h) -> h
  and hr = match r with Empty -> 0 | Node(_,_,_,h) -> h in
  if hl > hr + 1 then
    match l with
    | Node (ll, ld, lr, _)
      when (match ll with Empty -> 0 | Node(_,_,_,h) -> h) >=
           (match lr with Empty -> 0 | Node(_,_,_,h) -> h) ->
        mknode ll ld (mknode lr d r)
    | Node (ll, ld, Node(lrl, lrd, lrr, _), _) ->
        mknode (mknode ll ld lrl) lrd (mknode lrr d r)
    | _ -> assert false
  else if hr > hl + 1 then
    match r with
    | Node (rl, rd, rr, _)
      when (match rr with Empty -> 0 | Node(_,_,_,h) -> h) >=
           (match rl with Empty -> 0 | Node(_,_,_,h) -> h) ->
        mknode (mknode l d rl) rd rr
    | Node (Node (rll, rld, rlr, _), rd, rr, _) ->
        mknode (mknode l d rll) rld (mknode rlr rd rr)
    | _ -> assert false
  else
    mknode l d r

let rec add id data = function
    Empty ->
      Node(Empty, {ident = id; data = data; previous = None}, Empty, 1)
  | Node(l, k, r, h) ->
      let c = String.compare (name id) (name k.ident) in
      if c = 0 then
        Node(l, {ident = id; data = data; previous = Some k}, r, h)
      else if c < 0 then
        balance (add id data l) k r
      else
        balance l k (add id data r)

let rec min_binding = function
    Empty -> raise Not_found
  | Node (Empty, d, _, _) -> d
  | Node (l, _, _, _) -> min_binding l

let rec remove_min_binding = function
    Empty -> invalid_arg "Map.remove_min_elt"
  | Node (Empty, _, r, _) -> r
  | Node (l, d, r, _) -> balance (remove_min_binding l) d r

let merge t1 t2 =
  match (t1, t2) with
    (Empty, t) -> t
  | (t, Empty) -> t
  | (_, _) ->
      let d = min_binding t2 in
      balance t1 d (remove_min_binding t2)

let rec remove id = function
    Empty ->
      Empty
  | (Node (l, k, r, h) as m) ->
      let c = String.compare (name id) (name k.ident) in
      if c = 0 then
        match k.previous with
        | None -> merge l r
        | Some k -> Node (l, k, r, h)
      else if c < 0 then
        let ll = remove id l in if l == ll then m else balance ll k r
      else
        let rr = remove id r in if r == rr then m else balance l k rr

let rec find_previous id = function
    None ->
      raise Not_found
  | Some k ->
      if same id k.ident then k.data else find_previous id k.previous

let rec find_same id = function
    Empty ->
      raise Not_found
  | Node(l, k, r, _) ->
      let c = String.compare (name id) (name k.ident) in
      if c = 0 then
        if same id k.ident
        then k.data
        else find_previous id k.previous
      else
        find_same id (if c < 0 then l else r)

let rec find_name n = function
    Empty ->
      raise Not_found
  | Node(l, k, r, _) ->
      let c = String.compare n (name k.ident) in
      if c = 0 then
        k.ident, k.data
      else
        find_name n (if c < 0 then l else r)

let rec get_all = function
  | None -> []
  | Some k -> (k.ident, k.data) :: get_all k.previous

let rec find_all n = function
    Empty ->
      []
  | Node(l, k, r, _) ->
      let c = String.compare n (name k.ident) in
      if c = 0 then
        (k.ident, k.data) :: get_all k.previous
      else
        find_all n (if c < 0 then l else r)

let get_all_seq k () =
  Seq.unfold (Option.map (fun k -> (k.ident, k.data), k.previous))
    k ()

let rec find_all_seq n tbl () =
  match tbl with
  | Empty -> Seq.Nil
  | Node(l, k, r, _) ->
      let c = String.compare n (name k.ident) in
      if c = 0 then
        Seq.Cons((k.ident, k.data), get_all_seq k.previous)
      else
        find_all_seq n (if c < 0 then l else r) ()


let rec fold_aux f stack accu = function
    Empty ->
      begin match stack with
        [] -> accu
      | a :: l -> fold_aux f l accu a
      end
  | Node(l, k, r, _) ->
      fold_aux f (l :: stack) (f k accu) r

let fold_name f tbl accu = fold_aux (fun k -> f k.ident k.data) [] accu tbl

let rec fold_data f d accu =
  match d with
    None -> accu
  | Some k -> f k.ident k.data (fold_data f k.previous accu)

let fold_all f tbl accu =
  fold_aux (fun k -> fold_data f (Some k)) [] accu tbl

(* let keys tbl = fold_name (fun k _ accu -> k::accu) tbl [] *)

let rec iter f = function
    Empty -> ()
  | Node(l, k, r, _) ->
      iter f l; f k.ident k.data; iter f r

(* Idents for sharing keys *)

(* They should be 'totally fresh' -> neg numbers *)
let key_name = ""

let make_key_generator () =
  let c = ref 1 in
  function
  | Local _
  | Scoped _ ->
      let stamp = !c in
      decr c ;
      Local { name = key_name; stamp = stamp }
  | global_id ->
      Misc.fatal_errorf "Ident.make_key_generator () %s" (name global_id)

let compare x y =
  match x, y with
  | Local x, Local y ->
      let c = x.stamp - y.stamp in
      if c <> 0 then c
      else compare x.name y.name
  | Local _, _ -> 1
  | _, Local _ -> (-1)
  | Scoped x, Scoped y ->
      let c = x.stamp - y.stamp in
      if c <> 0 then c
      else compare x.name y.name
  | Scoped _, _ -> 1
  | _, Scoped _ -> (-1)
  | Global x, Global y -> compare x y
  | Global _, _ -> 1
  | _, Global _ -> (-1)
  | Global_with_args g1, Global_with_args g2 -> Global_module.Name.compare g1 g2
  | Global_with_args _, _ -> 1
  | _, Global_with_args _ -> (-1)
  | Predef { stamp = s1; _ }, Predef { stamp = s2; _ } -> compare s1 s2

let output oc id = output_string oc (unique_name id)
let hash i = (Char.code (name i).[0]) lxor (stamp i)

let original_equal = equal
include Identifiable.Make (struct
  type nonrec t = t
  let compare = compare
  let output = output
  let print = print
  let hash = hash
  let equal = same
end)
let equal = original_equal