./../../tools/model2fpga \
  -i x 4x2 "0,0,0,1,1,0,1,1" \
  -i y 4x1 "0,1,1,0" \
  -S "8.16" \
  -I 16 \
  -p \
  -V output.v \
  -t predict \
  -t train \
  -m \
  model.bin

yosys -q yosys.ys
nextpnr-ecp5 --85k --json circuit.json --lpf ulx3s.lpf --textcfg ulx3s.config
ecppack ulx3s.config ulx3s.bit
