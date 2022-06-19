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

# User interface for interacting with kernels on an FPGA

import std/tables
import logicdsl, utils
import ../ir

proc wrap_ui*(circuit: Circuit, program: Program, output_target: string, freq: int = 25_000_000): Circuit =
  let
    clock = Logic.input("clock", role=InputClock)
    buttons = Logic.input("buttons", 7, role=InputButtons)
    read_index = Logic.reg(program.index_type.bits, Logic.constant(program.index_type.bits, 0))
  read_index.update(clock, RisingEdge, select({
    buttons[5..5].detect(clock, RisingEdge): read_index - Logic.constant(program.index_type.bits, 1),
    buttons[6..6].detect(clock, RisingEdge): read_index + Logic.constant(program.index_type.bits, 1)
  }, read_index))
  
  let
    tensor_value = circuit.instantiate({
      "clock": clock,
      "target": Logic.constant(program.index_type.bits, BiggestUint(0)),
      #"clock": not buttons[0..0].debounce(clock, freq),
      "read_tensor_id": Logic.constant(program.index_type.bits, BiggestUint(int(program.targets[output_target].output) - 1)),
      "read_index": read_index
    }, 0)
    shown_value = select(buttons[1..1], read_index, tensor_value)
  result = Circuit.new([clock, buttons], {
    "value": select(buttons[2..2], shown_value[8..<16], shown_value[0..<8])
  })
