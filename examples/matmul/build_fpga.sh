./../../tools/model2fpga \
  -i a 2x3 "1,2,3,4,5,6"  `# Input tensor a`\
  -i b 3x2 "1,2,3,4,5,6"  `# Input tensor b`\
  -S "8.8"                `# Fixed point format for Scalar type`\
  -I 16                   `# Number of bits in Index type`\
  -p                      `# Print IR to stdout`\
  -g graph.gv             `# Output circuit graph`\
  -v output.v             `# Output verilog`\
  -f                      `# Flash bitstream to FPGA using fujprog`\
  -t matmul               `# Name of target to compile`\
  -l ulx3s.lpf            `# LPF file for nextpnr`\
  matmul.bin              `# Path to model`\

dot graph.gv -Tsvg -Efontname=serif -Gfontname=serif -Nfontname=serif -o graph.svg
