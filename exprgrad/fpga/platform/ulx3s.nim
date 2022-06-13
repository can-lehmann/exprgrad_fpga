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

import std/[os, osproc, streams, random]
import ../logicdsl

type
  Ulx3sError* = ref object of FpgaError
    code: int
  
  Ulx3s* = ref object of FpgaPlatform
    build_dir: string
    lpf_path: string

proc run(name: string, args: openArray[string]): tuple[code: int, output: string] =
  let
    process = start_process(name, args=args, options={poStdErrToStdOut, poUsePath})
    stream = process.output_stream()
  while process.running:
    var line = ""
    if stream.read_line(line):
      result.output.add(line)
      echo line
      result.output.add('\n')
  process.close()
  result.code = process.peek_exit_code()

proc check(res: tuple[code: int, output: string]) =
  if res.code != 0:
    raise Ulx3sError(code: res.code, msg: res.output)

method wrap*(platform: Ulx3s, circuit: Circuit): Circuit =
  let clock = Logic.input("clk_25mhz")
  result = Circuit.new([clock], {
    "wifi_gpio0": Logic.constant(true),
    "led": circuit.instantiate({
      circuit.find_role(InputClock).name: clock,
      "read_index": Logic.constant(16, 0)
    }, 0)[0..7]
  }, name="main")

proc create_build_dir(base_name: string = "build"): string =
  result = get_temp_dir()
  var id = rand(0..high(int))
  while dir_exists(result / (base_name & $id)):
    id += 1
  result = result / (base_name & $id)
  create_dir(result)

method build_verilog*(platform: Ulx3s, verilog: string): string =
  let
    source_path = platform.build_dir / "source.v"
    yosys_path = platform.build_dir / "yosys.ys"
    json_path = platform.build_dir / "circuit.json"
    config_path = platform.build_dir / "ulx3s.config"
  result = platform.build_dir / "ulx3s.bit"
  write_file(source_path, verilog)
  write_file(yosys_path, "read_verilog " & source_path & "\nsynth_ecp5 -json " & json_path)
  check run("yosys", ["-q", yosys_path])
  check run("nextpnr-ecp5", ["--85k", "--json", json_path, "--lpf", platform.lpf_path, "--textcfg", config_path])
  check run("ecppack", [config_path, result])

method upload_bitstream*(platform: Ulx3s, bitstream_path: string) =
  check run("fujprog", [bitstream_path])

proc new*(_: typedesc[Ulx3s], lpf_path: string): Ulx3s =
  result = Ulx3s(
    build_dir: create_build_dir(),
    lpf_path: lpf_path
  )
