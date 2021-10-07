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

# Unit-tests for exprgrad

import std/random
import exprgrad
import ../tools/test_framework

test "matmul":
  c*[x, y] ++= input("a")[it, y] * input("b")[x, it]
  let model = compile[float32](c.target("c"))
  block:
    let
      a = new_tensor([3, 2], @[float32 1, 2, 3, 4, 5, 6])
      b = new_tensor([2, 3], @[float32 1, 2, 3, 4, 5, 6])
    check model.call("c", {"a": a, "b": b}) == a * b

test "relu":
  var inp = input("inp")
  outp*{it} ++= select(0.0 < inp{it}, inp{it}, 0.0)
  let model = compile[float32](outp.target("outp"))
  block:
    let
      inp = new_tensor[float32]([3, 2], @[float32 0, -1, 10, -20, 0.1, -0.1])
      outp = new_tensor[float32]([3, 2], @[float32 0, 0, 10, 0, 0.1, 0])
    check model.call("outp", {"inp": inp}) == outp

test "mean_squared_error":
  loss*[0] ++= sq(input("pred"){it} - input("labels"){it})
  let model = compile[float32](loss.target("loss"))
  block:
    let
      pred = new_tensor[float32]([2, 2], @[float32 1, 2, 3, 4])
      labels = new_tensor[float32]([2, 2], @[float32 4, 3, 2, 1])
    check model.call("loss", {
      "pred": pred, "labels": pred
    }) == new_tensor([1], @[float32 0])
    
    check model.call("loss", {
      "pred": pred, "labels": labels
    }) == new_tensor([1], @[float32 9 + 1 + 1 + 9])

test "transpose":
  b*[x, y] ++= input("a")[y, x]
  block:
    let
      model = compile[float32](b.target("b"))
      a = new_tensor[float32]([3, 2], @[float32 1, 2, 3, 4, 5, 6])
    check model.call("b", {"a": a}) == a.transpose()

test "extern":
  proc `*`(inp: Fun, factor: float64): Fun =
    result{it} ++= inp{it} * @factor
  
  proc test_with_factor(factor: float64) =
    let
      model = compile[float64](target(input("x") * factor, "y"))
      x = new_tensor[float64]([3, 2], @[float64 1, 2, 3, 4, 5, 6])
    check model.call("y", {"x": x}) == x * factor
  
  for it in -2..2:
    test_with_factor(float64(it))

test "xor":
  randomize(10)
  
  hidden*[x, y] ++= input("x")[it, y] * param([4, 2])[x, it]
  hidden[x, y] ++= param([4])[x]
  hidden_relu*{it} ++= select(hidden{it} <= 0.0, 0.1 * hidden{it}, hidden{it})
  output*[x, y] ++= hidden_relu[it, y] * param([1, 4])[x, it]
  output[x, y] ++= param([1])[x]
  output_sigmoid*{it} ++= 1.0 / (1.0 + exp(-output{it})) 
  let pred = output_sigmoid.target("predict")
  
  proc optim(param: var Fun, grad: Fun) =
    param{it} ++= -0.1 * grad{it}
  loss*[0] ++= sq(pred{it} - input("y"){it})
  let net = loss.target("loss").backprop(optim).target("train")
  
  let model = compile[float32](net)
  
  let
    train_x = new_tensor([2, 4], @[float32 0, 0, 0, 1, 1, 0, 1, 1])
    train_y = new_tensor([1, 4], @[float32 0, 1, 1, 0])
  
  for epoch in 0..<1000:
    model.apply("train", {"x": train_x, "y": train_y})
  
  check squares(model.call("predict", {"x": train_x}) - train_y).sum() < 0.1
