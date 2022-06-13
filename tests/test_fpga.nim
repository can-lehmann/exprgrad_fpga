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

import std/[tables]
import exprgrad, exprgrad/[ir, irprint, model, passes, parser, logicgen, fpga/logicdsl, graphics/dotgraph]
import exprgrad/fpga/platform/ulx3s
import ../tools/test_framework

test "matmul/passes":
  let
    a = input("a", [2, 3])
    b = input("b", [3, 2])
  #c*[y, x] ++= a[y, it] * b[it, x] | (x, y, it)
  c*[y, x] ++= a[y, x] | (y, x) # * b[it, x] | (x, y, it)
  let program = to_program([c.target("c", CompileFpga)])
  program.scalar_type = ScalarType(bits: 16, is_fixed: true, fixed_point: 4)
  program.index_type = IndexType(bits: 16)
  program.compile()
  let target = program.targets["c"]
  echo target
  
  let circuit = target.to_circuit(program, {
    "a": new_tensor([2, 3], @[float64 1, 2, 3, 4, 5, 6]),
    #"b": new_tensor([3, 2], @[float64 1, 2, 3, 4, 5, 6])
  })
  write_file("output.gv", circuit.to_dot_graph())
  
  let platform = Ulx3s.new("ulx3s_v20.lpf")
  echo circuit.to_verilog(platform)
  echo circuit.build(platform)
  #circuit.save_verilog("output.v", target_spec)
