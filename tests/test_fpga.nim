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

# Unit-tests for compiling exprgrad kernels to an FPGA

import std/[tables, random]
import exprgrad, exprgrad/[ir, irprint, model, passes, parser, logicgen, fpga/logicdsl, fpga/utils, graphics/dotgraph]
import exprgrad/fpga/platform/ulx3s
import ../tools/test_framework

randomize(10)

test "matmul/passes":
  hidden*[y, x] ++= input("x", [4, 2])[y, it] * param([2, 4])[it, x] | (y, x, it)
  hidden[y, x] ++= param([4])[x] | (y, x)
  hidden_relu*{it} ++= select(hidden{it} <= 0.0, 0.1 * hidden{it}, hidden{it}) | it
  output*[y, x] ++= hidden_relu[y, it] * param([4, 1])[it, x] | (y, x, it)
  output[y, x] ++= param([1])[x] | (y, x)
  output_sigmoid*{it} ++= (
    let x = output{it} + 0.5;
    select(x <= 0.0,
      0.1 * x,
      select(x >= 1.0, 0.9 + 0.1 * x, x)
    )
  ) | it #1.0 / (1.0 + exp(-output{it})) | it
  let pred = output_sigmoid#.target("predict", CompileFpga)
  
  proc optim(param: var Fun, grad: Fun) =
    param{it} ++= -0.1 * grad{it} | it
  loss*[0] ++= sq(pred{it} - input("y", [4, 1]){it}) | it
  let net = loss.target("loss", CompileFpga).backprop(optim).target("train", CompileFpga)
  
  let program = to_program([net])
  program.scalar_type = ScalarType(bits: 16, is_fixed: true, fixed_point: 8)
  program.index_type = IndexType(bits: 16)
  program.compile()
  
  echo program.targets["loss"]
  
  let program_circuit = program.to_circuit({
    "x": new_tensor([4, 2], @[float64 0, 0, 0, 1, 1, 0, 1, 1]),
    "y": new_tensor([4, 1], @[float64 0, 1, 1, 1])
  })
  
  
  write_file("output.gv", program_circuit.to_dot_graph())
  
  let platform = Ulx3s.new("ulx3s_v20.lpf")
  echo circuit.to_verilog(platform)
  circuit.upload(platform)
  #circuit.save_verilog("output.v", target_spec)
