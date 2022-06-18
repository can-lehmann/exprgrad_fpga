./../../tools/model2fpga \
  -i x 4x2 "0,0,0,1,1,0,1,1" \
  -S "8.8" \
  -I 16 \
  -p \
  -v output.v \
  -f \
  -t predict \
  -l ulx3s.lpf \
  model.bin