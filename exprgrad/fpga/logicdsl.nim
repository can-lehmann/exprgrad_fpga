# Copyright 2022 Can Joshua Lehmann
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http:/www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# A dsl for creating logic circuits

import std/[math, tables, sets, hashes]

type LogicKind* = enum
  LogicConst, LogicReg, LogicInput, LogicBitwise,
  LogicConcat, LogicSlice, LogicInstance, LogicRead,
  LogicShl, LogicShr,
  LogicAnd, LogicOr, LogicInvert,
  LogicAdd, LogicSub, LogicMul, LogicNegate,
  LogicEq, LogicLt, LogicLe,
  LogicSelect

const
  LOGIC_GATES = static:
    var gates: set[LogicKind] = {}
    for kind in LogicAnd..high(LogicKind):
      gates.incl(kind)
    gates
  
  LOGIC_TRANSFORM_GATES = {
    LogicBitwise, LogicAnd, LogicOr, LogicInvert,
    LogicAdd, LogicSub, LogicNegate, LogicShl, LogicShr
  }
  
  LOGIC_COND_GATES = {LogicEq, LogicLt, LogicLe}
  
  LOGIC_COMB_GATES = {
    LogicBitwise, LogicInstance,
    LogicConcat, LogicSlice, LogicRead,
    LogicShl, LogicShr,
    LogicAnd, LogicOr, LogicInvert,
    LogicAdd, LogicSub, LogicMul, LogicNegate,
    LogicEq, LogicLt, LogicLe,
    LogicSelect
  }

type BitString* = object
  size*: int
  bytes*: seq[uint8]

proc init*(_: typedesc[BitString], bits: openArray[bool]): BitString =
  var byte_count = bits.len div 8
  if bits.len mod 8 != 0:
    byte_count += 1
  
  result = BitString(
    size: bits.len,
    bytes: new_seq[uint8](byte_count)
  )
  
  for it, bit in bits:
    if bit:
      result.bytes[it div 8] = result.bytes[it div 8] or uint8(1 shl (it mod 8))

proc init*(_: typedesc[BitString], size: int, value: BiggestUint): BitString =
  var byte_count = size div 8
  if size mod 8 != 0:
    byte_count += 1
  result = BitString(size: size, bytes: new_seq[uint8](byte_count))
  for it in 0..<byte_count:
    result.bytes[it] = uint8((value shr (it * 8)) and 0xff)

proc `$`(bit_string: BitString): string =
  result = $bit_string.size & "'b"
  for it in countdown(bit_string.bytes.len - 1, 0):
    for shift in countdown(min(7, bit_string.size - it * 8 - 1), 0):
      result &= ["0", "1"][ord(((bit_string.bytes[it] shr shift) and 1) != 0)]

type
  UpdateEvent* = enum
    RisingEdge, FallingEdge
  
  InputRole* = enum
    InputNone, InputClock, InputReset, InputButtons
  
  Logic* = ref object
    args*: seq[Logic]
    width*: int
    case kind*: LogicKind:
      of LogicConst:
        value*: BitString
      of LogicReg:
        event: UpdateEvent
        reg_name: string
      of LogicInput:
        name*: string
        role*: InputRole
      of LogicBitwise:
        bitwise: seq[bool]
      of LogicSlice:
        slice: HSlice[int, int]
      of LogicGates: discard
      of LogicShl, LogicShr:
        shift: int
      of LogicConcat: discard
      of LogicInstance:
        circuit: Circuit
        output: int
      of LogicRead:
        memory*: Memory
  
  MemoryWrite = object
    cond*: Logic
    index*: Logic
    value*: Logic
  
  Memory* = ref object
    width: int
    shape: seq[int]
    initial: seq[BitString]
    
    clock*: Logic
    event*: UpdateEvent
    writes*: seq[MemoryWrite]
  
  Circuit* = ref object
    name: string
    inputs*: seq[Logic]
    outputs*: seq[(string, Logic)]

proc hash*(logic: Logic): Hash = hash(logic[].addr)
proc `==`*(a, b: Logic): bool = a[].addr == b[].addr

proc hash*(logic: Memory): Hash = hash(logic[].addr)
proc `==`*(a, b: Memory): bool = a[].addr == b[].addr

proc hash*(circuit: Circuit): Hash = hash(circuit[].addr)
proc `==`*(a, b: Circuit): bool = a[].addr == b[].addr

proc constant*(_: typedesc[Logic], bit_string: BitString): Logic =
  result = Logic(kind: LogicConst, width: bit_string.size, value: bit_string)

proc constant*(_: typedesc[Logic], bits: int, value: BiggestUint): Logic =
  result = Logic(kind: LogicConst, width: bits, value: BitString.init(bits, value))

proc constant*(_: typedesc[Logic], value: seq[bool]): Logic =
  result = Logic(kind: LogicConst, width: value.len, value: BitString.init(value))

proc constant*(_: typedesc[Logic], value: bool): Logic =
  result = Logic(kind: LogicConst, width: 1, value: BitString.init([value]))

proc reg*(_: typedesc[Logic],
          width: int,
          initial: Logic = nil,
          name: string = ""): Logic =
  result = Logic(kind: LogicReg,
    width: width,
    reg_name: name,
    args: @[initial, nil, nil]
  )
  if initial.is_nil:
    result.args[0] = Logic.constant(width, 0)

proc input*(_: typedesc[Logic], name: string, width: int = 1, role: InputRole = InputNone): Logic =
  result = Logic(kind: LogicInput, name: name, width: width, role: role)

proc update*(reg, cond: Logic, edge: UpdateEvent, value: Logic) =
  assert reg.kind == LogicReg
  if not reg.args[1].is_nil:
    raise new_exception(ValueError, "Register has multiple drivers")
  reg.args[1] = cond
  reg.args[2] = value
  reg.event = edge

template logic_binop(op: untyped, op_kind: LogicKind) =
  proc op*(a, b: Logic): Logic =
    result = Logic(kind: op_kind, args: @[a, b])

logic_binop(`+`, LogicAdd)
logic_binop(`-`, LogicSub)
logic_binop(`*`, LogicMul)
logic_binop(`and`, LogicAnd)
logic_binop(`or`, LogicOr)
logic_binop(`<=>`, LogicEq)
logic_binop(`<`, LogicLt)
logic_binop(`<=`, LogicLe)

proc `shl`*(a: Logic, b: int): Logic =
  if b == 0:
    return a
  result = Logic(kind: LogicShl, args: @[a], shift: b)

proc `shr`*(a: Logic, b: int): Logic =
  if b == 0:
    return a
  result = Logic(kind: LogicShr, args: @[a], shift: b)

template logic_unop(op: untyped, op_kind: LogicKind) =
  proc op*(a: Logic): Logic =
    result = Logic(kind: op_kind, args: @[a])

logic_unop(`not`, LogicInvert)
logic_unop(`-`, LogicNegate)

proc select*(cond, a, b: Logic): Logic =
  result = Logic(kind: LogicSelect, args: @[cond, a, b])

proc select*(branches: openArray[(Logic, Logic)], otherwise: Logic): Logic =
  result = otherwise
  for it in countdown(branches.len - 1, 0):
    let (cond, value) = branches[it]
    result = select(cond, value, result)

proc select(value: Logic, cases: openArray[(Logic, Logic)], default: Logic): Logic =
  result = default
  for it in countdown(cases.len - 1, 0):
    let (pattern, res) = cases[it]
    result = Logic(kind: LogicSelect, args: @[pattern <=> value, res, result])

proc `[]`*(value: Logic, slice: HSlice[int, int]): Logic =
  result = Logic(kind: LogicSlice, slice: slice, args: @[value])

proc `&`*(a, b: Logic): Logic =
  result = Logic(kind: LogicConcat, args: @[a, b])

proc new*(_: typedesc[Memory],
          width: int,
          shape: openArray[int],
          initial: openArray[BitString] = []): Memory =
  if initial.len > 0:
    if initial.len != shape.prod():
      raise new_exception(ValueError, "Initial memory contents must be the same size as memory")
    for value in initial:
      if value.size != width:
        raise new_exception(ValueError, "Initial memory values must have same width as memory")
  result = Memory(width: width, shape: @shape, initial: @initial)

proc `[]`*(mem: Memory, index: Logic): Logic =
  result = Logic(kind: LogicRead, memory: mem, args: @[index])

proc write*(mem: Memory, clock: Logic, event: UpdateEvent, cond, index, value: Logic) =
  if mem.clock.is_nil:
    mem.clock = clock
    mem.event = event
  elif mem.clock != clock:
    raise new_exception(ValueError, "Memory has multiple drivers")
  mem.writes.add(MemoryWrite(cond: cond, index: index, value: value))

proc instantiate*(circuit: Circuit, args: openArray[Logic], output: int): Logic =
  result = Logic(kind: LogicInstance,
    circuit: circuit,
    args: @args,
    output: output
  )

proc instantiate*(circuit: Circuit, args: openArray[(string, Logic)], output: int): Logic =
  var names = init_table[string, int]()
  for it, input in circuit.inputs:
    names[input.name] = it
  var ordered_args = new_seq[Logic](circuit.inputs.len)
  for (name, value) in args:
    if name notin names:
      raise new_exception(ValueError, name & " is not a input of the circuit")
    let index = names[name]
    if not ordered_args[index].is_nil:
      raise new_exception(ValueError, "Unable to assign multiple values to input " & name)
    ordered_args[index] = value
  result = circuit.instantiate(ordered_args, output)

proc new*(_: typedesc[Circuit],
          inputs: openArray[Logic],
          outputs: openArray[(string, Logic)],
          name: string = ""): Circuit =
  result = Circuit(
    inputs: @inputs,
    outputs: @outputs,
    name: name
  )

proc find_role*(circuit: Circuit, role: InputRole): Logic =
  for input in circuit.inputs:
    if input.role == role:
      return input

proc infer_widths*(circuit: Circuit)
proc infer_width(logic: Logic, closed: var HashSet[Logic]): int

proc infer_widths(mem: Memory, closed: var HashSet[Logic]) =
  if mem.writes.len > 0:
    if mem.clock.infer_width(closed) != 1:
      raise new_exception(ValueError, "Clock signal must have width 1")
  for write in mem.writes:
    if write.cond.infer_width(closed) != 1:
      raise new_exception(ValueError, "Condition must have width 1")
    discard write.index.infer_width(closed)
    if write.value.infer_width(closed) != mem.width:
      raise new_exception(ValueError, "")

proc infer_width(logic: Logic, closed: var HashSet[Logic]): int =
  if logic in closed:
    return logic.width
  case logic.kind:
    of LogicConst, LogicInput:
      if logic.width <= 0:
        raise new_exception(ValueError, $logic.kind & " must have a width > 0.")
    of LogicReg:
      closed.incl(logic)
      let
        expected = [logic.width, 1, logic.width]
        names = ["initial", "condition", "value"]
      for it, arg in logic.args:
        let width = arg.infer_width(closed)
        if width != expected[it]:
          raise new_exception(ValueError, "Width mismatch in register " & names[it] & ", expected width " & $expected[it] & ", but got " & $width)
    of LogicConcat, LogicMul:
      for arg in logic.args:
        logic.width += arg.infer_width(closed)
    of LogicSlice:
      let width = logic.args[0].infer_width(closed)
      if logic.slice.b >= width or logic.slice.a >= width:
        raise new_exception(ValueError, "Slice index out of range")
      logic.width = max(logic.slice.b - logic.slice.a + 1, 0)
    of LogicInstance:
      logic.circuit.infer_widths()
      for it, arg in logic.args:
        let width = arg.infer_width(closed)
        if width != logic.circuit.inputs[it].width:
          raise new_exception(ValueError, "")
      logic.width = logic.circuit.outputs[logic.output][1].width
    of LogicRead:
      logic.width = logic.memory.width
      closed.incl(logic)
      discard logic.args[0].infer_width(closed)
      logic.memory.infer_widths(closed)
    of LOGIC_TRANSFORM_GATES, LOGIC_COND_GATES:
      var arg_width = 0
      for arg in logic.args:
        let width = arg.infer_width(closed)
        if arg_width == 0:
          arg_width = width
        elif arg_width != width:
          raise new_exception(ValueError, "All arguments of " & $logic.kind & " must have the same width.")
      if logic.kind in LOGIC_TRANSFORM_GATES:
        logic.width = arg_width
      else:
        logic.width = 1
    of LogicSelect:
      if logic.args[0].infer_width(closed) != 1:
        echo logic.args[0] in closed
        echo logic.args[0].width
        echo logic.args[0].kind
        raise new_exception(ValueError, "Condition of select must have width 1.")
      logic.width = logic.args[1].infer_width(closed)
      if logic.width != logic.args[2].infer_width(closed):
        raise new_exception(ValueError, "Options of select must have same width.")
  result = logic.width
  closed.incl(logic)

proc infer_widths*(circuit: Circuit) =
  var closed = init_hash_set[Logic]()
  for (name, output) in circuit.outputs:
    discard output.infer_width(closed)

proc find_state(logic: Logic, regs: var HashSet[Logic], mems: var HashSet[Memory]) =
  case logic.kind:
    of LogicReg:
      if logic in regs:
        return
      else:
        regs.incl(logic)
    of LogicRead:
      if logic.memory notin mems:
        mems.incl(logic.memory)
        logic.args[0].find_state(regs, mems)
        if logic.memory.writes.len > 0:
          logic.memory.clock.find_state(regs, mems)
        for write in logic.memory.writes:
          write.cond.find_state(regs, mems)
          write.index.find_state(regs, mems)
          write.value.find_state(regs, mems)
    else: discard
  
  for arg in logic.args:
    arg.find_state(regs, mems)

proc find_state(circuit: Circuit): (HashSet[Logic], HashSet[Memory]) =
  for (name, output) in circuit.outputs:
    output.find_state(result[0], result[1])

proc find_circuits(circuit: Circuit): HashSet[Circuit]

proc find_circuits(logic: Logic, circuits: var HashSet[Circuit], closed: var HashSet[Logic]) =
  if logic notin closed:
    closed.incl(logic)
    for arg in logic.args:
      arg.find_circuits(circuits, closed)
    if logic.kind == LogicInstance:
      circuits = circuits + logic.circuit.find_circuits()

proc find_circuits(circuit: Circuit): HashSet[Circuit] =
  result.incl(circuit)
  var closed = init_hash_set[Logic]()
  for (name, output) in circuit.outputs:
    output.find_circuits(result, closed)

type
  FpgaError* = ref object of IoError
  FpgaPlatform* = ref object of RootObj
  
  Context = object
    source: string
    indent: int
    module_names: Table[Circuit, string]
    value_names: Table[Logic, string]
    memory_names: Table[Memory, string]

method wrap*(platform: FpgaPlatform, circuit: Circuit): Circuit {.base.} = circuit
method build_verilog*(platform: FpgaPlatform, verilog: string): string {.base.} = raise FpgaError(msg: "Not implementd")
method upload_bitstream*(platform: FpgaPlatform, bitstream_path: string) {.base.} = raise FpgaError(msg: "Not implementd")

proc emit_indent(ctx: var Context, width: int = 2) =
  for it in 0..<(ctx.indent * width):
    ctx.source.add(' ')

template with_indent(ctx: var Context, body: untyped) =
  block:
    ctx.indent += 1
    defer: ctx.indent -= 1
    body

proc `[]`(ctx: var Context, circuit: Circuit): string =
  if circuit notin ctx.module_names:
    var name = "mod" & $ctx.module_names.len
    if circuit.name.len > 0:
      name = circuit.name
    ctx.module_names[circuit] = name
  result = ctx.module_names[circuit]

proc `[]`(ctx: var Context, logic: Logic): string =
  if logic notin ctx.value_names:
    var name = "value" & $ctx.value_names.len
    if logic.kind == LogicInput:
      name = logic.name
    elif logic.kind == LogicReg and logic.reg_name.len > 0:
      name &= "_" & logic.reg_name
    elif logic.kind == LogicConst:
      name = $logic.value
    ctx.value_names[logic] = name
  result = ctx.value_names[logic]

proc `[]`(ctx: var Context, memory: Memory): string =
  if memory notin ctx.memory_names:
    ctx.memory_names[memory] = "mem" & $ctx.memory_names.len
  result = ctx.memory_names[memory]

proc declare_values(logic: Logic, closed: var HashSet[Logic], ctx: var Context) =
  if logic in closed or logic.kind notin LOGIC_COMB_GATES:
    return
  closed.incl(logic)
  for arg in logic.args:
    arg.declare_values(closed, ctx)
  ctx.emit_indent()
  ctx.source &= "wire [" & $(logic.width - 1) & ":0] " & ctx[logic] & ";\n"

proc format_operator(logic: Logic, ctx: var Context): string =
  case logic.kind:
    of LogicConcat: 
      result = "{"
      for it in countdown(logic.args.len - 1, 0):
        result &= ctx[logic.args[it]]
        if it != 0:
          result &= ", "
      result &= "}"
    of LogicSlice:
      result = ctx[logic.args[0]] & "[" & $logic.slice.b & ":" & $logic.slice.a & "]"
    of LogicRead:
      result = ctx[logic.memory] & "[" & ctx[logic.args[0]] & "]"
    of LogicAnd, LogicOr, LogicAdd, LogicSub, LogicMul, LogicEq, LogicLt, LogicLe:
      let op = case logic.kind:
        of LogicAnd: "&"
        of LogicOr: "|"
        of LogicAdd: "+"
        of LogicSub: "-"
        of LogicMul: "*"
        of LogicEq: "=="
        of LogicLt: "<"
        of LogicLe: "<="
        else: "<unknown_operator>"
      result = "(" & ctx[logic.args[0]] & " " & op & " " & ctx[logic.args[1]] & ")"
    of LogicShl, LogicShr:
      let op = case logic.kind:
        of LogicShl: "<<"
        of LogicShr: "<<"
        else: "<unknown_shift>"
      result = "(" & ctx[logic.args[0]] & " " & op & " " & $logic.shift & ")"
    of LogicInvert:
      result = "~" & ctx[logic.args[0]]
    of LogicNegate:
      result = "-" & ctx[logic.args[0]]
    of LogicSelect:
      result = "(" & ctx[logic.args[0]] & " ? " & ctx[logic.args[1]] & " : " & ctx[logic.args[2]] & ")"
    else:
      raise new_exception(ValueError, $logic.kind & " is not an operator")

proc emit_combinatorial(logic: Logic, closed: var HashSet[Logic], ctx: var Context) =
  if logic in closed or logic.kind notin LOGIC_COMB_GATES:
    return
  closed.incl(logic)
  for arg in logic.args:
    arg.emit_combinatorial(closed, ctx)
  ctx.emit_indent()
  if logic.kind == LogicInstance:
    let
      name = ctx[logic.circuit]
      inst_name = "__" & name & "_" & ctx[logic]
    ctx.source &= name & " " & inst_name & "("
    for it, arg in logic.args:
      if it != 0:
        ctx.source &= ", "
      ctx.source &= ctx[arg]
    for it, (name, output) in logic.circuit.outputs:
      if it != 0 or logic.args.len > 0:
        ctx.source &= ", "
      if it == logic.output:
        ctx.source &= ctx[logic]
      else:
        raise new_exception(ValueError, "not implemented")
    ctx.source &= ");\n"
  else:
    ctx.source &= "assign " & ctx[logic] & " = " & format_operator(logic, ctx) & ";\n"

proc to_verilog(circuit: Circuit, ctx: var Context) =
  ctx.emit_indent()
  ctx.source &= "module " & ctx[circuit] & "("
  for it, input in circuit.inputs:
    if it != 0:
      ctx.source &= ", "
    ctx.source &= "input wire [" & $(input.width - 1) & ":0] " & ctx[input]
  for it, (name, output) in circuit.outputs:
    if it != 0 or circuit.inputs.len > 0:
      ctx.source &= ", "
    ctx.source &= "output wire [" & $(output.width - 1) & ":0] " & name
  ctx.source &= ");\n"
  
  let (regs, mems) = circuit.find_state()
  
  let combinatorial_subgraphs = block:
    var combs: seq[Logic] = @[]
    for reg in regs:
      for arg in reg.args:
        combs.add(arg)
    for mem in mems:
      if mem.writes.len > 0:
        combs.add(mem.clock)
      for write in mem.writes:
        combs.add(write.cond)
        combs.add(write.index)
        combs.add(write.value)
    for (name, output) in circuit.outputs:
      combs.add(output)
    combs
  
  ctx.with_indent:
    var closed = init_hash_set[Logic]()
    for comb in combinatorial_subgraphs:
      comb.declare_values(closed, ctx)
    
    ctx.source &= "\n"
    
    for reg in regs:
      ctx.emit_indent()
      ctx.source &= "reg [" & $(reg.width - 1) & ":0] " & ctx[reg] & " = " & ctx[reg.args[0]] & ";\n"
    
    for memory in mems:
      ctx.emit_indent()
      ctx.source &= "reg [" & $(memory.width - 1) & ":0] " & ctx[memory]
      for dim in memory.shape:
        ctx.source &= "[" & $(dim - 1) & ":0]"
      ctx.source &= ";\n"
    
    ctx.source &= "\n"
    
    closed = init_hash_set[Logic]()
    
    for comb in combinatorial_subgraphs:
      comb.emit_combinatorial(closed, ctx)
    
    ctx.source &= "\n"
    
    ctx.emit_indent()
    ctx.source &= "initial begin\n"
    ctx.with_indent:
      for mem in mems:
        if mem.initial.len > 0:
          for it, value in mem.initial:
            ctx.emit_indent()
            ctx.source &= ctx[mem] & "[" & $it & "] = " & $value & ";\n"
    ctx.emit_indent()
    ctx.source &= "end\n"
    
    ctx.source &= "\n"
    
    type
      Sensitivity = (Logic, UpdateEvent)
      
      SequentialBlock = object
        regs: seq[Logic]
        mems: seq[Memory]
    
    var seq_blocks = init_table[Sensitivity, SequentialBlock]()
    for reg in regs:
      let sensitivity = (reg.args[1], reg.event)
      if sensitivity notin seq_blocks:
        seq_blocks[sensitivity] = SequentialBlock()
      seq_blocks[sensitivity].regs.add(reg)
    
    for mem in mems:
      if mem.writes.len > 0:
        let sensitivity = (mem.clock, mem.event)
        if sensitivity notin seq_blocks:
          seq_blocks[sensitivity] = SequentialBlock()
        seq_blocks[sensitivity].mems.add(mem)
    
    for sensitivity, seq_block in seq_blocks:
      let (signal, event) = sensitivity
      ctx.emit_indent()
      ctx.source &= "always @("
      ctx.source &= [RisingEdge: "posedge", FallingEdge: "negedge"][event]
      ctx.source &= " " & ctx[signal] & ") begin\n"
      ctx.with_indent:
        for reg in seq_block.regs:
          ctx.emit_indent()
          ctx.source &= ctx[reg] & " <= " & ctx[reg.args[2]] & ";\n"
        for mem in seq_block.mems:
          ctx.emit_indent()
          for it, write in mem.writes:
            if it != 0:
              ctx.source &= " else "
            ctx.source &= "if (" & ctx[write.cond] & ") begin\n"
            ctx.with_indent:
              ctx.emit_indent()
              ctx.source &= ctx[mem] & "[" & ctx[write.index] & "] <= " & ctx[write.value] & ";\n"
            ctx.emit_indent()
            ctx.source &= "end"
          ctx.source &= "\n"
      ctx.emit_indent()
      ctx.source &= "end\n"
    
    ctx.source &= "\n"
    
    for (name, output) in circuit.outputs:
      ctx.emit_indent()
      ctx.source &= "assign " & name & " = " & ctx[output] & ";\n"
  
  ctx.emit_indent()
  ctx.source &= "endmodule\n"

proc to_verilog*(circuit: Circuit, platform: FpgaPlatform): string =
  let main = platform.wrap(circuit)
  main.infer_widths()
  var ctx = Context()
  for circuit in main.find_circuits():
    circuit.to_verilog(ctx)
  result = ctx.source

proc save_verilog*(circuit: Circuit, path: string, platform: FpgaPlatform) =
  write_file(path, circuit.to_verilog(platform))

proc build*(circuit: Circuit, platform: FpgaPlatform): string =
  result = platform.build_verilog(circuit.to_verilog(platform))

proc upload*(circuit: Circuit, platform: FpgaPlatform) =
  let bitstream = platform.build_verilog(circuit.to_verilog(platform))
  platform.upload_bitstream(bitstream)

when is_main_module:
  let
    clock = Logic.input("clock", role = InputClock)
    counter = Logic.reg(32)
  counter.update(clock, RisingEdge, counter + Logic.constant(32, 1))
  let circuit = Circuit.new([clock], {"counter": counter[(32 - 8)..<32]})
