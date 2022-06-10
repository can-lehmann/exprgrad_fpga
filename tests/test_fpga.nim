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
import ../tools/test_framework

test "matmul/passes":
  let
    a = input("a", [1024, 1024])
    b = input("b", [1024, 1024])
  c*[y, x] ++= a[y, it] * b[it, x] | (x, y, it)
  let program = to_program([c.target("c", CompileFpga)])
  program.scalar_type = ScalarType(bits: 16, is_fixed: true, fixed_point: 8)
  program.index_type = IndexType(bits: 16)
  program.compile()
  let target = program.targets["c"]
  echo target
  
  proc wrapper(circuit: Circuit, target: TargetSpec): Circuit =
    let clock = Logic.input("clk_25mhz")
    result = Circuit.new([clock], {
      "wifi_gpio0": Logic.constant(true),
      "led": circuit.instantiate({
        circuit.find_role(InputClock).name: clock,
        "read_index": Logic.constant(16, 0)
      }, 0)
    }, name="main")
  
  let
    circuit = target.to_circuit(program)
    target_spec = TargetSpec(wrapper: wrapper)
  write_file("output.gv", circuit.to_dot_graph())
  
  echo circuit.to_verilog(target_spec)
  #circuit.save_verilog("output.v", target_spec)
