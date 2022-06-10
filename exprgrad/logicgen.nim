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
import fpga/logicdsl

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

proc encode_scalar(value: float64, format: ScalarType): Logic =
  var bits = new_seq[bool](format.bits)
  for it, bit in bits.mpairs:
    if it < format.fixed_point:
      bit = (int(value * float64(2 ^ (format.fixed_point - it))) and 1) != 0
    else:
      bit = (int(value) and (1 shl (it - format.fixed_point))) != 0
  result = Logic.constant(bits)

type
  Context = object
    state: Logic
    next_state: Logic
    clock: Logic
    
    tensors: seq[Memory]
    regs: seq[Logic]
    current_state: int
    state_count: int
    
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
        res = encode_scalar(instr.scalar_lit, scalar_type)
      of InstrBoolean:
        res = Logic.constant(1, BiggestUint(instr.boolean_lit.ord))
      of InstrAdd: binop(`+`)
      of InstrSub: binop(`-`)
      of InstrMul:
        # TODO: Signed
        res = ctx[instr.args[0]] * ctx[instr.args[1]]
        if ctx.kernel.regs[instr.args[0]].typ.kind == TypeScalar:
          res = (res shr scalar_type.fixed_point)[0..<scalar_type.bits]
        else:
          res = res[0..<ctx.program.index_type.bits]
      of InstrNegate:
        res = -ctx[instr.args[0]]
      of InstrEq: binop(`<=>`)
      of InstrLt: binop(`<`) # TODO: Signed
      of InstrLe: binop(`<=`) # TODO: Signed
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
          Logic.constant(true),
          ctx[instr.args[0]],
          value
        )
      of InstrNestedLoops:
        var is_inner_done: Logic = nil
        for it in countdown(instr.nested_loops.len - 1, 0):
          let
            (iter_reg, step)  = instr.nested_loops[it]
            (start, stop) = (ctx[instr.args[2 * it]], ctx[instr.args[2 * it + 1]])
            iter = Logic.reg(index_type.bits, initial = Logic.constant(index_type.bits, 0))
            inc = iter + Logic.constant(index_type.bits, BiggestUint(step))
            is_done = inc <=> stop
          var next = select(is_done, start, inc)
          if not is_inner_done.is_nil:
            next = select(is_inner_done, next, iter)
          is_inner_done = is_done
          iter.update(ctx.clock, RisingEdge, next)
          ctx.regs[iter_reg] = iter
        instr.body.to_circuit(ctx)
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

proc to_circuit*(target: Target, program: Program): Circuit =
  program.assert_gen("to_circuit",
    requires={StageTyped, StageLoops}
  )
  
  var ctx = Context(
    state: Logic.reg(0),
    next_state: Logic.reg(0),
    clock: Logic.input("clock", role=InputClock),
    tensors: new_seq[Memory](program.tensors.len),
    program: program
  )
  
  for id in target.tensors:
    let size = program.tensors[id].shape.prod()
    ctx.tensors[id] = Memory.new(program.scalar_type.bits, [size])
  
  for kernel in target.kernels:
    kernel.to_circuit(ctx)
  
  let read_index = Logic.input("read_index", width = program.index_type.bits)
  result = Circuit.new([ctx.clock, read_index], {"data": ctx.tensors[target.output][read_index]})
