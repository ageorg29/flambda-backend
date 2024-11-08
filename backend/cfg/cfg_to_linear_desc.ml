open Cfg_intf.S

let from_basic (basic : basic) : Linear.instruction_desc =
  match basic with
  | Prologue -> Lprologue
  | Reloadretaddr -> Lreloadretaddr
  | Pushtrap { lbl_handler } -> Lpushtrap { lbl_handler }
  | Poptrap -> Lpoptrap
  | Stack_check { max_frame_size_bytes } -> Lstackcheck { max_frame_size_bytes }
  | Op op ->
    let op : Mach.operation =
      match op with
      | Move -> Imove
      | Spill -> Ispill
      | Reload -> Ireload
      | Const_int n -> Iconst_int n
      | Const_float32 n -> Iconst_float32 n
      | Const_float n -> Iconst_float n
      | Const_symbol n -> Iconst_symbol n
      | Const_vec128 bits -> Iconst_vec128 bits
      | Stackoffset n -> Istackoffset n
      | Load { memory_chunk; addressing_mode; mutability; is_atomic } ->
        Iload
          { memory_chunk;
            addressing_mode;
            mutability = Simple_operation.to_ast_mutable_flag mutability;
            is_atomic
          }
      | Store (c, m, b) -> Istore (c, m, b)
      | Intop op -> Iintop op
      | Intop_imm (op, i) -> Iintop_imm (op, i)
      | Intop_atomic { op; size; addr } -> Iintop_atomic { op; size; addr }
      | Floatop (w, op) -> Ifloatop (w, op)
      | Csel c -> Icsel c
      | Reinterpret_cast cast -> Ireinterpret_cast cast
      | Static_cast cast -> Istatic_cast cast
      | Probe_is_enabled { name } -> Iprobe_is_enabled { name }
      | Opaque -> Iopaque
      | Specific op -> Ispecific op
      | Begin_region -> Ibeginregion
      | End_region -> Iendregion
      | Name_for_debugger
          { ident; which_parameter; provenance; is_assignment; regs } ->
        Iname_for_debugger
          { ident; which_parameter; provenance; is_assignment; regs }
      | Dls_get -> Idls_get
      | Poll -> Ipoll { return_label = None }
      | Alloc { bytes; dbginfo; mode } -> Ialloc { bytes; dbginfo; mode }
    in
    Lop op
