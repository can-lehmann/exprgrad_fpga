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

import std/random
import exprgrad, exprgrad/io/serialize, exprgrad/layers/[base, dnn]
randomize(10)

let
  net = input("x")
    .dense(2, 4).leaky_relu() # 1st Layer
    .dense(4, 1).leaky_relu() # 2nd Layer
    .target("predict")
    .mse(input("y"))          # Loss
    .target("loss")
    .backprop(gradient_descent.make_opt(rate=0.1)) # Train
    .target("train")
  model = compile[float64](net)

let
  train_x = new_tensor([4, 2], @[float64 0, 0, 0, 1, 1, 0, 1, 1])
  train_y = new_tensor([4, 1], @[float64 0, 1, 1, 0])

echo "Prediction: ", model.call("predict", {"x": train_x})
echo "Loss: ", model.call("loss", {"x": train_x, "y": train_y})
model.save("model.bin")
