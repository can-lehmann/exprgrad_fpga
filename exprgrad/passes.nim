# Copyright 2021 Can Joshua Lehmann
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

# Compiler passes for exprgrad's compiler

import std/[tables, algorithm, sets, math, rationals, sequtils, strutils]
import ir, irprint

proc infer_types(instrs: seq[Instr], regs: var seq[Register]) =
  for instr in instrs:
    template ret_type(): var Type = regs[instr.res].typ
    template arg_type(index: int): Type = regs[instr.args[index]].typ
    
    case instr.kind:
      of InstrIndex: ret_type = Type(kind: TypeIndex, count: 1)
      of InstrScalar: ret_type = Type(kind: TypeScalar, count: 1)
      of InstrBoolean: ret_type = Type(kind: TypeBoolean, count: 1)
      of InstrAdd, InstrSub, InstrMul,
         InstrEq, InstrLe, InstrLt:
        let (a, b) = (arg_type(0), arg_type(1))
        if a != b:
          raise TypeError(msg: "Arguments of " & $instr.kind & " must have the same type, but got " & $a & " and " & $b & " instead.")
        case instr.kind:
          of InstrEq, InstrLe, InstrLt:
            ret_type = Type(kind: TypeBoolean, count: a.count)
          else: ret_type = a
      of InstrDiv:
        if arg_type(0).kind != TypeScalar or arg_type(0).kind != TypeScalar:
          raise TypeError(msg: "Arguments of " & $instr.kind & " must be of type Scalar.")
        ret_type = arg_type(0)
      of InstrIndexDiv, InstrMod, InstrWrap:
        if arg_type(0).kind != TypeIndex or arg_type(0).kind != TypeIndex:
          raise TypeError(msg: "Arguments of " & $instr.kind & " must be of type Index.")
        ret_type = arg_type(0)
      of InstrNegate:
        if arg_type(0).kind notin {TypeScalar, TypeIndex}:
          raise TypeError(msg: "Argument to " & $instr.kind & " must be a Scalar or an Index")
        ret_type = arg_type(0)
      of InstrAnd, InstrOr:
        if arg_type(0).kind != TypeBoolean or arg_type(0).kind != TypeBoolean:
          raise TypeError(msg: "Arguments of " & $instr.kind & " must be of type Boolean.")
        ret_type = arg_type(0)
      of InstrSelect:
        let (cond, a, b) = (arg_type(0), arg_type(1), arg_type(2))
        if a != b:
          raise TypeError(msg: "The second and the third argument of " & $instr.kind & " must have the same type")
        if cond.kind != TypeBoolean:
          raise TypeError(msg: "The first argument of " & $instr.kind & " must be a Boolean")
        if cond.count != a.count:
          raise TypeError(msg: "All arguments of " & $instr.kind & " must have the same count")
        ret_type = a
      of InstrToScalar:
        if arg_type(0).kind notin {TypeIndex}:
          raise TypeError(msg: "Unable to convert " & $arg_type(0) & " to Scalar")
        ret_type = Type(kind: TypeScalar, count: arg_type(0).count)
      of InstrToIndex:
        if arg_type(0).kind notin {TypeScalar}:
          raise TypeError(msg: "Unable to convert " & $arg_type(0) & " to Index")
        ret_type = Type(kind: TypeIndex, count: arg_type(0).count)
      of InstrSin, InstrCos, InstrExp, InstrPow, InstrSqrt,
         InstrLog, InstrLog10, InstrLog2, InstrLn:
        for it in 0..<instr.args.len:
          if arg_type(it).kind != TypeScalar:
            raise TypeError(msg: "Argument " & $it & " to " & $instr.kind & " is currently of type " & $arg_type(it) & ", but must be of type Scalar.")
        ret_type = arg_type(0)
      of InstrShape, InstrLen, InstrShapeLen:
        ret_type = Type(kind: TypeIndex, count: 1)
      of InstrArray:
        for it in 1..<instr.args.len:
          if arg_type(it) != arg_type(0):
            raise TypeError(msg: "All items in array must be of the same type")
        ret_type = Type(kind: TypeArray,
          count: 1,
          len: instr.args.len,
          item: arg_type(0)
        )
      of InstrArrayLen:
        if arg_type(0).kind != TypeArray:
          raise TypeError(msg: "Argument to " & $instr.kind & " must be an array")
        ret_type = Type(kind: TypeIndex, count: arg_type(0).count)
      of InstrArrayRead:
        if arg_type(0).kind != TypeArray:
          raise TypeError(msg: "First argument to " & $instr.kind & " must be an array")
        if arg_type(1).kind != TypeIndex:
          raise TypeError(msg: "Second argument to " & $instr.kind & " must be an index")
        if arg_type(0).count != arg_type(1).count:
          raise TypeError() 
        ret_type = arg_type(0).item
      of InstrRead, InstrWrite, InstrOverwrite:
        if instr.tensor == TensorId(0):
          raise TypeError(msg: $instr.kind & " must have a tensor argument")
        if arg_type(0).kind != TypeIndex:
          raise TypeError(msg: "First argument to " & $instr.kind & " must be an Index")
        case instr.kind:
          of InstrRead: ret_type = Type(kind: TypeScalar, count: 1)
          of InstrWrite:
            if arg_type(1).kind != TypeScalar:
              raise TypeError(msg: "Second argument of " & $instr.kind & " must be a Scalar")
          else: discard
      of InstrEpoch: ret_type = Type(kind: TypeIndex, count: 1)
      of InstrLoop:
        if arg_type(0).kind != TypeIndex or arg_type(1).kind != TypeIndex:
          raise TypeError(msg: "Loop bounds must be of type Index, but are currently of types " & $arg_type(0) & " and " & $arg_type(1))
        regs[instr.loop_iter].typ = Type(kind: TypeIndex, count: 1)
        instr.body.infer_types(regs)
      of InstrThreads:
        if arg_type(0).kind != TypeIndex or arg_type(1).kind != TypeIndex:
          raise TypeError(msg: "Thread range must be of type Index")
        regs[instr.threads_begin].typ = Type(kind: TypeIndex, count: 1)
        regs[instr.threads_end].typ = Type(kind: TypeIndex, count: 1)
        instr.body.infer_types(regs)
      of InstrGpu:
        for it, arg in instr.args:
          if arg_type(it).kind != TypeIndex:
            raise TypeError(msg: "Gpu ranges must be of type Index")
        for index in instr.gpu_indices:
          regs[index.group].typ = Type(kind: TypeIndex, count: 1)
          regs[index.local].typ = Type(kind: TypeIndex, count: 1)
        instr.body.infer_types(regs)
      of InstrIf:
        if arg_type(0).kind != TypeBoolean:
          raise TypeError(msg: "If condition must be of type Boolean")
        instr.body.infer_types(regs)
      of InstrSharedCache:
        ret_type = Type(kind: TypeArray,
          count: 1,
          len: instr.cache_size,
          item: Type(kind: TypeScalar, count: 1)
        )
      of InstrCacheWrite:
        if arg_type(0).kind != TypeArray:
          raise TypeError(msg: "Local cache must be of type Array")
        if arg_type(1).kind != TypeIndex:
          raise TypeError(msg: "Index into local cache must be of type Index")
        if arg_type(2).kind != TypeScalar:
          raise TypeError(msg: "Third argument of " & $instr.kind & " must be of type Scalar")
      of InstrBarrier: discard
      of InstrNestedLoops:
        for it, (iter, step) in instr.nested_loops:
          if arg_type(2 * it).kind != TypeIndex or arg_type(2 * it + 1).kind != TypeIndex:
            raise TypeError(msg: "Loop bounds must be of type Index")
          regs[iter].typ = Type(kind: TypeIndex, count: 1)
        instr.body.infer_types(regs)

proc infer_types(expr: Expr, regs: var seq[Register]) =
  expr.instrs.infer_types(regs)

proc infer_types(index: LinearIndex, regs: var seq[Register]) =
  index.setup.infer_types(regs)
  for reg, factor in index.factors:
    if regs[reg].typ.kind != TypeIndex:
      raise TypeError(msg: "LinearIndex factor have the type Index")

proc infer_types(tensor_op: TensorOp, regs: var seq[Register]) =
  for dim in tensor_op.dims:
    dim.infer_types(regs)
  if tensor_op.is_raw and tensor_op.dims.len != 1:
    raise TypeError(msg: "A raw tensor operation must have exactly one index")

proc infer_types*(kernel: Kernel) =
  if kernel.generator.kind == GenNone:
    kernel.setup.infer_types(kernel.regs)
    for loop in kernel.loops:
      loop.start.infer_types(kernel.regs)
      loop.stop.infer_types(kernel.regs)
      kernel.regs[loop.iter].typ = Type(kind: TypeIndex, count: 1)
    for cond in kernel.conds:
      cond.infer_types(kernel.regs)
      if kernel.regs[cond.res].typ.kind != TypeBoolean:
        raise TypeError(msg: "Condition must be of type Boolean")
    for read in kernel.reads:
      read.infer_types(kernel.regs)
      kernel.regs[read.data].typ = Type(kind: TypeScalar, count: 1)
    kernel.expr.infer_types(kernel.regs)
    kernel.write.infer_types(kernel.regs)
    if kernel.write.data != RegId(0) and
       kernel.regs[kernel.write.data].typ.kind != TypeScalar:
      raise TypeError(msg: "Kernel must write a Scalar to the output tensor")

proc infer_types*(program: Program) =
  program.assert_pass("infer_types",
    produces={StageTyped},
    preserves=ALL_STAGES
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.infer_types()

proc fold_setup(index: var LinearIndex, kernel: Kernel) =
  var regs = new_seq[LinearIndex](kernel.regs.len)
  for loop in kernel.loops:
    # TODO: How should we handle registers defined in the setup section of the kernel?
    regs[loop.iter] = LinearIndex(
      factors: to_table({loop.iter: 1})
    )
  
  for instr in index.setup:
    template binary_op(op) =
      regs[instr.res] = op(regs[instr.args[0]], regs[instr.args[1]])
    
    template unary_op(op) =
      regs[instr.res] = op(regs[instr.args[0]])
    
    case instr.kind:
      of InstrIndex: regs[instr.res] = init_linear_index(instr.index_lit)
      of InstrAdd: binary_op(`+`)
      of InstrSub: binary_op(`-`)
      of InstrMul: binary_op(`*`)
      of InstrNegate: unary_op(`-`)
      else:
        regs[instr.res] = LinearIndex(
          factors: to_table({instr.res: 1})
        )
  
  var sum = LinearIndex()
  for reg, factor in index.factors:
    sum = sum + regs[reg] * factor
  
  var used = new_seq[bool](kernel.regs.len)
  for reg, factor in sum.factors:
    used[reg] = true
  
  for it in countdown(index.setup.len - 1, 0):
    let instr = index.setup[it]
    if used[instr.res]:
      sum.setup.add(instr)
      for arg in instr.args:
        used[arg] = true
  
  sum.setup.reverse()
  index = sum

proc fold_linear_indices(kernel: Kernel) =
  for loop in kernel.loops.mitems:
    loop.start.fold_setup(kernel)
    loop.stop.fold_setup(kernel)
  for read in kernel.reads.mitems:
    for dim in read.dims.mitems:
      dim.fold_setup(kernel)
  for dim in kernel.write.dims.mitems:
    dim.fold_setup(kernel)

proc fold_linear_indices*(program: Program) =
  program.assert_pass("fold_linear_indices",
    produces={StageFolded},
    preserves={StageTensors}
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.fold_linear_indices()
      if kernel.grad.is_custom:
        for grad_kernel in kernel.grad.kernels:
          grad_kernel.fold_linear_indices()

proc dead_code_elim(instrs: var seq[Instr], used: var seq[bool]) =
  var it = instrs.len - 1
  while it >= 0:
    let instr = instrs[it]
    let is_instr_used = used[instr.res] or instr.kind in SIDE_EFFECT_INSTRS
    if is_instr_used:
      for arg in instr.args:
        used[arg] = true
    else:
      instrs.delete(it)
    it -= 1

proc dead_code_elim(index: var LinearIndex, used: var seq[bool]) =
  for reg, factor in index.factors:
    used[reg] = true
  index.setup.dead_code_elim(used)

proc dead_code_elim(loops: var seq[Loop], used: var seq[bool]) =
  for it in countdown(loops.len - 1, 0):
    loops[it].start.dead_code_elim(used)
    loops[it].stop.dead_code_elim(used)

proc dead_code_elim(reads: var seq[TensorOp], used: var seq[bool]) =
  var it = 0
  while it < reads.len:
    if not used[reads[it].data]:
      reads.delete(it)
    else:
      for dim in reads[it].dims.mitems:
        dim.dead_code_elim(used)
      it += 1

proc dead_code_elim*(kernel: Kernel) =
  if kernel.generator.kind == GenNone:
    var used = new_seq[bool](kernel.regs.len)
    used[kernel.write.data] = true
    for dim in kernel.write.dims.mitems:
      dim.dead_code_elim(used)
    kernel.expr.instrs.dead_code_elim(used)
    kernel.reads.dead_code_elim(used)
    kernel.loops.dead_code_elim(used)
    kernel.setup.dead_code_elim(used)

proc dead_code_elim*(program: Program) =
  program.assert_pass("dead_code_elim",
    produces={},
    preserves=ALL_STAGES
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.dead_code_elim()
      if kernel.grad.is_custom:
        for grad_kernel in kernel.grad.kernels:
          grad_kernel.dead_code_elim()

proc dead_kernel_elim*(program: Program) =
  for name, target in program.targets.mpairs:
    var
      used = new_seq[bool](program.tensors.len)
      it = target.kernels.len - 1
    
    for it, tensor in program.tensors:
      if tensor.kind != TensorResult:
        used[it] = true
    if target.output != TensorId(0):
      used[target.output] = true
    
    while it >= 0:
      let kernel = target.kernels[it]
      if used[kernel.write.tensor]:
        for read in kernel.reads:
          used[read.tensor] = true
      else:
        target.kernels.delete(it)
      it -= 1

proc deduplicate_reads*(kernel: Kernel) =
  var
    unique = init_table[TensorOp, RegId]()
    subs = init_table[RegId, RegId]()
    it = 0
  while it < kernel.reads.len:
    var base_read = kernel.reads[it]
    base_read.data = RegId(0)
    if base_read in unique:
      subs[kernel.reads[it].data] = unique[base_read]
      kernel.reads.delete(it)
    else:
      unique[base_read] = kernel.reads[it].data
      it += 1
  
  kernel.expr.substitute(subs)
  kernel.write.substitute(subs)

proc deduplicate_reads*(program: Program) =
  program.assert_pass("deduplicate_reads",
    produces={},
    preserves=ALL_STAGES
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.deduplicate_reads()
      if kernel.grad.is_custom:
        for grad_kernel in kernel.grad.kernels:
          grad_kernel.deduplicate_reads()

proc derive(instrs: seq[Instr],
            regs: var seq[Register],
            grad_regs: var Table[RegId, RegId]): seq[Instr] =
  for it in countdown(instrs.len - 1, 0):
    let instr = instrs[it]
    if instr.res notin grad_regs:
      continue
    let grad = grad_regs[instr.res]
    var grad_args = new_seq[RegId]()
    case instr.kind:
      of InstrAdd:
        grad_args = @[grad, grad]
      of InstrSub:
        let neg_grad = regs.alloc()
        result.add(Instr(kind: InstrNegate, args: @[grad], res: neg_grad))
        grad_args = @[grad, neg_grad]
      of InstrMul:
        let (grad_a, grad_b) = (regs.alloc(), regs.alloc())
        result.add(Instr(kind: InstrMul, args: @[grad, instr.args[1]], res: grad_a))
        result.add(Instr(kind: InstrMul, args: @[grad, instr.args[0]], res: grad_b))
        grad_args = @[grad_a, grad_b]
      of InstrDiv:
        # d/dx (x / y) = 1 / y
        # d/dy (x / y) = d/dy (x * y ^ -1) = -x * y ^ -2
        let
          (grad_a, grad_b) = (regs.alloc(), regs.alloc())
          (neg_x, sq_y, div_grad_sq_y) = (regs.alloc(), regs.alloc(), regs.alloc())
        result.add(Instr(kind: InstrDiv, args: @[grad, instr.args[1]], res: grad_a))
        result.add(Instr(kind: InstrMul, args: @[instr.args[1], instr.args[1]], res: sq_y))
        result.add(Instr(kind: InstrDiv, args: @[grad, sq_y], res: div_grad_sq_y))
        result.add(Instr(kind: InstrNegate, args: @[instr.args[0]], res: neg_x))
        result.add(Instr(kind: InstrMul, args: @[neg_x, div_grad_sq_y], res: grad_b))
        grad_args = @[grad_a, grad_b]
      of InstrNegate:
        let neg_grad = regs.alloc()
        result.add(Instr(kind: InstrNegate, args: @[grad], res: neg_grad))
        grad_args = @[neg_grad]
      of InstrLn:
        let grad_x = regs.alloc()
        result.add(Instr(kind: InstrDiv, args: @[grad, instr.args[0]], res: grad_x))
        grad_args = @[grad_x]
      of InstrExp:
        let grad_x = regs.alloc()
        result.add(Instr(kind: InstrMul, args: @[grad, instr.res], res: grad_x))
        grad_args = @[grad_x]
      of InstrSin:
        let (cos, grad_x) = (regs.alloc(), regs.alloc())
        result.add(Instr(kind: InstrCos, args: @[instr.args[0]], res: cos))
        result.add(Instr(kind: InstrMul, args: @[cos, grad], res: grad_x))
        grad_args = @[grad_x]
      of InstrCos:
        let (sin, neg_sin, grad_x) = (regs.alloc(), regs.alloc(), regs.alloc())
        result.add(Instr(kind: InstrSin, args: @[instr.args[0]], res: sin))
        result.add(Instr(kind: InstrNegate, args: @[sin], res: neg_sin))
        result.add(Instr(kind: InstrMul, args: @[neg_sin, grad], res: grad_x))
        grad_args = @[grad_x]
      of InstrSelect:
        let (grad_a, grad_b, zero) = (regs.alloc(), regs.alloc(), regs.alloc())
        result.add(Instr(kind: InstrScalar, res: zero))
        result.add(Instr(kind: InstrSelect, args: @[instr.args[0], grad, zero], res: grad_a))
        result.add(Instr(kind: InstrSelect, args: @[instr.args[0], zero, grad], res: grad_b))
        grad_args = @[RegId(0), grad_a, grad_b]
      of InstrToScalar, InstrToIndex: grad_args = @[RegId(0)]
      else: discard
    
    if grad_args.len != instr.args.len:
      raise GradientError(msg: "Unable to derive " & $instr.kind)
    
    for it, arg in instr.args:
      if grad_args[it] != RegId(0):
        if arg in grad_regs:
          let sum = regs.alloc()
          result.add(Instr(kind: InstrAdd, args: @[grad_regs[arg], grad_args[it]], res: sum))
          grad_regs[arg] = sum
        else:
          grad_regs[arg] = grad_args[it]

proc derive*(kernel: Kernel, grad_tensors: Table[TensorId, TensorId]): seq[Kernel] =
  let base_kernel = kernel.clone()
  var grad_regs = init_table[RegId, RegId]()
  
  block derive_write:
    let write_grad = base_kernel.regs.alloc()
    base_kernel.reads.add(TensorOp(
      is_raw: kernel.write.is_raw,
      data: write_grad,
      dims: kernel.write.dims,
      tensor: grad_tensors[kernel.write.tensor]
    ))
    grad_regs[kernel.write.data] = write_grad
  
  block derive_expr:
    base_kernel.expr.instrs &= kernel.expr.instrs.derive(
      base_kernel.regs, grad_regs
    )
  
  for read in kernel.reads:
    let grad_kernel = base_kernel.clone()
    if read.data in grad_regs:
      grad_kernel.expr.res = grad_regs[read.data]
      grad_kernel.write = TensorOp(
        tensor: grad_tensors[read.tensor],
        is_raw: read.is_raw,
        dims: read.dims,
        data: grad_regs[read.data]
      )
      grad_kernel.dead_code_elim()
      result.add(grad_kernel)

proc copy_shape(target: Target, dest, src: TensorId) =
  target.shapes.add(ShapeConstraint(kind: ShapeCopy, dest: dest, src: src))

proc generate*(program: Program) =
  program.assert_pass("generate",
    produces={StageGenerated},
    preserves={StageShapes, StageFolded, StageTensors}
  )

  for name, target in program.targets.mpairs:
    var it = 0
    while it < target.kernels.len:
      let kernel = target.kernels[it]
      case kernel.generator.kind:
        of GenBackwards:
          var
            grad_tensors = init_table[TensorId, TensorId]()
            grad_kernels: seq[Kernel] = @[]
          
          block:
            let
              loss = kernel.generator.tensor
              grad_loss = program.tensors.alloc(TensorDef(
                kind: TensorResult
              ))
            grad_kernels.add(Kernel(
              regs: @[
                Register(typ: Type(kind: TypeScalar, count: 1)),
                Register(typ: Type(kind: TypeIndex, count: 1)),
                Register(typ: Type(kind: TypeIndex, count: 1))
              ],
              loops: @[Loop(iter: RegId(2),
                has_bounds: true,
                stop: LinearIndex(
                  setup: @[Instr(kind: InstrLen, tensor: loss, res: RegId(3))],
                  factors: to_table({RegId(3): 1})
                ),
                step: 1
              )],
              expr: Expr(
                instrs: @[Instr(kind: InstrScalar, scalar_lit: 1, res: RegId(1))],
                res: RegId(1)
              ),
              write: TensorOp(
                is_raw: true,
                tensor: grad_loss,
                dims: @[init_linear_index(RegId(2))],
                data: RegId(1)
              )
            ))
            target.copy_shape(grad_loss, loss)
            grad_tensors[loss] = grad_loss
          
          for it2 in (it + 1)..<target.kernels.len:
            let kernel = target.kernels[it2]
            if kernel.generator.kind == GenGradient:
              grad_tensors[kernel.generator.tensor] = kernel.write.tensor
              target.copy_shape(kernel.write.tensor, kernel.generator.tensor)
          
          for it2 in countdown(it - 1, 0):
            let kernel = target.kernels[it2]
            for read in kernel.reads:
              if read.tensor notin grad_tensors:
                let grad_tensor = program.tensors.alloc(TensorDef(
                  kind: TensorResult
                ))
                target.copy_shape(grad_tensor, read.tensor)
                grad_tensors[read.tensor] = grad_tensor
            
            if kernel.grad.is_custom:
              var subs = kernel.grad.subs
              for initial_tensor, grad in kernel.grad.tensors:
                var tensor = initial_tensor
                if tensor in kernel.grad.subs:
                  tensor = kernel.grad.subs[tensor]
                subs[grad] = grad_tensors[tensor]
              for it in countdown(kernel.grad.kernels.len - 1, 0):
                var grad_kernel = kernel.grad.kernels[it].clone()
                grad_kernel.substitute(subs)
                grad_kernels.add(grad_kernel)
            else:
              grad_kernels.add(kernel.derive(grad_tensors))
          
          target.kernels.delete(it)
          target.kernels.insert(grad_kernels, it)
          it += grad_kernels.len
        of GenGradient:
          target.kernels.delete(it)
        of GenReshape:
          target.kernels[it] = Kernel(
            regs: @[
              Register(typ: Type(kind: TypeScalar, count: 1)),
              Register(typ: Type(kind: TypeIndex, count: 1)),
              Register(typ: Type(kind: TypeIndex, count: 1))
            ],
            loops: @[Loop(iter: RegId(2),
              has_bounds: true,
              stop: LinearIndex(
                setup: @[Instr(kind: InstrLen,
                  tensor: kernel.generator.tensor, res: RegId(3)
                )],
                factors: to_table({RegId(3): 1})
              ),
              step: 1
            )],
            reads: @[TensorOp(
              tensor: kernel.generator.tensor,
              dims: @[init_linear_index(RegId(2))],
              data: RegId(1),
              is_raw: true
            )],
            expr: Expr(res: RegId(1)),
            write: TensorOp(
              tensor: kernel.write.tensor,
              dims: @[init_linear_index(RegId(2))],
              data: RegId(1),
              is_raw: true
            )
          )
          var
            shape = ShapeConstraint(kind: ShapeDims,
              dest: kernel.write.tensor
            )
            prod = 1
          for dim, size in kernel.generator.reshape:
            if size >= 0:
              prod *= size
          for dim, size in kernel.generator.reshape:
            if size >= 0:
              shape.dims.add(init_linear_index(size))
            else:
              shape.dims.add(LinearIndex(
                setup: @[
                  Instr(kind: InstrLen, tensor: kernel.generator.tensor, res: RegId(1)),
                  Instr(kind: InstrIndex, index_lit: prod, res: RegId(2)),
                  Instr(kind: InstrIndexDiv, args: @[RegId(1), RegId(2)], res: RegId(3))
                ],
                factors: to_table({RegId(3): 1})
              ))
          target.shapes.add(shape)
          it += 1
        of GenNone:
          it += 1

proc reorder_loops*(kernel: Kernel) =
  var loop_iters = new_seq[LoopId](kernel.regs.len)
  for it, loop in kernel.loops:
    loop_iters[loop.iter] = LoopId(it + 1)
  
  var graph = new_seq[array[TensorOpKind, seq[LoopId]]](kernel.loops.len)
  for kind, op in kernel.tensor_ops:
    for it in 1..<op.dims.len:
      for reg_a, factor_a in op.dims[it - 1].factors:
        for reg_b, factor_b in op.dims[it].factors:
          if loop_iters[reg_a] != LoopId(0) and
             loop_iters[reg_b] != LoopId(0):
            graph[int(loop_iters[reg_a]) - 1][kind].add(loop_iters[reg_b])
  
  const SCORE_VALS = [OpRead: 10, OpWrite: 1]
  var scores = new_seq[int](kernel.loops.len)
  for it, edges in graph:
    for kind, kind_edges in edges:
      for target in kind_edges:
        scores[target] += SCORE_VALS[kind]
  
  var
    closed = new_seq[bool](kernel.loops.len)
    order = new_seq[LoopId]()
  for it in 0..<kernel.loops.len:
    var
      min_score = 0
      min_loop = LoopId(0)
    for it, score in scores:
      if not closed[it]:
        if score < min_score or min_loop == LoopId(0):
          min_loop = LoopId(it + 1)
          min_score = score
    
    assert min_loop != LoopId(0)
    closed[min_loop] = true
    order.add(min_loop)
    
    for kind, edges in graph[min_loop]:
      for target in edges:
        scores[target] -= SCORE_VALS[kind]
  
  var new_loops = new_seq[Loop](order.len)
  for it, loop_id in order:
    new_loops[it] = kernel.loops[loop_id]
  kernel.loops = new_loops

proc reorder_loops*(program: Program) =
  program.assert_pass("reorder_loops",
    preserves=ALL_STAGES
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.reorder_loops()

proc unfold(linear: LinearIndex, regs: var seq[Register]): Expr =
  result.instrs = linear.setup
  
  var terms = new_seq[RegId]()
  for reg, factor in linear.factors:
    if factor != 0:
      if factor == 1:
        terms.add(reg)
      else:
        let (product, factor_reg) = (regs.alloc(), regs.alloc())
        result.instrs.add(Instr(kind: InstrIndex, index_lit: factor, res: factor_reg))
        result.instrs.add(Instr(kind: InstrMul, args: @[reg, factor_reg], res: product))
        terms.add(product)
  
  if linear.constant != 0:
    let reg = regs.alloc()
    result.instrs.add(Instr(kind: InstrIndex, index_lit: linear.constant, res: reg))
    terms.add(reg)
  
  if terms.len > 0:
    var sum = terms[0]
    for it in 1..<terms.len:
      let res = regs.alloc()
      result.instrs.add(Instr(kind: InstrAdd, args: @[sum, terms[it]], res: res))
      sum = res
    result.res = sum
  else:
    let zero = regs.alloc()
    result.instrs.add(Instr(kind: InstrIndex, res: zero))
    result.res = zero

proc expand_tensor_index(dims: seq[LinearIndex],
                         tensor: TensorId,
                         regs: var seq[Register],
                         shape: openArray[int] = []): Expr =
  var
    stride = RegId(0)
    terms = new_seq[RegId]()
  for it in countdown(dims.len - 1, 0):
    let
      dim = dims[it]
      dim_expr = dim.unfold(regs)
    result.instrs.add(dim_expr.instrs)
    
    if stride == RegId(0):
      terms.add(dim_expr.res)
    else:
      let product = regs.alloc()
      result.instrs.add(Instr(kind: InstrMul,
        args: @[dim_expr.res, stride],
        res: product
      ))
      terms.add(product)
    
    if it != 0:
      let size = regs.alloc()
      if it < shape.len and shape[it] >= 0:
        result.instrs.add(Instr(kind: InstrIndex,
          index_lit: shape[it], res: size
        ))
      else:
        result.instrs.add(Instr(kind: InstrShape,
          tensor: tensor, dim: it, res: size
        ))
      if stride == RegId(0):
        stride = size
      else:
        let new_stride = regs.alloc()
        result.instrs.add(Instr(kind: InstrMul,
          args: @[size, stride],
          res: new_stride
        ))
        stride = new_stride
  
  if terms.len == 0:
    let zero = regs.alloc()
    result.instrs.add(Instr(kind: InstrIndex, res: zero))
    result.res = zero
  else:
    var sum = terms[0]
    for it in 1..<terms.len:
      let new_sum = regs.alloc()
      result.instrs.add(Instr(kind: InstrAdd,
        args: @[sum, terms[it]],
        res: new_sum
      ))
      sum = new_sum
    result.res = sum

proc inline_tensor_ops(kernel: Kernel, has_written: var seq[bool]) =
  var instrs = [
    OpRead: new_seq[Instr](),
    OpWrite: new_seq[Instr]()
  ]
  
  for kind, tensor_op in kernel.tensor_ops:
    var args = new_seq[RegId]()
    if tensor_op.cache.exists:
      args.add(tensor_op.cache.reg)
    
    if tensor_op.is_raw:
      let dim = tensor_op.dims[0].unfold(kernel.regs)
      instrs[kind].add(dim.instrs)
      args.add(dim.res)
    else:
      let index =
        if tensor_op.cache.exists:
          var
            dims: seq[LinearIndex] = @[]
            cache_shape: seq[int] = @[]
          for it, dim in tensor_op.dims:
            let cache_dim = tensor_op.cache.dims[it]
            dims.add(dim - cache_dim.offset - init_linear_index(cache_dim.interval.min))
            cache_shape.add(cache_dim.interval.max - cache_dim.interval.min + 1)
          expand_tensor_index(dims, tensor_op.tensor, kernel.regs, cache_shape)
        else:
          expand_tensor_index(tensor_op.dims, tensor_op.tensor, kernel.regs)
      
      instrs[kind].add(index.instrs)
      args.add(index.res)
    
    var res = RegId(0)
    case kind:
      of OpRead: res = tensor_op.data
      of OpWrite: args.add(tensor_op.data)
    
    let instr_kind = case kind:
      of OpRead:
        if tensor_op.cache.exists:
          InstrArrayRead
        else:
          InstrRead
      of OpWrite:
        var can_overwrite = not has_written[tensor_op.tensor]
        for loop in kernel.loops:
          if loop.mode < LoopIndependent:
            can_overwrite = false
            break
        if can_overwrite:
          InstrOverwrite
        else:
          InstrWrite
    
    instrs[kind].add(Instr(kind: instr_kind,
      tensor: tensor_op.tensor,
      args: args,
      res: res
    ))
  
  has_written[kernel.write.tensor] = true
  kernel.expr.instrs = instrs[OpRead] & kernel.expr.instrs & instrs[OpWrite]
  kernel.expr.res = RegId(0)
  kernel.reads = new_seq[TensorOp]()
  kernel.write = TensorOp()

proc inline_tensor_ops*(program: Program) =
  program.assert_pass("inline_tensor_ops",
    requires={StageFolded, StageCacheSizes},
    produces={StageTensorInstrs},
    preserves={
      StageFolded, StageTensors, StageGenerated, StageBounds,
      StageTensorInstrs, StageShapes, StageSortedShapes,
      StageStaticShapes
    }
  )

  var has_written = new_seq[bool](program.tensors.len)
  for it, tensor in program.tensors:
    if tensor.kind != TensorResult:
      has_written[it] = true
  for name, target in program.targets.mpairs:
    for kernel in target.kernels:
      kernel.inline_tensor_ops(has_written)

proc collect_tensors(instrs: seq[Instr], tensors: var HashSet[TensorId]) =
  for instr in instrs:
    if instr.tensor != TensorId(0):
      tensors.incl(instr.tensor)
    instr.body.collect_tensors(tensors)

proc collect_tensors(instrs: seq[Instr]): HashSet[TensorId] =
  instrs.collect_tensors(result)

proc collect_tensors(kernel: Kernel, tensors: var HashSet[TensorId]) =
  for kind, op in kernel.tensor_ops:
    tensors.incl(op.tensor)
  for loop in kernel.loops:
    loop.start.setup.collect_tensors(tensors)
    loop.stop.setup.collect_tensors(tensors)
  kernel.expr.instrs.collect_tensors(tensors)

proc collect_tensors*(program: Program) =
  program.assert_pass("collect_tensors",
    requires={},
    produces={StageCollected},
    preserves=ALL_STAGES
  )
  
  for name, target in program.targets.mpairs:
    target.tensors = init_hash_set[TensorId]()
    for kernel in target.kernels:
      kernel.collect_tensors(target.tensors)

proc unfold_inplace(index: var LinearIndex, regs: var seq[Register]) =
  let expr = index.unfold(regs)
  index.setup = expr.instrs
  index.factors = to_table({expr.res: 1})
  index.constant = 0

proc unfold_loop_bounds*(program: Program) =
  program.assert_pass("unfold_loop_bounds",
    requires={StageFolded},
    preserves={
      StageTensors, StageGenerated, StageBounds,
      StageTensorInstrs, StageShapes, StageSortedShapes
    }
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      for loop in kernel.loops.mitems:
        loop.start.unfold_inplace(kernel.regs)
        loop.stop.unfold_inplace(kernel.regs)

proc peek_key[K, V](tab: Table[K, V]): K =
  for key, value in tab:
    return key

proc peek_value[K, V](tab: Table[K, V]): V =
  for key, value in tab:
    return value

proc only_register*(linear: LinearIndex): RegId =
  if linear.constant == 0 and
     linear.factors.len == 1 and
     linear.factors.peek_value() == 1:
    result = linear.factors.peek_key()

proc use_bounds(loop: var Loop, op: TensorOp, dim: int, regs: var seq[Register]) =
  loop.has_bounds = true
  loop.start = init_linear_index(0)
  let size = regs.alloc()
  loop.stop = init_linear_index(size)
  if op.is_raw:
    loop.stop.setup = @[Instr(kind: InstrLen,
      tensor: op.tensor, res: size
    )]
  else:
    loop.stop.setup = @[Instr(kind: InstrShape,
      tensor: op.tensor, dim: dim, res: size
    )]
  loop.step = 1

proc infer_loop_bounds*(program: Program) =
  program.assert_pass("infer_loop_bounds",
    requires={StageFolded},
    produces={StageBounds},
    preserves={
      StageFolded, StageShapes, StageSortedShapes,
      StageTensors, StageGenerated, StageStaticShapes
    }
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      var iters = init_table[RegId, LoopId]()
      for it, loop in kernel.loops:
        if not loop.has_bounds:
          iters[loop.iter] = LoopId(it + 1)
      for kind, op in kernel.tensor_ops:
        for it, dim in op.dims:
          if dim.only_register != RegId(0) and
             dim.only_register in iters:
            let loop_id = iters[dim.only_register]
            if not kernel.loops[loop_id].has_bounds:
              kernel.loops[loop_id].use_bounds(op, it, kernel.regs)

proc simplify_max_index(indices: var seq[LinearIndex]) =
  var
    max_constants = init_table[Table[RegId, int], int]()
    complex_indices = new_seq[LinearIndex]()
  for it, index in indices:
    if index.setup.len == 0:
      if index.factors notin max_constants:
        max_constants[index.factors] = index.constant
      else:
        max_constants[index.factors] = max(max_constants[index.factors], index.constant)
    else:
      complex_indices.add(index)
  
  indices = complex_indices
  for factors, constant in max_constants:
    indices.add(LinearIndex(
      factors: factors, constant: constant
    ))

proc infer_shape_constraints(kernel: Kernel): ShapeConstraint =
  if kernel.write.is_raw:
    if kernel.reads.len == 1:
      result = ShapeConstraint(kind: ShapeCopy,
        src: kernel.reads[0].tensor,
        dest: kernel.write.tensor
      )
  else:
    result = ShapeConstraint(kind: ShapeLinear)
    for op in kernel.reads:
      if not op.is_raw:
        if op.tensor notin result.reads:
          result.reads[op.tensor] = new_seq[seq[LinearIndex]](op.dims.len)
        for it, dim in op.dims:
          result.reads[op.tensor][it].add(dim)
    
    result.dest = kernel.write.tensor
    for it, dim in kernel.write.dims:
      result.write.add(dim)
    
    for tensor, dims in result.reads.mpairs:
      for dim in dims.mitems:
        dim.simplify_max_index()

proc infer_shape_constraints*(program: Program) =
  program.assert_pass("infer_shape_constraints",
    requires={StageFolded, StageTensors},
    produces={StageShapes},
    preserves={
      StageGenerated, StageFolded, StageTyped, StageTensors
    }
  )
  
  for name, target in program.targets.mpairs:
    for tensor in program.caches:
      let tensor_def = program.tensors[tensor]
      target.shapes.add(ShapeConstraint(kind: ShapeCopy,
        src: tensor_def.cache, dest: tensor
      ))
    
    for it, kernel in target.kernels:
      if kernel.generator.kind == GenNone:
        target.shapes.add(kernel.infer_shape_constraints())

iterator deps(shape: ShapeConstraint): TensorId =
  case shape.kind:
    of ShapeNone: discard
    of ShapeDims:
      for dim in shape.dims:
        for instr in dim.setup:
          if instr.tensor != TensorId(0):
            yield instr.tensor
    of ShapeLinear:
      for tensor in shape.reads.keys:
        yield tensor
    of ShapeCopy: yield shape.src

proc flatten_constraints(tensor: TensorId,
                         tensors: Table[TensorId, ShapeConstraint],
                         closed: var seq[bool],
                         order: var seq[ShapeConstraint],
                         program: Program) =
  if program.tensors[tensor].kind in {TensorResult, TensorCache, TensorRandom} and
     not closed[tensor]:
    closed[tensor] = true
    if tensor notin tensors:
      raise ShapeError(msg: $tensor & " (" & program.tensors[tensor].name & ") requires shape")
    let constr = tensors[tensor]
    for dep in constr.deps:
      dep.flatten_constraints(tensors, closed, order, program)
    order.add(constr)

proc sort_shape_constraints*(program: Program) =
  program.assert_pass("sort_shape_constraints",
    requires={StageShapes, StageCollected},
    produces={StageSortedShapes},
    preserves=ALL_STAGES
  )
  
  for name, target in program.targets.mpairs:
    var
      tensors = init_table[TensorId, ShapeConstraint]()
      closed = new_seq[bool](program.tensors.len)
    
    for constr in target.shapes:
      if constr.dest notin tensors:
        tensors[constr.dest] = constr
      else:
        discard # TODO: Unify current and new constraint
    
    var order = new_seq[ShapeConstraint]()
    for tensor in target.tensors:
      tensor.flatten_constraints(tensors, closed, order, program)
    
    target.shapes = order

type Matrix[T] = object
  data: seq[T]
  width: int

{.push inline.}
proc height(matrix: Matrix): int = matrix.data.len div matrix.width
proc `[]`[T](matrix: Matrix[T], y, x: int): T = matrix.data[x + y * matrix.width]
proc `[]`[T](matrix: var Matrix[T], y, x: int): var T = matrix.data[x + y * matrix.width]
proc `[]=`[T](matrix: var Matrix[T], y, x: int, value: T) = matrix.data[x + y * matrix.width] = value

proc `$`[T](matrix: Matrix[T]): string =
  for y in 0..<matrix.height:
    if y != 0:
      result &= "; "
    for x in 0..<matrix.width:
      if x != 0:
        result &= ", "
      result &= $matrix[y, x]
  result = "[" & result & "]"

proc swap_rows[T](matrix: var Matrix[T], a, b: int) =
  for x in 0..<matrix.width:
    swap(matrix[a, x], matrix[b, x])
{.pop.}

proc init_matrix[T](h, w: int): Matrix[T] =
  result = Matrix[T](width: w, data: new_seq[T](w * h))

type Fraction = Rational[int]
proc solve(equations: seq[LinearIndex]): Table[RegId, Fraction] =
  var indices = init_table[RegId, int]()
  for equation in equations:
    for reg, factor in equation.factors:
      if reg notin indices:
        indices[reg] = indices.len
  
  if indices.len == 0:
    return
  
  if equations.len < indices.len:
    raise new_exception(ValueError, "Underconstrained linear system")
  
  var
    matrix = init_matrix[int](indices.len, indices.len + 1)
    known = init_hash_set[seq[Fraction]]()
    y = 0
  for equation in equations:
    if equation.factors.len == 0:
      if equation.constant != 0:
        raise new_exception(ValueError, "No solution")
      continue
    
    var row = new_seq[int](matrix.width)
    for reg, factor in equation.factors:
      row[indices[reg]] = factor
    row[indices.len] = -equation.constant
    var
      normalized = new_seq[Fraction](matrix.width)
      first_value = 0
    for x, value in row:
      if first_value == 0:
        first_value = value
      if first_value == 0:
        normalized[x] = 0//1
      else:
        normalized[x] = value // first_value
    
    if normalized notin known:
      for x in 0..<matrix.width:
        matrix[y, x] = row[x]
      known.incl(normalized)
      y += 1
      if y >= matrix.height:
        break
  
  if y < matrix.height:
    raise new_exception(ValueError, "Underconstrained linear system")
  
  for pivot in 0..<matrix.height:
    var max_row = pivot
    for y in (pivot + 1)..<matrix.height:
      if abs(matrix[y, pivot]) > abs(matrix[max_row, pivot]):
        max_row = y
    if max_row != pivot:
      matrix.swap_rows(max_row, pivot)
    let target = matrix[pivot, pivot]
    for y in (pivot + 1)..<matrix.height:
      let cur = matrix[y, pivot]
      if cur != 0:
        for x in 0..<matrix.width:
          matrix[y, x] = matrix[y, x] * target - matrix[pivot, x] * cur
  
  var solutions = new_seq[Fraction](indices.len)
  for y in countdown(matrix.height - 1, 0):
    var sum = matrix[y, indices.len] // 1
    for x in (y + 1)..<indices.len:
      sum -= solutions[x] * matrix[y, x]
    solutions[y] = sum / (matrix[y, y] // 1)
  
  for reg, index in indices:
    result[reg] = solutions[index]

proc eval*(instrs: seq[Instr],
           shapes: Table[TensorId, seq[int]],
           regs: var Table[RegId, int]): bool =
  for instr in instrs:
    var can_eval = true
    for arg in instr.args:
      if arg notin regs:
        can_eval = false
        break
    if can_eval and instr.tensor != TensorId(0):
      can_eval = instr.tensor in shapes
    if can_eval:
      case instr.kind:
        of InstrShape:
          var size = -1
          let shape = shapes[instr.tensor]
          if instr.dim < 0:
            size = shape[shape.len + instr.dim]
          else:
            size = shape[instr.dim]
          regs[instr.res] = size
          if size < 0:
            result = true
        of InstrLen: regs[instr.res] = shapes[instr.tensor].prod()
        of InstrShapeLen: regs[instr.res] = shapes[instr.tensor].len
        of InstrIndex: regs[instr.res] = instr.index_lit
        of InstrAdd: regs[instr.res] = regs[instr.args[0]] + regs[instr.args[1]]
        of InstrSub: regs[instr.res] = regs[instr.args[0]] - regs[instr.args[1]]
        of InstrMul: regs[instr.res] = regs[instr.args[0]] * regs[instr.args[1]]
        of InstrIndexDiv: regs[instr.res] = regs[instr.args[0]] div regs[instr.args[1]]
        of InstrMod: regs[instr.res] = regs[instr.args[0]] mod regs[instr.args[1]]
        of InstrWrap:
          regs[instr.res] = regs[instr.args[0]] mod regs[instr.args[1]]
          if regs[instr.res] < 0:
            regs[instr.res] += regs[instr.args[1]]
        of InstrNegate: regs[instr.res] = -regs[instr.args[0]]
        else: raise ShapeError(msg: $instr.kind & " is not allowed in tensor shape definition")
    else:
      result = true

proc matches*(static_shape, shape: seq[int]): bool =
  if static_shape.len == 0:
    result = true
  elif static_shape.len == shape.len:
    for dim, size in static_shape:
      if size >= 0:
        if shape[dim] != static_shape[dim]:
          return false
    result = true

proc infer_shapes*(program: Program,
                   target: string,
                   inputs: openArray[(TensorId, seq[int])]): Table[TensorId, seq[int]] =
  result = init_table[TensorId, seq[int]]()
  for (tensor, shape) in inputs:
    result[tensor] = shape
    let static_shape = program.tensors[tensor].shape
    if not static_shape.matches(shape):
      raise ShapeError(msg: "Given shape for " & $tensor & " is " & $shape & ", but its static shape is " & $static_shape)
  for tensor_id in program.params:
    result[tensor_id] = program.tensors[tensor_id].shape
  for shape in program.targets[target].shapes:
    case shape.kind:
      of ShapeNone: discard
      of ShapeDims:
        var sizes = new_seq[int](shape.dims.len)
        for dim, index in shape.dims:
          var regs = init_table[RegId, int]()
          if index.setup.eval(result, regs):
            raise ShapeError(msg: "Unable to evaluate all instructions. Maybe you forgot to pass a required input tensor.")
          sizes[dim] = index.eval(regs)
        result[shape.dest] = sizes
      of ShapeCopy:
        result[shape.dest] = result[shape.src]
      of ShapeLinear:
        var equations: seq[LinearIndex] = @[]
        for tensor, dims in shape.reads:
          if tensor notin result:
            raise ShapeError(msg: "Shape of " & $tensor & " is not known, but required to infer the shape of " & $shape.dest & ". Maybe you forgot to pass a required input tensor.")
          for dim, indices in dims:
            assert indices.len == 1
            let index = indices[0]
            equations.add(index - (result[tensor][dim] - 1))
        
        var max_values = init_table[RegId, int]()
        for reg, max_value in solve(equations):
          max_values[reg] = max_value.num div max_value.den
        
        result[shape.dest] = new_seq[int](shape.write.len)
        for dim, index in shape.write:
          result[shape.dest][dim] = index.eval(max_values) + 1

proc infer_static_shapes*(program: Program) =
  program.assert_pass("infer_static_shapes",
    requires={StageSortedShapes},
    produces={StageStaticShapes},
    preserves=ALL_STAGES
  )
  
  var shapes = init_table[TensorId, seq[int]]()
  for it, tensor in program.tensors:
    let id = TensorId(it + 1)
    if tensor.shape.len > 0:
      shapes[id] = tensor.shape
  
  for name, target in program.targets:
    for shape in target.shapes:
      var dims: seq[int] = @[]
      case shape.kind:
        of ShapeNone: discard
        of ShapeDims:
          dims = new_seq[int](shape.dims.len)
          for dim, size in shape.dims:
            var regs = init_table[RegId, int]()
            if size.setup.eval(shapes, regs):
              dims[dim] = -1
            else:
              dims[dim] = size.eval(regs)
        of ShapeLinear:
          var equations: seq[LinearIndex] = @[]
          for tensor, dims in shape.reads:
            if tensor in shapes and shapes[tensor].len == dims.len:
              for dim, index in dims:
                assert index.len == 1
                let size = shapes[tensor][dim]
                if size >= 0:
                  equations.add(index[0] - (size - 1))
          
          var max_values = init_table[RegId, int]()
          for reg, max_value in solve(equations):
            max_values[reg] = max_value.num div max_value.den
          
          dims = new_seq[int](shape.write.len)
          for dim, size in shape.write:
            var can_eval = true
            for reg, factor in size.factors:
              if reg notin max_values:
                can_eval = false
                break
            if can_eval:
              dims[dim] = size.eval(max_values) + 1
            else:
              dims[dim] = -1
        of ShapeCopy:
          if shape.src in shapes:
            dims = shapes[shape.src]
      
      if dims.len > 0:
        if shape.dest in shapes:
          do_assert shapes[shape.dest] == dims
        else:
          shapes[shape.dest] = dims
  
  for it, tensor in program.tensors.mpairs:
    let id = TensorId(it + 1)
    case tensor.kind:
      of TensorResult, TensorRandom:
        if id in shapes:
          tensor.shape = shapes[id]
      of TensorCache:
        if id notin shapes or shapes[id].any_it(it < 0):
          let kind = ($tensor.kind)[len("Tensor")..^1].to_lower_ascii()
          raise ShapeError(msg: "Shape of " & kind & " \"" & tensor.name & "\" must be inferred at compile time")
        tensor.shape = shapes[id]
      else:
        if id in shapes:
          assert tensor.shape == shapes[id]

proc inline_static_shapes(instrs: var seq[Instr], tensors: seq[TensorDef]) =
  for instr in instrs.mitems:
    var size = -1
    if instr.tensor != TensorId(0) and
       tensors[instr.tensor].shape.len > 0:
      let shape = tensors[instr.tensor].shape
      case instr.kind:
        of InstrLen: size = shape.prod()
        of InstrShape:
          if instr.dim < 0:
            size = shape[shape.len + instr.dim]
          else:
            size = shape[instr.dim]
        of InstrShapeLen: size = shape.len
        else: discard
    if size >= 0:
      instr = Instr(kind: InstrIndex, index_lit: size, res: instr.res)

proc inline_static_shapes*(program: Program) =
  program.assert_pass("inline_static_shapes",
    produces={},
    requires={StageStaticShapes, StageBounds, StageTensorInstrs},
    preserves={
      StageTensors, StageFolded, StageShapes, StageSortedShapes,
      StageGenerated, StageTyped, StageBounds, StageTensorInstrs
    }
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.setup.inline_static_shapes(program.tensors)
      for loop in kernel.loops.mitems:
        loop.start.setup.inline_static_shapes(program.tensors)
        loop.stop.setup.inline_static_shapes(program.tensors)
        loop.cache.inline_static_shapes(program.tensors)
      kernel.expr.instrs.inline_static_shapes(program.tensors)

proc make_tensor_lookups*(program: Program) =
  program.assert_pass("make_tensor_lookups",
    produces={StageTensors},
    preserves=ALL_STAGES
  )
  
  for it, tensor in program.tensors:
    let id = TensorId(it + 1)
    case tensor.kind:
      of TensorParam: program.params.add(id)
      of TensorInput: program.inputs[tensor.name] = id
      of TensorCache: program.caches.add(id)
      else: discard

proc identify_independent*(kernel: Kernel) =
  var independent = init_hash_set[RegId]()
  for dim in kernel.write.dims:
    if dim.only_register != RegId(0):
      independent.incl(dim.factors.peek_key())
  for loop in kernel.loops.mitems:
    if loop.iter in independent:
      loop.mode = LoopIndependent

proc identify_independent*(program: Program) =
  program.assert_pass("identify_independent",
    produces={StageIndependent},
    requires={},
    preserves=ALL_STAGES
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.identify_independent()

proc choose_parallel*(program: Program) =
  program.assert_pass("choose_parallel",
    requires={StageIndependent},
    produces={},
    preserves=ALL_STAGES
  )
  
  const LOOP_COUNT = [
    CompileCpu: 0,
    CompileThreads: 1,
    CompileGpu: 3,
    CompileFpga: 0
  ]
  
  for name, target in program.targets:
    if LOOP_COUNT[target.compile_target] > 0:
      for kernel in target.kernels:
        var
          count = LOOP_COUNT[target.compile_target]
          parallel: seq[Loop] = @[]
          it = 0
        while it < kernel.loops.len and count > 0:
          var loop = kernel.loops[it]
          if loop.mode >= LoopIndependent:
            loop.mode = LoopParallel
            parallel.add(loop)
            count -= 1
            kernel.loops.delete(it)
          else:
            it += 1
        kernel.loops = parallel & kernel.loops

type
  BoundsMode = enum BoundsNone, BoundsDim, BoundsLen
  BoundsInfo = object
    mode: BoundsMode
    tensor: TensorId
    dim: int

proc bounds_info(loop: Loop): BoundsInfo =
  if loop.start.factors.len == 0 and
     loop.start.constant == 0 and
     loop.stop.only_register != RegId(0) and
     loop.stop.setup.len > 0 and
     loop.stop.only_register == loop.stop.setup[^1].res:
    result.tensor = loop.stop.setup[^1].tensor
    case loop.stop.setup[^1].kind:
      of InstrShape:
        result.mode = BoundsDim
        result.dim = loop.stop.setup[^1].dim
      of InstrLen:
        result.mode = BoundsLen
      else: discard

type
  TokenId = distinct int
  ShapeTokens = seq[seq[TokenId]]

proc `==`(a, b: TokenId): bool {.borrow.}
proc `$`(token: TokenId): string =
  if token == TokenId(0):
    result = "no_token"
  else:
    result = "token" & $(int(token) - 1)

proc alloc(tokens: var TokenId): TokenId =
  tokens = TokenId(int(tokens) + 1)
  result = tokens

proc build_shape_tokens(program: Program): ShapeTokens =
  program.assert_analysis("build_shape_tokens", requires={
    StageSortedShapes, StageStaticShapes, StageFolded
  })
  
  result = new_seq[seq[TokenId]](program.tensors.len)
  var
    tokens = TokenId(0)
    value_tokens = init_table[int, TokenId]()
  for it, tensor in program.tensors:
    result[it] = new_seq[TokenId](tensor.shape.len)
    for dim, size in tensor.shape:
      if size != -1:
        if size notin value_tokens:
          value_tokens[size] = tokens.alloc()
        result[it][dim] = value_tokens[size]
  
  for name, target in program.targets:
    for shape in target.shapes:
      case shape.kind:
        of ShapeNone: discard
        of ShapeDims:
          if result[shape.dest].len == 0:
            result[shape.dest] = new_seq[TokenId](shape.dims.len)
          for dim, size in shape.dims:
            if result[shape.dest][dim] == TokenId(0):
              if size.only_register != RegId(0) and
                 size.setup.len > 0 and
                 size.setup[^1].res == size.only_register and
                 size.setup[^1].kind == InstrShape:
                let instr = size.setup[^1]
                while result[instr.tensor].len <= instr.dim:
                  result[instr.tensor].add(tokens.alloc())
                result[shape.dest][dim] = result[instr.tensor][instr.dim]
              else:
                result[shape.dest][dim] = tokens.alloc()
        of ShapeLinear:
          var regs = init_table[RegId, TokenId]()
          for tensor, dims in shape.reads:
            while result[tensor].len < dims.len:
              result[tensor].add(tokens.alloc())
            for dim, size in dims:
              assert size.len == 1
              if size[0].only_register != RegId(0):
                regs[size[0].only_register] = result[tensor][dim]
          if result[shape.dest].len == 0:
            result[shape.dest] = new_seq[TokenId](shape.write.len)
          for dim, size in shape.write:
            if result[shape.dest][dim] == TokenId(0):
              if size.only_register in regs:
                result[shape.dest][dim] = regs[size.only_register]
              else:
                result[shape.dest][dim] = tokens.alloc()
        of ShapeCopy:
          result[shape.dest] = result[shape.src]

proc same_range(tokens: ShapeTokens, a, b: BoundsInfo): bool =
  if a.mode == b.mode:
    case a.mode:
      of BoundsNone: result = false
      of BoundsDim:
        result = tokens[a.tensor][a.dim] == tokens[b.tensor][b.dim]
      of BoundsLen:
        result = tokens[a.tensor] == tokens[b.tensor]

proc is_elementwise_map(kernel: Kernel): bool =
  if kernel.loops.len == 1:
    let
      iter = kernel.loops[0].iter
      info = kernel.loops[0].bounds_info
    result = kernel.reads.len == 1 and kernel.reads[0].is_raw and
             kernel.reads[0].dims[0].only_register == iter and
             kernel.write.is_raw and
             kernel.write.dims[0].only_register == iter and
             info.mode == BoundsLen and
             (info.tensor == kernel.reads[0].tensor or
              info.tensor == kernel.write.tensor)

proc nest_elementwise_map(kernel: Kernel, tensors: seq[TensorDef]) =
  kernel.loops = @[]
  kernel.reads[0].is_raw = false
  kernel.write.is_raw = false
  
  let tensor_id = kernel.reads[0].tensor
  var iters: seq[LinearIndex] = @[]
  for dim, size in tensors[tensor_id].shape:
    let iter = kernel.regs.alloc()
    iters.add(init_linear_index(iter))
    kernel.loops.add(Loop(iter: iter, has_bounds: true))
    kernel.loops[^1].use_bounds(kernel.reads[0], dim, kernel.regs)
  kernel.reads[0].dims = iters
  kernel.write.dims = iters

proc fuse_loops*(program: Program) =
  program.assert_pass("fuse_loops",
    requires={StageBounds, StageIndependent, StageStaticShapes},
    produces={},
    preserves={
      StageGenerated, StageTensors, StageShapes,
      StageSortedShapes, StageTensorInstrs, StageFolded,
      StageStaticShapes, StageBounds
    }
  )
  
  let shape_tokens = program.build_shape_tokens()
  for name, target in program.targets:
    if target.compile_target == CompileFpga:
      continue # TODO
    for kernel_it in 1..<target.kernels.len:
      let
        a = target.kernels[kernel_it - 1]
        b = target.kernels[kernel_it]
      
      if b.is_elementwise_map() and
         a.write.tensor == b.reads[0].tensor and
         a.loops.len > 0 and
         a.loops[0].bounds_info.mode == BoundsDim and
         a.loops[0].mode >= LoopIndependent and
         shape_tokens[b.reads[0].tensor] == shape_tokens[b.write.tensor]:
        b.nest_elementwise_map(program.tensors)
      
      if not a.write.is_raw and
         not b.reads.any_it(it.tensor == a.write.tensor and it.is_raw):
        for it in 0..<min(a.loops.len, b.loops.len):
          let
            a_loop = a.loops[it]
            b_loop = b.loops[it]
          if not shape_tokens.same_range(a_loop.bounds_info, b_loop.bounds_info):
            break
          var dim = -1
          for dim_it, index in a.write.dims:
            if index.only_register == a_loop.iter:
              dim = dim_it
              break
          if dim == -1:
            break
          let has_dependent_read = b.reads.any_it(
            it.tensor == a.write.tensor and
            it.dims[dim].only_register != b_loop.iter
          )
          if has_dependent_read:
            break
          a.loops[it].fuse_next = true

proc inline_conditions(kernel: Kernel) =
  if kernel.conds.len > 0:
    let body = kernel.expr.instrs
    kernel.expr.instrs = @[]
    
    var res = RegId(0)
    for cond in kernel.conds:
      kernel.expr.instrs.add(cond.instrs)
      if res == RegId(0):
        res = cond.res
      else:
        let new_res = kernel.regs.alloc()
        kernel.expr.instrs.add(Instr(kind: InstrAnd,
          args: @[res, cond.res],
          res: new_res
        ))
        res = new_res
    kernel.conds = @[]
    
    kernel.expr.instrs.add(Instr(kind: InstrIf,
      args: @[res],
      body: body
    ))

proc inline_conditions*(program: Program) =
  program.assert_pass("inline_conditions",
    produces={StageConditions},
    preserves={
      StageBounds, StageGenerated, StageTensors, StageShapes,
      StageSortedShapes, StageTensorInstrs
    }
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.inline_conditions()

proc tile_loops(kernel: Kernel) =
  var it = 0
  while it < kernel.loops.len:
    let loop = kernel.loops[it]
    if loop.schedule.tile and loop.mode < LoopParallel:
      let
        outer = Loop(
          iter: kernel.regs.alloc(),
          mode: loop.mode,
          has_bounds: true,
          start: loop.start,
          stop: loop.stop,
          step: loop.schedule.tile_size,
          schedule: loop.schedule
        )
        inner = Loop(
          iter: loop.iter,
          mode: LoopNone,
          has_bounds: true,
          start: LinearIndex(
            factors: to_table({outer.iter: 1})
          ),
          stop: LinearIndex(
            factors: to_table({outer.iter: 1}), # TODO: Check if in bounds
            constant: loop.schedule.tile_size
          ),
          step: 1,
          schedule: DEFAULT_LOOP_SCHEDULE
        )
      kernel.loops.delete(it)
      kernel.loops.insert([outer, inner], it)
      it += 2
    else:
      it += 1

proc tile_loops*(program: Program) =
  program.assert_pass("tile_loops",
    requires = {StageBounds, StageFolded},
    produces = {StageCacheSizes},
    preserves = {
      StageBounds, StageFolded, StageStaticShapes, StageGenerated,
      StageTensors, StageShapes, StageSortedShapes
    }
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.tile_loops()

proc bounds_size(loop: Loop): int =
  let size = loop.stop - loop.start
  if size.factors.len > 0:
    result = -1
  else:
    result = size.constant

proc eval(index: LinearIndex, regs: Table[RegId, OffsetInterval]): OffsetInterval =
  result.interval.min += index.constant
  result.interval.max += index.constant
  for reg, factor in index.factors:
    if reg in regs:
      result.offset = result.offset + regs[reg].offset * factor
      result.interval = result.interval + regs[reg].interval * factor
    else:
      result.offset = result.offset + LinearIndex(factors: to_table({reg: factor}))

proc infer_cache_sizes(kernel: Kernel, compile_target: CompileTarget) =
  if kernel.reads.any_it(it.schedule.cache):
    var cache_level = kernel.loops.len
    while cache_level > 0 and
          kernel.loops[cache_level - 1].mode < LoopParallel and
          kernel.loops[cache_level - 1].bounds_size >= 0:
      cache_level -= 1
    
    var regs = init_table[RegId, OffsetInterval]()
    for it in cache_level..<kernel.loops.len:
      let loop = kernel.loops[it]
      regs[loop.iter] = OffsetInterval(
        offset: loop.start,
        interval: Interval(min: 0, max: loop.bounds_size - 1)
      )
    if compile_target == CompileGpu:
      for it in 0..<cache_level:
        template loop: var Loop = kernel.loops[it]
        if loop.mode >= LoopParallel:
          if loop.tile_offset == RegId(0):
            loop.tile_offset = kernel.regs.alloc()
          regs[loop.iter] = OffsetInterval(
            offset: init_linear_index(loop.tile_offset),
            interval: Interval(min: 0, max: loop.schedule.tile_size - 1)
          )
    
    for read in kernel.reads.mitems:
      if read.is_raw:
        continue # TODO: Support raw reads
      var cache = LocalCache(
        exists: true,
        level: cache_level,
        reg: kernel.regs.alloc()
      )
      if read.schedule.cache:
        for dim in read.dims:
          cache.dims.add(dim.eval(regs))
      read.cache = cache

proc infer_cache_sizes*(program: Program) =
  program.assert_pass("infer_cache_sizes",
    requires = {StageBounds, StageFolded},
    produces = {StageCacheSizes},
    preserves = {
      StageBounds, StageFolded, StageStaticShapes, StageGenerated,
      StageTensors, StageShapes, StageSortedShapes
    }
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.infer_cache_sizes(target.compile_target)

proc cache_tensor(read: TensorOp, kernel: Kernel, compile_target: CompileTarget): seq[Instr] =
  type CacheSize = enum
    CacheEqualShape,
    CacheSmaller,
    CacheEqualSize,
    CacheLarger
  
  var cache_shape: seq[int] = @[]
  for dim in read.cache.dims:
    cache_shape.add(dim.interval.max - dim.interval.min + 1)
  result.add(Instr(kind: InstrSharedCache,
    cache_size: cache_shape.prod(),
    res: read.cache.reg
  ))
  
  var
    thread_shape: seq[int] = @[]
    local_offset_iters: seq[RegId] = @[]
    offset = LinearIndex()
    stride = 1
  if compile_target == CompileGpu:
    for it in countdown(kernel.loops.len - 1, 0):
      template loop: var Loop = kernel.loops[it]
      if loop.mode >= LoopParallel:
        thread_shape.add(loop.schedule.tile_size)
        if loop.local_offset == RegId(0):
          loop.local_offset = kernel.regs.alloc()
        local_offset_iters.add(loop.local_offset)
        offset.factors[loop.local_offset] = stride
        stride *= loop.schedule.tile_size
  
  thread_shape.reverse()
  local_offset_iters.reverse()
  
  let cache_size =
    if thread_shape == cache_shape:
      CacheEqualShape
    elif cache_shape.prod() < thread_shape.prod():
      CacheSmaller
    elif cache_shape.prod() == thread_shape.prod():
      CacheEqualSize
    else:
      CacheLarger
  
  let start = offset.unfold(kernel.regs)
  result.add(start.instrs)
  
  let iter =
    if cache_size in {CacheEqualShape, CacheSmaller, CacheEqualSize}:
      start.res
    else:
      kernel.regs.alloc()
  
  var body: seq[Instr] = @[]
  
  var
    dims: seq[LinearIndex] = @[]
    cur = iter
  for it in countdown(read.cache.dims.len - 1, 0):
    let
      dim = read.cache.dims[it]
      size = dim.interval.max - dim.interval.min + 1
      size_reg = kernel.regs.alloc()
    
    let local_offset =
      if cache_size == CacheEqualShape:
        local_offset_iters[it]
      elif it == 0:
        cur
      else:
        let offset = kernel.regs.alloc()
        body.add(Instr(kind: InstrIndex,
          index_lit: size,
          res: size_reg
        ))
        body.add(Instr(kind: InstrMod,
          args: @[cur, size_reg],
          res: offset
        ))
        let new_cur = kernel.regs.alloc()
        body.add(Instr(kind: InstrIndexDiv,
          args: @[cur, size_reg],
          res: new_cur
        ))
        cur = new_cur
        offset
    
    let read_dim = unfold(dim.offset + local_offset.init_linear_index(), kernel.regs)
    body.add(read_dim.instrs)
    dims.add(init_linear_index(read_dim.res))
  
  dims.reverse()
  let index = expand_tensor_index(dims, read.tensor, kernel.regs)
  body.add(index.instrs)
  let value = kernel.regs.alloc()
  body.add(Instr(kind: InstrRead,
    args: @[index.res],
    tensor: read.tensor,
    res: value
  ))
  body.add(Instr(kind: InstrCacheWrite,
    args: @[read.cache.reg, iter, value]
  ))
  
  if cache_size in {CacheEqualShape, CacheEqualSize}:
    result.add(body)
  else:
    let stop = kernel.regs.alloc()
    result.add(Instr(kind: InstrIndex,
      index_lit: cache_shape.prod(),
      res: stop
    ))
    if cache_size == CacheSmaller:
      let cond = kernel.regs.alloc()
      result.add(Instr(kind: InstrLt,
        args: @[iter, stop],
        res: cond
      ))
      result.add(Instr(kind: InstrIf,
        args: @[cond],
        body: body
      ))
    else:
      result.add(Instr(kind: InstrLoop,
        args: @[start.res, stop],
        loop_iter: iter,
        loop_step: thread_shape.prod(),
        body: body
      ))

proc cache_tensors*(kernel: Kernel, compile_target: CompileTarget) =
  for read in kernel.reads:
    if read.cache.exists:
      let instrs = cache_tensor(read, kernel, compile_target)
      if read.cache.level == 0:
        kernel.setup.add(instrs)
      else:
        kernel.loops[read.cache.level - 1].cache.add(instrs)

proc cache_tensors*(program: Program) =
  program.assert_pass("cache_tensors",
    requires = {StageCacheSizes},
    preserves = {
      StageBounds, StageFolded, StageStaticShapes, StageGenerated,
      StageTensors, StageShapes, StageSortedShapes, StageCacheSizes
    }
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.cache_tensors(target.compile_target)

proc inline_loop(kernel: Kernel, compile_target: CompileTarget) =
  let loop = kernel.loops.pop()
  if loop.cache.len > 0:
    if compile_target == CompileGpu:
      kernel.expr.instrs.insert(Instr(kind: InstrBarrier))
    kernel.expr.instrs.insert(loop.cache)
    if compile_target == CompileGpu:
      kernel.expr.instrs.insert(Instr(kind: InstrBarrier))
  if loop.mode >= LoopParallel:
    case compile_target:
      of CompileCpu, CompileFpga:
        raise StageError(msg: "Parallel loops are not supported by CPU target")
      of CompileThreads:
        let (range_begin, range_end) = (kernel.regs.alloc(), kernel.regs.alloc())
        kernel.expr.instrs = @[Instr(kind: InstrThreads,
          args: @[loop.start.only_register, loop.stop.only_register],
          threads_begin: range_begin, threads_end: range_end,
          body: @[Instr(kind: InstrLoop,
            args: @[range_begin, range_end],
            loop_iter: loop.iter,
            loop_step: 1,
            body: kernel.expr.instrs
          )]
        )]
      of CompileGpu:
        var
          instr = Instr(kind: InstrGpu,
            args: @[loop.start.only_register, loop.stop.only_register]
          )
          loops = @[loop]
        while kernel.loops.len > 0 and
              kernel.loops[^1].mode >= LoopParallel:
          let loop = kernel.loops.pop()
          loops.add(loop)
          instr.args.add([loop.start.only_register, loop.stop.only_register])
        
        var conds: seq[RegId] = @[]
        for it, loop in loops:
          let
            local_offset =
              if loop.local_offset != RegId(0):
                loop.local_offset
              else:
                kernel.regs.alloc()
            index = GpuIndex(
              group: kernel.regs.alloc(),
              local: local_offset,
              size: loop.schedule.tile_size
            )
            offset =
              if loop.tile_offset != RegId(0):
                loop.tile_offset
              else:
                kernel.regs.alloc()
            size_reg = kernel.regs.alloc()
          instr.body.add(Instr(kind: InstrIndex,
            index_lit: index.size,
            res: size_reg
          ))
          instr.body.add(Instr(kind: InstrMul,
            args: @[index.group, size_reg],
            res: offset
          ))
          instr.body.add(Instr(kind: InstrAdd,
            args: @[offset, index.local],
            res: loop.iter
          ))
          instr.gpu_indices.add(index)
          
          if loop.stop.setup[^1].kind != InstrIndex or
             loop.stop.setup[^1].index_lit mod index.size != 0:
            let
              is_in_range = kernel.regs.alloc()
              max = loop.stop.setup[^1].res
            instr.body.add(Instr(kind: InstrLt,
              args: @[loop.iter, max],
              res: is_in_range
            ))
            conds.add(is_in_range)
        
        if conds.len > 0:
          var cond = conds[0]
          for it in 1..<conds.len:
            let res = kernel.regs.alloc()
            instr.body.add(Instr(kind: InstrAnd,
              args: @[cond, conds[it]],
              res: res
            ))
            cond = res
          instr.body.add(Instr(kind: InstrIf,
            args: @[cond],
            body: kernel.expr.instrs
          ))
        else:
          instr.body.add(kernel.expr.instrs)
        
        kernel.expr.instrs = @[instr]
        for loop in loops:
          kernel.expr.instrs.insert(loop.start.setup)
          kernel.expr.instrs.insert(loop.stop.setup)
        return
  else:
    case compile_target:
      of CompileFpga:
        var instr = Instr(kind: InstrNestedLoops, body: kernel.expr.instrs)
        kernel.expr.instrs = @[]
        for loop in kernel.loops:
          instr.args.add([loop.start.only_register, loop.stop.only_register])
          instr.nested_loops.add((loop.iter, loop.step))
          kernel.expr.instrs.insert(loop.start.setup)
          kernel.expr.instrs.insert(loop.stop.setup)
        kernel.loops = @[]
        instr.args.add([loop.start.only_register, loop.stop.only_register])
        instr.nested_loops.add((loop.iter, loop.step))
        kernel.expr.instrs.add(instr)
      else:
        kernel.expr.instrs = @[Instr(kind: InstrLoop,
          args: @[loop.start.only_register, loop.stop.only_register],
          loop_iter: loop.iter,
          loop_step: loop.step,
          loop_fuse_next: loop.fuse_next,
          body: kernel.expr.instrs
        )]
  kernel.expr.instrs.insert(loop.start.setup)
  kernel.expr.instrs.insert(loop.stop.setup)

proc inline_loops(target: Target, cur, until_level: int) =
  let kernel = target.kernels[cur]
  while kernel.loops.len > until_level:
    while kernel.loops[^1].fuse_next:
      target.inline_loops(cur + 1, kernel.loops.len)
      let next_kernel = target.kernels[cur + 1]
      var
        instrs = next_kernel.expr.instrs
        setup = next_kernel.setup
        subs = init_table[RegId, RegId]()
      for it in 0..<kernel.loops.len:
        subs[next_kernel.loops[it].iter] = kernel.loops[it].iter
      for it in 0..<next_kernel.regs.len:
        let reg = RegId(it + 1)
        if reg notin subs:
          subs[reg] = kernel.regs.alloc(next_kernel.regs[it])
      instrs.substitute(subs)
      setup.substitute(subs)
      kernel.expr.instrs.add(instrs)
      kernel.setup.add(setup)
      for it in 0..<kernel.loops.len:
        kernel.loops[it].fuse_next = next_kernel.loops[it].fuse_next
      target.kernels.delete(cur + 1)
    kernel.inline_loop(target.compile_target)

proc inline_loops*(program: Program) =
  program.assert_pass("inline_loops",
    requires={StageBounds, StageConditions},
    produces={StageLoops},
    preserves={
      StageGenerated, StageTensors, StageShapes,
      StageSortedShapes, StageTensorInstrs, StageConditions
    }
  )
  
  for name, target in program.targets.mpairs:
    var it = 0
    while it < target.kernels.len:
      target.inline_loops(it, 0)
      it += 1
    
    for kernel in target.kernels:
      kernel.setup.add(kernel.expr.instrs)
      kernel.expr = Expr()

proc lift_invariants(instrs: var seq[Instr],
                     regs: var seq[int],
                     levels: var seq[seq[Instr]],
                     min_level: int) =
  var it = 0
  while it < instrs.len:
    let instr = instrs[it]
    if instr.body.len > 0:
      levels.add(@[])
      var body_min_level = min_level
      case instr.kind:
        of InstrLoop:
          regs[instr.loop_iter] = levels.len
        of InstrThreads:
          regs[instr.threads_begin] = levels.len
          regs[instr.threads_end] = levels.len
          body_min_level = levels.len
        of InstrGpu:
          for index in instr.gpu_indices:
            regs[index.local] = levels.len
            regs[index.group] = levels.len
          body_min_level = levels.len
        of InstrIf:
          body_min_level = levels.len # TODO: Only for InstrRead, InstrArrayRead, ...
        of InstrNestedLoops:
          for (iter, step) in instr.nested_loops:
            regs[iter] = levels.len
        else: discard
      instrs[it].body.lift_invariants(regs, levels, body_min_level)
      let level = levels.pop()
      instrs.insert(level, it)
      it += level.len
    
    if instr.kind in SIDE_EFFECT_INSTRS:
      if instr.res != RegId(0):
        regs[instr.res] = levels.len 
    else:
      var instr_level = 0
      if instr.kind notin {InstrShape, InstrLen, InstrShapeLen, InstrEpoch}:
        instr_level = min_level
      
      for arg in instr.args:
        if regs[arg] > instr_level:
          instr_level = regs[arg]
      
      if instr.res != RegId(0):
        regs[instr.res] = instr_level
      
      if instr_level < levels.len:
        levels[instr_level].add(instr)
        instrs.delete(it)
        continue
    
    it += 1

proc lift_invariants*(program: Program) =
  program.assert_pass("lift_invariants",
    produces={},
    requires={StageTensorInstrs},
    preserves={
      StageGenerated, StageTensors, StageShapes,
      StageSortedShapes, StageBounds,
      StageTensorInstrs, StageLoops, StageConditions
    }
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      var
        regs = new_seq[int](kernel.regs.len)
        levels: seq[seq[Instr]] = @[]
      kernel.setup.lift_invariants(regs, levels, 0)

proc collect_closures(instrs: var seq[Instr], regs: var seq[int], level: int): HashSet[RegId] =
  for instr in instrs.mitems:
    var used = instr.body.collect_closures(regs, level + 1)
    
    # TODO: Refactor using iterator which returns all registers defined by the instruction
    case instr.kind:
      of InstrLoop:
        regs[instr.loop_iter] = level + 1
      of InstrThreads:
        regs[instr.threads_begin] = level + 1
        regs[instr.threads_end] = level + 1
      of InstrGpu:
        for index in instr.gpu_indices:
          regs[index.local] = level + 1
          regs[index.group] = level + 1
      else: discard
    
    if instr.kind in {InstrThreads, InstrGpu}:
      var closure = ParallelClosure()
      for reg in used:
        if regs[reg] <= level:
          closure.regs.add(reg)
      
      var tensors: seq[TensorId] = @[]
      for tensor in instr.body.collect_tensors():
        closure.tensors.add(tensor)
      
      case instr.kind:
        of InstrThreads: instr.threads_closure = closure
        of InstrGpu: instr.gpu_closure = closure
        else: discard
    
    for arg in instr.args:
      used.incl(arg)
    
    if instr.res != RegId(0):
      regs[instr.res] = level
    
    result = result.union(used)

proc collect_closures*(program: Program) =
  program.assert_pass("collect_closures",
    produces={},
    requires={StageLoops},
    preserves={
      StageGenerated, StageTensors, StageShapes,
      StageSortedShapes, StageBounds,
      StageTensorInstrs, StageLoops, StageConditions
    }
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      var regs = new_seq[int](kernel.regs.len)
      discard kernel.setup.collect_closures(regs, 0)

proc extract_closure(regs: seq[bool], closure: ParallelClosure): seq[bool] =
  result = new_seq[bool](regs.len)
  for reg in closure.regs:
    if not regs[reg]:
      raise ValidationError(msg: $reg & " cannot be captured because it is not defined")
    result[reg] = regs[reg]

proc validate(instrs: seq[Instr], regs: var seq[bool]) =
  for instr in instrs:
    for arg in instr.args:
      if not regs[arg]:
        raise ValidationError(msg: $arg & " is not defined")
    
    case instr.kind:
      of InstrIf:
        instr.body.validate(regs)
      of InstrLoop:
        regs[instr.loop_iter] = true
        instr.body.validate(regs)
      of InstrThreads:
        var closure = regs.extract_closure(instr.threads_closure)
        closure[instr.threads_begin] = true
        closure[instr.threads_end] = true
        instr.body.validate(closure)
      of InstrGpu:
        var closure = regs.extract_closure(instr.gpu_closure)
        for index in instr.gpu_indices:
          closure[index.local] = true
          closure[index.group] = true
        instr.body.validate(closure)
      of InstrNestedLoops:
        for (iter, step) in instr.nested_loops:
          regs[iter] = true
        instr.body.validate(regs)
      else: discard
    
    if instr.res != RegId(0):
      regs[instr.res] = true

proc validate(index: LinearIndex, regs: var seq[bool]) =
  index.setup.validate(regs)
  for reg, factor in index.factors:
    if not regs[reg]:
      raise ValidationError(msg: $reg & " is not defined")

proc validate(kernel: Kernel) =
  if kernel.generator.kind != GenNone:
    return
  var regs = new_seq[bool](kernel.regs.len)
  kernel.setup.validate(regs)
  for loop in kernel.loops:
    loop.start.validate(regs)
    loop.stop.validate(regs)
    regs[loop.iter] = true
  # TODO: Conditions, Write, Read Index
  for read in kernel.reads:
    regs[read.data] = true
  kernel.expr.instrs.validate(regs)

proc validate*(program: Program) =
  program.assert_pass("validate", preserves = ALL_STAGES)
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.validate()

type ConstValue = object
  is_const: bool
  case typ: TypeKind:
    of TypeBoolean: boolean_val: bool
    of TypeIndex: index_val: int
    of TypeScalar: scalar_val: float64
    else: discard

proc prop_constants(instrs: var seq[Instr], consts: var seq[ConstValue], regs: var seq[Register]) =
  var setup: seq[Instr] = @[]
  for instr in instrs.mitems:
    if instr.body.len > 0:
      instr.body.prop_constants(consts, regs)
    
    template binop(op) =
      let
        a = consts[instr.args[0]]
        b = consts[instr.args[1]]
      if a.is_const and b.is_const:
        if a.typ == TypeIndex:
          consts[instr.res] = ConstValue(
            is_const: true,
            typ: TypeIndex,
            index_val: op(a.index_val, b.index_val)
          )
        elif a.typ == TypeScalar:
          consts[instr.res] = ConstValue(
            is_const: true,
            typ: TypeScalar,
            scalar_val: op(a.scalar_val, b.scalar_val)
          )
    
    case instr.kind:
      of InstrIndex: consts[instr.res] = ConstValue(is_const: true, typ: TypeIndex, index_val: instr.index_lit)
      of InstrScalar: consts[instr.res] = ConstValue(is_const: true, typ: TypeScalar, scalar_val: instr.scalar_lit)
      of InstrBoolean: consts[instr.res] = ConstValue(is_const: true, typ: TypeBoolean, boolean_val: instr.boolean_lit)
      of InstrAdd: binop(`+`)
      of InstrSub: binop(`-`)
      of InstrMul: binop(`*`)
      of InstrDiv:
        if not consts[instr.args[0]].is_const and
           consts[instr.args[1]].is_const and
           consts[instr.args[1]].typ == TypeScalar:
          let factor = regs.alloc()
          setup.add(Instr(kind: InstrScalar,
            scalar_lit: 1.0 / consts[instr.args[1]].scalar_val,
            res: factor
          ))
          instr = Instr(kind: InstrMul,
            args: @[instr.args[0], factor],
            res: instr.res
          )
      of InstrToScalar:
        if consts[instr.args[0]].is_const and consts[instr.args[0]].typ == TypeIndex:
          consts[instr.res] = ConstValue(
            is_const: true,
            typ: TypeScalar,
            scalar_val: float64(consts[instr.args[0]].index_val)
          )
      of InstrToIndex:
        if consts[instr.args[0]].is_const and consts[instr.args[0]].typ == TypeScalar:
          consts[instr.res] = ConstValue(
            is_const: true,
            typ: TypeIndex,
            index_val: int(consts[instr.args[0]].scalar_val)
          )
      else: discard
    
    if instr.kind notin {InstrIndex, InstrScalar, InstrBoolean} and
       instr.res != RegId(0) and
       consts[instr.res].is_const:
      let value = consts[instr.res]
      case value.typ:
        of TypeIndex: instr = Instr(kind: InstrIndex, index_lit: value.index_val, res: instr.res)
        of TypeScalar: instr = Instr(kind: InstrScalar, scalar_lit: value.scalar_val, res: instr.res)
        of TypeBoolean: instr = Instr(kind: InstrBoolean, boolean_lit: value.boolean_val, res: instr.res)
        else: discard
  
  if setup.len > 0:
    instrs.insert(setup)

proc prop_constants(kernel: Kernel) =
  var consts = new_seq[ConstValue](kernel.regs.len)
  kernel.setup.prop_constants(consts, kernel.regs)
  kernel.expr.instrs.prop_constants(consts, kernel.regs)

proc prop_constants*(program: Program) =
  program.assert_pass("prop_constants",
    requires={},
    preserves = ALL_STAGES - {StageTyped}
  )
  
  for name, target in program.targets:
    for kernel in target.kernels:
      kernel.prop_constants()
