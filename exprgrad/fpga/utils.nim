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

# Utility modules

import std/[times, math]
import logicdsl

proc count_bits*(value: int): int =
  result = 1
  while (1 shl result) < value:
    result += 1

proc debounce*(input, clock: Logic,
               freq: int,
               milliseconds: int = 100): Logic =
  let
    ticks = int(round((milliseconds / 1_000) * float64(freq)))
    bits = count_bits(ticks)
  
  let
    zero = Logic.constant(bits, 0)
    counter = Logic.reg(bits, zero)
    next_counter = counter - Logic.constant(bits, 1)
    value = Logic.reg(1)
    read_input = counter <=> zero
    restart_counter = read_input and not (input <=> value)
    start_count = Logic.constant(bits, BiggestUint(ticks - 1))
  counter.update(clock, RisingEdge, select(restart_counter, start_count, select(counter > zero, next_counter, zero)))
  value.update(clock, RisingEdge, select(read_input, input, value))
  result = value

proc detect*(input, clock: Logic, event: UpdateEvent): Logic =
  let prev = Logic.reg(1)
  prev.update(clock, RisingEdge, input)
  result = not (prev <=> input)
  case event:
    of RisingEdge:
      result = result and input
    of FallingEdge:
      result = result and (not input)
