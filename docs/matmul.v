module mod0(input wire [0:0] clock, input wire [15:0] read_tensor_id, input wire [15:0] read_index, output wire [15:0] data);
  wire [0:0] value3;
  wire [15:0] value4;
  wire [0:0] value5;
  wire [15:0] value6;
  wire [15:0] value7;
  wire [15:0] value8;
  wire [0:0] value9;
  wire [0:0] value10;
  wire [15:0] value11;
  wire [0:0] value12;
  wire [15:0] value13;
  wire [15:0] value14;
  wire [15:0] value15;
  wire [15:0] value16;
  wire [15:0] value17;
  wire [15:0] value18;
  wire [0:0] value19;
  wire [0:0] value20;
  wire [0:0] value21;
  wire [0:0] value22;
  wire [1:0] value23;
  wire [1:0] value24;
  wire [1:0] value25;
  wire [0:0] value26;
  wire [31:0] value27;
  wire [15:0] value28;
  wire [15:0] value29;
  wire [31:0] value30;
  wire [15:0] value31;
  wire [15:0] value32;
  wire [15:0] value33;
  wire [31:0] value34;
  wire [15:0] value35;
  wire [15:0] value36;
  wire [15:0] value37;
  wire [31:0] value38;
  wire [31:0] value39;
  wire [15:0] value40;
  wire [15:0] value41;
  wire [15:0] value42;
  wire [0:0] value43;
  wire [15:0] value44;
  wire [15:0] value45;

  reg [15:0] value46_iter2 = 16'b0000000000000000;
  reg [15:0] value48_iter0 = 16'b0000000000000000;
  reg [15:0] value50_iter1 = 16'b0000000000000000;
  reg [1:0] value52 = 2'b00;
  reg [15:0] mem0[5:0];
  reg [15:0] mem1[5:0];
  reg [15:0] mem2[3:0];

  assign value3 = (value52 == 2'b11);
  assign value4 = (value46_iter2 + 16'b0000000000000001);
  assign value5 = (value4 == 16'b0000000000000010);
  assign value6 = (value5 ? 16'b0000000000000000 : value4);
  assign value7 = (value3 ? value6 : value46_iter2);
  assign value8 = (value50_iter1 + 16'b0000000000000001);
  assign value9 = (value8 == 16'b0000000000000011);
  assign value10 = (value9 & value5);
  assign value11 = (value48_iter0 + 16'b0000000000000001);
  assign value12 = (value11 == 16'b0000000000000010);
  assign value13 = (value12 ? 16'b0000000000000000 : value11);
  assign value14 = (value10 ? value13 : value48_iter0);
  assign value15 = (value3 ? value14 : value48_iter0);
  assign value16 = (value9 ? 16'b0000000000000000 : value8);
  assign value17 = (value5 ? value16 : value50_iter1);
  assign value18 = (value3 ? value17 : value50_iter1);
  assign value19 = (value52 == 2'b00);
  assign value20 = (value12 & value10);
  assign value21 = (value3 & value20);
  assign value22 = (value52 == 2'b01);
  assign value23 = (value22 ? 2'b11 : value52);
  assign value24 = (value21 ? 2'b10 : value23);
  assign value25 = (value19 ? 2'b01 : value24);
  assign value26 = (value52 == 2'b11);
  assign value27 = ($signed(value48_iter0) * $signed(16'b0000000000000010));
  assign value28 = value27[15:0];
  assign value29 = (value46_iter2 + value28);
  assign value30 = ($signed(value48_iter0) * $signed(16'b0000000000000011));
  assign value31 = value30[15:0];
  assign value32 = (value50_iter1 + value31);
  assign value33 = mem1[value32];
  assign value34 = ($signed(value50_iter1) * $signed(16'b0000000000000010));
  assign value35 = value34[15:0];
  assign value36 = (value46_iter2 + value35);
  assign value37 = mem0[value36];
  assign value38 = ($signed(value33) * $signed(value37));
  assign value39 = (value38 >> 8);
  assign value40 = value39[15:0];
  assign value41 = mem2[value29];
  assign value42 = (value40 + value41);
  assign value43 = (read_tensor_id == 16'b0000000000000000);
  assign value44 = mem2[read_index];
  assign value45 = (value43 ? value44 : 16'b0000000000000000);

  initial begin
    mem0[0] = 16'b0000000100000000;
    mem0[1] = 16'b0000001000000000;
    mem0[2] = 16'b0000001100000000;
    mem0[3] = 16'b0000010000000000;
    mem0[4] = 16'b0000010100000000;
    mem0[5] = 16'b0000011000000000;
    mem1[0] = 16'b0000000100000000;
    mem1[1] = 16'b0000001000000000;
    mem1[2] = 16'b0000001100000000;
    mem1[3] = 16'b0000010000000000;
    mem1[4] = 16'b0000010100000000;
    mem1[5] = 16'b0000011000000000;
  end

  always @(posedge clock) begin
    value46_iter2 <= value7;
    value48_iter0 <= value15;
    value50_iter1 <= value18;
    value52 <= value25;
    if (value26) begin
      mem2[value29] <= value42;
    end
  end

  assign data = value45;
endmodule
module main(input wire [0:0] clk_25mhz, input wire [6:0] btn, output wire [0:0] wifi_gpio0, output wire [7:0] led);
  wire [7:0] value77;
  wire [7:0] value78;


  mod2 __mod2_value77(clk_25mhz, btn, value77);
  assign value78 = value77[7:0];

  initial begin
  end


  assign wifi_gpio0 = 1'b1;
  assign led = value78;
endmodule
module mod2(input wire [0:0] clock, input wire [6:0] buttons, output wire [7:0] value);
  wire [0:0] value82;
  wire [0:0] value83;
  wire [0:0] value84;
  wire [0:0] value85;
  wire [0:0] value86;
  wire [15:0] value87;
  wire [0:0] value88;
  wire [0:0] value89;
  wire [0:0] value90;
  wire [15:0] value91;
  wire [15:0] value92;
  wire [15:0] value93;
  wire [0:0] value94;
  wire [0:0] value95;
  wire [15:0] value96;
  wire [15:0] value97;
  wire [7:0] value98;
  wire [7:0] value99;
  wire [7:0] value100;

  reg [0:0] value101 = 1'b0;
  reg [0:0] value103 = 1'b0;
  reg [15:0] value105 = 16'b0000000000000000;

  assign value82 = buttons[5:5];
  assign value83 = buttons[6:6];
  assign value84 = (value101 == value82);
  assign value85 = ~value84;
  assign value86 = (value85 & value82);
  assign value87 = (value105 - 16'b0000000000000001);
  assign value88 = (value103 == value83);
  assign value89 = ~value88;
  assign value90 = (value89 & value83);
  assign value91 = (value105 + 16'b0000000000000001);
  assign value92 = (value90 ? value91 : value105);
  assign value93 = (value86 ? value87 : value92);
  assign value94 = buttons[2:2];
  assign value95 = buttons[1:1];
  mod0 __mod0_value96(clock, 16'b0000000000000000, value105, value96);
  assign value97 = (value95 ? value105 : value96);
  assign value98 = value97[15:8];
  assign value99 = value97[7:0];
  assign value100 = (value94 ? value98 : value99);

  initial begin
  end

  always @(posedge clock) begin
    value101 <= value82;
    value103 <= value83;
    value105 <= value93;
  end

  assign value = value100;
endmodule
