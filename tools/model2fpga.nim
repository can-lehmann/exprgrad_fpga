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

# Convert a exprgrad model to a circuit

import std/[os, tables, sets, sequtils, strutils]
import ../exprgrad, ../exprgrad/[ir, irprint, logicgen, passes]
import ../exprgrad/fpga/[logicdsl, ui, platform/ulx3s]
import ../exprgrad/io/[faststreams, serialize]
import ../exprgrad/graphics/dotgraph

proc peek[T](items: HashSet[T]): T =
  for item in items:
    return item

type ModelDescr = object
  source: Program
  params: Table[TensorId, Tensor[float64]]
  caches: Table[TensorId, Tensor[float64]]

proc load*(stream: var ReadStream, model: var ModelDescr) =
  var is_nil = false
  stream.load(is_nil)
  if not is_nil:
    stream.load(model.source)
    stream.load(model.params)
    stream.load(model.caches)
  else:
    raise new_exception(ValueError, "Saved model is nil")

proc load_model_descr(path: string): ModelDescr =
  var stream = open_read_stream(path)
  stream.load(result)

type
  ActionKind = enum
    ActionPrintIr, ActionRawVerilog, ActionVerilog, ActionGraph, ActionBitstream, ActionFlash
  
  Action = object
    path: string
    kind: ActionKind
  
  Args = object
    path: string
    inputs: seq[(string, Tensor[float64])]
    scalar_type: ScalarType
    index_type: IndexType
    targets: HashSet[string]
    lpf_path: string
    mainloop: bool
    actions: seq[Action]

proc parse_args(): Args =
  result.scalar_type = ScalarType(bits: 16, is_fixed: true, fixed_point: 8)
  result.index_type = IndexType(bits: 16)
  
  var it = 1
  
  proc take_param(it: var int): string =
    result = param_str(it)
    it += 1
  
  while it <= param_count():
    let param = take_param(it)
    
    if param[0] == '-':
      case param:
        of "-i":
          let
            name = take_param(it)
            shape = take_param(it)
            value = take_param(it)
          
          result.inputs.add((
            name,
            new_tensor[float64](
              shape.split("x").map_it(it.strip().parse_int()),
              value.split(",").map_it(it.strip().parse_float())
            )
          ))
        of "-f": result.actions.add(Action(kind: ActionFlash))
        of "-p": result.actions.add(Action(kind: ActionPrintIr))
        of "-v": result.actions.add(Action(kind: ActionVerilog, path: take_param(it)))
        of "-V": result.actions.add(Action(kind: ActionRawVerilog, path: take_param(it)))
        of "-g": result.actions.add(Action(kind: ActionGraph, path: take_param(it)))
        of "-b": result.actions.add(Action(kind: ActionBitstream, path: take_param(it)))
        of "-S":
          let parts = take_param(it).split(".")
          if parts.len != 2:
            raise new_exception(ValueError, "")
          let (before_point, after_point) = (parts[0].parse_int(), parts[1].parse_int())
          result.scalar_type = ScalarType(
            bits: before_point + after_point,
            is_fixed: true,
            fixed_point: after_point
          )
        of "-I": result.index_type = IndexType(bits: take_param(it).parse_int())
        of "-t": result.targets.incl(take_param(it))
        of "-l": result.lpf_path = take_param(it)
        of "-m": result.mainloop = true
        else:
          raise new_exception(ValueError, "Invalid option " & param)
    else:
      result.path = param
  if result.path.len == 0:
    raise new_exception(ValueError, "Missing model path")

when is_main_module:
  let
    args = parse_args()
    model = load_model_descr(args.path)
    program = model.source.clone()
  
  program.scalar_type = args.scalar_type
  program.index_type = args.index_type
  for target in args.targets:
    if target notin program.targets:
      raise new_exception(ValueError, "Model does not have target " & target)
    program.targets[target].compile_target = CompileFpga
  
  program.make_tensor_lookups()
  for (name, input) in args.inputs:
    let id = program.inputs[name]
    if not program.tensors[id].shape.matches(input.shape):
      raise ShapeError(msg: "Static shape for " & name & " does not match actual shape")
    program.tensors[id].shape = input.shape
  
  program.compile()
  echo program
  let
    program_circuit = program.to_circuit(args.inputs, model.params, model.caches, mainloop=args.mainloop)
    platform = Ulx3s.new(args.lpf_path)
    circuit = program_circuit.wrap_ui(program, args.targets.peek())
  
  for action in args.actions:
    case action.kind:
      of ActionPrintIr:
        echo program
      of ActionGraph:
        write_file(action.path, program_circuit.to_dot_graph())
      of ActionVerilog:
        circuit.save_verilog(action.path, platform)
      of ActionRawVerilog:
        write_file(action.path, program_circuit.to_verilog())
      of ActionBitstream:
        let path = circuit.build(platform)
        copy_file(path, action.path)
      of ActionFlash:
        circuit.upload(platform)
