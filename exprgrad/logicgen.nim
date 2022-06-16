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

# Code generator for FPGAs

import std/[math, tables, sets]
import ir
import fpga/[logicdsl, utils], tensors

proc `*`(a: Logic, b: uint): Logic =
  result = Logic.constant(0, 0)
  for shift in 0..<(sizeof(b) * 8):
    if ((b shr shift) and 1) != 0:
      result = result + (a shl shift)

proc resize(logic: Logic, from_bits, to_bits: int): Logic =
  if from_bits == to_bits:
    result = logic
  elif from_bits > to_bits:
    result = logic[0..<to_bits]
  else:
    result = logic & Logic.constant(to_bits - from_bits, 0)

proc encode_scalar(value: float64, format: ScalarType): BitString =
  var bits = new_seq[bool](format.bits)
  let unsigned_value = abs(value)
  for it, bit in bits.mpairs:
    if it < format.fixed_point:
      bit = (int(unsigned_value * float64(2 ^ (format.fixed_point - it))) and 1) != 0
    else:
      bit = (int(unsigned_value) and (1 shl (it - format.fixed_point))) != 0
  result = BitString.init(bits)
  if value < 0:
    result = -result

type
  Context = object
    state: Logic
    next_state: Logic
    clock: Logic
    
    tensors: seq[Memory]
    regs: seq[Logic]
    
    states: seq[int]
    state_count: int
    init_state: int
    end_state: int
    wait_state: int
    
    kernel_id: KernelId
    program: Program
    kernel: Kernel

proc `[]`(ctx: Context, reg: RegId): Logic =
  result = ctx.regs[reg]
  if result.is_nil:
    raise GeneratorError(msg: $reg & " is not yet defined")

proc alloc_state(ctx: var Context): int =
  result = ctx.state_count
  ctx.state_count += 1

proc to_circuit(instrs: seq[Instr], ctx: var Context) =
  for instr in instrs:
    var res: Logic = nil
    
    template binop(op: untyped) =
      res = op(ctx[instr.args[0]], ctx[instr.args[1]])
    
    let
      scalar_type = ctx.program.scalar_type
      index_type = ctx.program.index_type
    
    case instr.kind:
      of InstrIndex:
        res = Logic.constant(index_type.bits, BiggestUint(instr.index_lit))
      of InstrScalar:
        res = Logic.constant(encode_scalar(instr.scalar_lit, scalar_type))
      of InstrBoolean:
        res = Logic.constant(1, BiggestUint(instr.boolean_lit.ord))
      of InstrAdd: binop(`+`)
      of InstrSub: binop(`-`)
      of InstrMul:
        res = signed_mul(ctx[instr.args[0]], ctx[instr.args[1]])
        if ctx.kernel.regs[instr.args[0]].typ.kind == TypeScalar:
          res = (res shr scalar_type.fixed_point)[0..<scalar_type.bits]
        else:
          res = res[0..<ctx.program.index_type.bits]
      of InstrNegate:
        res = -ctx[instr.args[0]]
      of InstrEq: binop(`<=>`)
      of InstrLt: binop(signed_lt)
      of InstrLe: binop(signed_le)
      of InstrAnd: binop(`and`)
      of InstrOr: binop(`or`)
      of InstrShape, InstrLen, InstrShapeLen:
        let tensor = ctx.program.tensors[instr.tensor]
        var value = 0
        case instr.kind:
          of InstrShape: value = tensor.shape[instr.dim]
          of InstrLen: value = tensor.shape.prod()
          of InstrShapeLen: value = tensor.shape.len
          else: discard
        res = Logic.constant(index_type.bits, BiggestUint(value))
      of InstrSelect:
        res = select(ctx[instr.args[0]], ctx[instr.args[1]], ctx[instr.args[2]])
      of InstrToScalar:
        let from_typ = ctx.kernel.regs[instr.args[0]].typ
        if from_typ.kind == TypeIndex:
          res = ctx[instr.args[0]].resize(index_type.bits, scalar_type.bits) shl scalar_type.fixed_point
        else:
          raise GeneratorError(msg: "Unable to convert " & $from_typ & " to scalar")
      of InstrToIndex:
        let from_typ = ctx.kernel.regs[instr.args[0]].typ
        if from_typ.kind == TypeScalar:
          res = resize(ctx[instr.args[0]] shr scalar_type.fixed_point, scalar_type.bits, index_type.bits)
        else:
          raise GeneratorError(msg: "Unable to convert " & $from_typ & " to index")
      of InstrRead:
        res = ctx.tensors[instr.tensor][ctx[instr.args[0]]]
      of InstrWrite, InstrOverwrite:
        var value = ctx[instr.args[1]]
        if instr.kind == InstrWrite:
          value = value + ctx.tensors[instr.tensor][ctx[instr.args[0]]]
        ctx.tensors[instr.tensor].write(
          ctx.clock,
          RisingEdge,
          ctx.state <=> Logic.constant(ctx.state.width, BiggestUint(ctx.states[ctx.kernel_id])),
          ctx[instr.args[0]],
          value
        )
      of InstrNestedLoops:
        var is_inner_done: Logic = nil
        for it in countdown(instr.nested_loops.len - 1, 0):
          let
            (iter_reg, step)  = instr.nested_loops[it]
            (start, stop) = (ctx[instr.args[2 * it]], ctx[instr.args[2 * it + 1]])
            iter = Logic.reg(index_type.bits, initial = Logic.constant(index_type.bits, 0), name = "iter" & $it)
            inc = iter + Logic.constant(index_type.bits, BiggestUint(step))
            is_done = inc <=> stop
          var next = select(is_done, start, inc)
          if not is_inner_done.is_nil:
            next = select(is_inner_done, next, iter)
            is_inner_done = is_done and is_inner_done
          else:
            is_inner_done = is_done
          iter.update(ctx.clock, RisingEdge, next)
          ctx.regs[iter_reg] = iter
        instr.body.to_circuit(ctx)
        
        var
          next_kernel = KernelId(int(ctx.kernel_id) + 1)
          next_kernel_state = ctx.end_state
        
        if int(next_kernel) - 1 < ctx.states.len:
          next_kernel_state = ctx.states[next_kernel]
        
        let
          kernel_state = Logic.constant(ctx.state.width, BiggestUint(ctx.states[ctx.kernel_id]))
          goto_next_state = (ctx.state <=> kernel_state) and is_inner_done
        ctx.next_state = select(goto_next_state,
          Logic.constant(ctx.state.width, BiggestUint(next_kernel_state)),
          ctx.next_state
        )
      of InstrDiv, InstrIndexDiv, InstrMod, InstrWrap, InstrSin, InstrCos,
         InstrExp, InstrPow, InstrSqrt, InstrLog, InstrLog10, InstrLog2, InstrLn:
        raise GeneratorError(msg: "Logic synthesis for " & $instr.kind & " is not yet implemented")
      else:
        raise GeneratorError(msg: "Unable to generate logic for " & $instr.kind)
    if not res.is_nil:
      ctx.regs[instr.res] = res

proc to_circuit*(kernel: Kernel, ctx: var Context) =
  ctx.kernel = kernel
  ctx.regs = new_seq[Logic](kernel.regs.len)
  kernel.setup.to_circuit(ctx)

proc to_circuit*(target: Target, ctx: var Context) =
  ctx.init_state = ctx.alloc_state()
  ctx.end_state = ctx.alloc_state()
  
  ctx.states = new_seq[int](target.kernels.len)
  for state in ctx.states.mitems:
    state = ctx.alloc_state()
  
  ctx.next_state = select(ctx.state <=> Logic.constant(ctx.state.width, BiggestUint(ctx.init_state)),
    Logic.constant(ctx.state.width, BiggestUint(ctx.states[0])),
    ctx.next_state
  )
  ctx.next_state = select(ctx.state <=> Logic.constant(ctx.state.width, BiggestUint(ctx.end_state)),
    Logic.constant(ctx.state.width, BiggestUint(ctx.wait_state)),
    ctx.next_state
  )
  for it, kernel in target.kernels:
    ctx.kernel_id = KernelId(it + 1)
    kernel.to_circuit(ctx)

proc to_circuit*(program: Program, inputs: openArray[(string, Tensor[float64])]): Circuit =
  program.assert_gen("to_circuit",
    requires={StageTyped, StageLoops}
  )
  
  var
    state_count = 1
    used_tensors = init_hash_set[TensorId]()
  for name, target in program.targets:
    if target.compile_target == CompileFpga:
      state_count += target.kernels.len + 2
      used_tensors = used_tensors + target.tensors
  
  let state = Logic.reg(count_bits(state_count))
  
  var ctx = Context(
    state: state,
    next_state: state,
    clock: Logic.input("clock", role=InputClock),
    tensors: new_seq[Memory](program.tensors.len),
    program: program
  )
  
  ctx.wait_state = ctx.alloc_state()
  
  var initial_tensors = new_seq[Tensor[float64]](program.tensors.len)
  
  for (name, value) in inputs:
    initial_tensors[program.inputs[name]] = value
  
  for id in used_tensors:
    let
      def = program.tensors[id]
      shape = def.shape # TODO: Infer shape
    case def.kind:
      of TensorInput:
        if initial_tensors[id].is_nil:
          raise GeneratorError()
      of TensorRandom:
        initial_tensors[id] = new_rand_tensor[float64](shape, def.random_range)
      of TensorParam:
        initial_tensors[id] = new_rand_tensor[float64](shape, def.init_range)
      of TensorResult, TensorCache: discard
  
  for id in used_tensors:
    var initial: seq[BitString] = @[]
    if not initial_tensors[id].is_nil:
      let tensor = initial_tensors[id]
      for it in 0..<tensor.len:
        initial.add(tensor{it}.encode_scalar(program.scalar_type))
    let size = program.tensors[id].shape.prod()
    ctx.tensors[id] = Memory.new(program.scalar_type.bits, [size], initial=initial)
  
  var target_states = init_table[string, int]()
  for name, target in program.targets:
    target.to_circuit(ctx)
    target_states[name] = ctx.init_state
  
  ctx.next_state = select(ctx.state <=> Logic.constant(ctx.state.width, BiggestUint(ctx.wait_state)),
    Logic.constant(ctx.state.width, BiggestUint(target_states["loss"])),
    ctx.next_state
  )
  
  ctx.state.update(ctx.clock, RisingEdge, ctx.next_state)
  
  let
    read_index = Logic.input("read_index", width = program.index_type.bits)
    read_tensor_id = Logic.input("read_tensor_id", width = program.index_type.bits)
  
  var read_value = Logic.constant(program.scalar_type.bits, 0)
  for name, target in program.targets:
    if target.compile_target == CompileFpga and target.output != TensorId(0):
      let tensor_id = Logic.constant(program.index_type.bits, BiggestUint(int(target.output) - 1))
      read_value = select(read_tensor_id <=> tensor_id,
        ctx.tensors[target.output][read_index],
        read_value
      )
  
  result = Circuit.new([ctx.clock, read_tensor_id, read_index], {"data": read_value})
