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

type
  UpdateEvent* = enum
    RisingEdge, FallingEdge
  
  InputRole* = enum
    InputNone, InputClock, InputReset
  
  Logic* = ref object
    args*: seq[Logic]
    width*: int
    case kind*: LogicKind:
      of LogicConst:
        value*: seq[uint8]
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
  
  Memory* = ref object
    width: int
    shape: seq[int]
    
    clock*: Logic
    event*: UpdateEvent
    writes*: seq[(Logic, Logic, Logic)]
  
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

proc constant*(_: typedesc[Logic], bits: int, value: BiggestUint): Logic =
  result = Logic(kind: LogicConst, width: bits)
  var bytes = bits div 8
  if bits mod 8 != 0:
    bytes += 1
  for it in 0..<bytes:
    result.value.add(uint8((value shr (it * 8)) and 0xff))

proc constant*(_: typedesc[Logic], value: seq[bool]): Logic =
  result = Logic(kind: LogicConst, width: value.len)
  var bytes = new_seq[uint8](value.len div 8)
  if value.len mod 8 != 0:
    bytes.add(uint8(0))
  for it, bit in value:
    if bit:
      bytes[it div 8] = bytes[it div 8] or uint8(1 shl (it mod 8))
  result.value = bytes

proc constant*(_: typedesc[Logic], value: bool): Logic =
  result = Logic(kind: LogicConst, width: 1, value: @[uint8(ord(value))])

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

proc select(value: Logic, cases: openArray[(Logic, Logic)], default: Logic): Logic =
  result = default
  for it in countdown(cases.len - 1, 0):
    let (pattern, res) = cases[it]
    result = Logic(kind: LogicSelect, args: @[pattern <=> value, res, result])

proc `[]`*(value: Logic, slice: HSlice[int, int]): Logic =
  result = Logic(kind: LogicSlice, slice: slice, args: @[value])

proc `&`*(a, b: Logic): Logic =
  result = Logic(kind: LogicConcat, args: @[a, b])

proc new*(_: typedesc[Memory], width: int, shape: openArray[int]): Memory =
  result = Memory(width: width, shape: @shape)

proc `[]`*(mem: Memory, index: Logic): Logic =
  result = Logic(kind: LogicRead, memory: mem, args: @[index])

proc write*(mem: Memory, clock: Logic, event: UpdateEvent, cond, index, value: Logic) =
  if mem.clock.is_nil:
    mem.clock = clock
    mem.event = event
  elif mem.clock != clock:
    raise new_exception(ValueError, "Memory has multiple drivers")
  mem.writes.add((cond, index, value))

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
  for (cond, index, value) in mem.writes:
    if cond.infer_width(closed) != 1:
      raise new_exception(ValueError, "Condition must have width 1")
    discard index.infer_width(closed)
    if value.infer_width(closed) != mem.width:
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
        for (cond, index, value) in logic.memory.writes:
          cond.find_state(regs, mems)
          index.find_state(regs, mems)
          value.find_state(regs, mems)
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
  WrapperGenerator* = proc(circuit: Circuit, spec: TargetSpec): Circuit
  
  TargetSpec* = object
    wrapper*: WrapperGenerator
  
  Context = object
    source: string
    indent: int
    module_names: Table[Circuit, string]
    value_names: Table[Logic, string]
    memory_names: Table[Memory, string]

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

proc format_value*(width: int, value: seq[uint8]): string =
  result = $width & "'b"
  for it in countdown(value.len - 1, 0):
    for shift in countdown(min(7, width - it * 8 - 1), 0):
      result &= ["0", "1"][ord(((value[it] shr shift) and 1) != 0)]

proc `[]`(ctx: var Context, logic: Logic): string =
  if logic notin ctx.value_names:
    var name = "value" & $ctx.value_names.len
    if logic.kind == LogicInput:
      name = logic.name
    elif logic.kind == LogicReg and logic.reg_name.len > 0:
      name &= "_" & logic.reg_name
    elif logic.kind == LogicConst:
      name = format_value(logic.width, logic.value)
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
        if it != 0:
          result &= ", "
        result &= ctx[logic.args[it]]
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
      for (cond, index, value) in mem.writes:
        combs.add(cond)
        combs.add(index)
        combs.add(value)
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
    
    var seq_blocks = init_table[(Logic, UpdateEvent), seq[(Logic, Logic)]]()
    for reg in regs:
      let
        (cond, value) = (reg.args[1], reg.args[2])
        sensitivity = (cond, reg.event)
      if sensitivity notin seq_blocks:
        seq_blocks[sensitivity] = new_seq[(Logic, Logic)]()
      seq_blocks[sensitivity].add((reg, value))
    
    for sensitivity, assigns in seq_blocks:
      let (signal, event) = sensitivity
      ctx.emit_indent()
      ctx.source &= "always @("
      ctx.source &= [RisingEdge: "posedge", FallingEdge: "negedge"][event]
      ctx.source &= " " & ctx[signal] & ") begin\n"
      ctx.with_indent:
        for (target, value) in assigns:
          ctx.emit_indent()
          ctx.source &= ctx[target] & " <= " & ctx[value] & ";\n"
      ctx.emit_indent()
      ctx.source &= "end\n"
    
    ctx.source &= "\n"
    
    for (name, output) in circuit.outputs:
      ctx.emit_indent()
      ctx.source &= "assign " & name & " = " & ctx[output] & ";\n"
  
  ctx.emit_indent()
  ctx.source &= "endmodule\n"

proc to_verilog*(circuit: Circuit, target: TargetSpec): string =
  let main = target.wrapper(circuit, target)
  main.infer_widths()
  var ctx = Context()
  for circuit in main.find_circuits():
    circuit.to_verilog(ctx)
  result = ctx.source

proc save_verilog*(circuit: Circuit, path: string, target: TargetSpec) =
  write_file(path, circuit.to_verilog(target))

when is_main_module:
  let
    clock = Logic.input("clock", role = InputClock)
    counter = Logic.reg(32)
  counter.update(clock, RisingEdge, counter + Logic.constant(32, 1))
  let circuit = Circuit.new([clock], {"counter": counter[(32 - 8)..<32]})
  
  proc wrapper(circuit: Circuit, target: TargetSpec): Circuit =
    let clock = Logic.input("clk_25mhz")
    result = Circuit.new([clock], {
      "wifi_gpio0": Logic.constant(true),
      "led": circuit.instantiate({
        circuit.find_role(InputClock).name: clock
      }, 0)
    }, name = "main")
  
  let target = TargetSpec(wrapper: wrapper)
  circuit.save_verilog("build/output.v", target)
