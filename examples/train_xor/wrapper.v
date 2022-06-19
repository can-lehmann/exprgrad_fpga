module main(input clk_25mhz, input [6:0] btn, output [7:0] led, output wifi_gpio0);
  assign wifi_gpio0 = 1'b1;
  
  wire [23:0] data;
  wire [15:0] read_index;
  assign read_index = (btn[5] ? 2 : 0) | (btn[6] ? 1 : 0);
  mod0 __mod0(clk_25mhz, {15'b0, btn[3]}, 3, read_index, data);
  assign led = btn[2] ? data[23:16] : (btn[1] ? data[15:8] : data[7:0]);
endmodule
