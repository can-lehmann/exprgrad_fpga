module mod0(input wire [0:0] clock, input wire [6:0] buttons, output wire [7:0] value);
  wire [0:0] value2;
  wire [0:0] value3;
  wire [0:0] value4;
  wire [0:0] value5;
  wire [15:0] value6;
  wire [0:0] value7;
  wire [0:0] value8;
  wire [0:0] value9;
  wire [0:0] value10;
  wire [15:0] value11;
  wire [15:0] value12;
  wire [15:0] value13;
  wire [0:0] value14;
  wire [0:0] value15;
  wire [15:0] value16;
  wire [15:0] value17;
  wire [7:0] value18;
  wire [7:0] value19;
  wire [7:0] value20;

  reg [0:0] value21 = 1'b0;
  reg [15:0] value23 = 16'b0000000000000000;
  reg [0:0] value25 = 1'b0;

  assign value2 = buttons[5:5];
  assign value3 = (value21 == value2);
  assign value4 = ~value3;
  assign value5 = (value4 & value2);
  assign value6 = (value23 - 16'b0000000000000001);
  assign value7 = buttons[6:6];
  assign value8 = (value25 == value7);
  assign value9 = ~value8;
  assign value10 = (value9 & value7);
  assign value11 = (value23 + 16'b0000000000000001);
  assign value12 = (value10 ? value11 : value23);
  assign value13 = (value5 ? value6 : value12);
  assign value14 = buttons[2:2];
  assign value15 = buttons[1:1];
  mod1 __mod1_value16(clock, 16'b0000000000000000, 16'b0000000000000000, value23, value16);
  assign value17 = (value15 ? value23 : value16);
  assign value18 = value17[15:8];
  assign value19 = value17[7:0];
  assign value20 = (value14 ? value18 : value19);

  initial begin
  end

  always @(posedge clock) begin
    value21 <= value2;
    value23 <= value13;
    value25 <= value7;
  end

  assign value = value20;
endmodule
module mod1(input wire [0:0] clock, input wire [15:0] target, input wire [15:0] read_tensor_id, input wire [15:0] read_index, output wire [15:0] data);
  wire [0:0] value35;
  wire [0:0] value36;
  wire [1:0] value37;
  wire [0:0] value38;
  wire [15:0] value39;
  wire [0:0] value40;
  wire [15:0] value41;
  wire [0:0] value42;
  wire [15:0] value43;
  wire [0:0] value44;
  wire [0:0] value45;
  wire [0:0] value46;
  wire [0:0] value47;
  wire [0:0] value48;
  wire [1:0] value49;
  wire [1:0] value50;
  wire [1:0] value51;
  wire [15:0] value52;
  wire [15:0] value53;
  wire [15:0] value54;
  wire [15:0] value55;
  wire [15:0] value56;
  wire [15:0] value57;
  wire [15:0] value58;
  wire [15:0] value59;
  wire [0:0] value60;
  wire [31:0] value61;
  wire [15:0] value62;
  wire [15:0] value63;
  wire [31:0] value64;
  wire [15:0] value65;
  wire [15:0] value66;
  wire [15:0] value67;
  wire [31:0] value68;
  wire [15:0] value69;
  wire [15:0] value70;
  wire [15:0] value71;
  wire [31:0] value72;
  wire [31:0] value73;
  wire [15:0] value74;
  wire [15:0] value75;
  wire [15:0] value76;
  wire [0:0] value77;
  wire [15:0] value78;
  wire [15:0] value79;

  reg [1:0] value80 = 2'b00;
  reg [15:0] value82_iter2 = 16'b0000000000000000;
  reg [15:0] value84_iter0 = 16'b0000000000000000;
  reg [15:0] value86_iter1 = 16'b0000000000000000;
  reg [15:0] mem0[3:0];
  reg [15:0] mem1[5:0];
  reg [15:0] mem2[5:0];

  assign value35 = (value80 == 2'b00);
  assign value36 = (target == 16'b0000000000000000);
  assign value37 = (value36 ? 2'b01 : 2'b00);
  assign value38 = (value80 == 2'b11);
  assign value39 = (value84_iter0 + 16'b0000000000000001);
  assign value40 = (value39 == 16'b0000000000000010);
  assign value41 = (value86_iter1 + 16'b0000000000000001);
  assign value42 = (value41 == 16'b0000000000000011);
  assign value43 = (value82_iter2 + 16'b0000000000000001);
  assign value44 = (value43 == 16'b0000000000000010);
  assign value45 = (value42 & value44);
  assign value46 = (value40 & value45);
  assign value47 = (value38 & value46);
  assign value48 = (value80 == 2'b01);
  assign value49 = (value48 ? 2'b11 : value80);
  assign value50 = (value47 ? 2'b10 : value49);
  assign value51 = (value35 ? value37 : value50);
  assign value52 = (value44 ? 16'b0000000000000000 : value43);
  assign value53 = (value38 ? value52 : value82_iter2);
  assign value54 = (value40 ? 16'b0000000000000000 : value39);
  assign value55 = (value45 ? value54 : value84_iter0);
  assign value56 = (value38 ? value55 : value84_iter0);
  assign value57 = (value42 ? 16'b0000000000000000 : value41);
  assign value58 = (value44 ? value57 : value86_iter1);
  assign value59 = (value38 ? value58 : value86_iter1);
  assign value60 = (value80 == 2'b11);
  assign value61 = ($signed(value84_iter0) * $signed(16'b0000000000000010));
  assign value62 = value61[15:0];
  assign value63 = (value82_iter2 + value62);
  assign value64 = ($signed(value84_iter0) * $signed(16'b0000000000000011));
  assign value65 = value64[15:0];
  assign value66 = (value86_iter1 + value65);
  assign value67 = mem1[value66];
  assign value68 = ($signed(value86_iter1) * $signed(16'b0000000000000010));
  assign value69 = value68[15:0];
  assign value70 = (value82_iter2 + value69);
  assign value71 = mem2[value70];
  assign value72 = ($signed(value67) * $signed(value71));
  assign value73 = (value72 >> 8);
  assign value74 = value73[15:0];
  assign value75 = mem0[value63];
  assign value76 = (value74 + value75);
  assign value77 = (read_tensor_id == 16'b0000000000000000);
  assign value78 = mem0[read_index];
  assign value79 = (value77 ? value78 : 16'b0000000000000000);

  initial begin
    mem1[0] = 16'b0000000100000000;
    mem1[1] = 16'b0000001000000000;
    mem1[2] = 16'b0000001100000000;
    mem1[3] = 16'b0000010000000000;
    mem1[4] = 16'b0000010100000000;
    mem1[5] = 16'b0000011000000000;
    mem2[0] = 16'b0000000100000000;
    mem2[1] = 16'b0000001000000000;
    mem2[2] = 16'b0000001100000000;
    mem2[3] = 16'b0000010000000000;
    mem2[4] = 16'b0000010100000000;
    mem2[5] = 16'b0000011000000000;
  end

  always @(posedge clock) begin
    value80 <= value51;
    value82_iter2 <= value53;
    value84_iter0 <= value56;
    value86_iter1 <= value59;
    if (value60) begin
      mem0[value63] <= value76;
    end
  end

  assign data = value79;
endmodule
module main(input wire [0:0] clk_25mhz, input wire [6:0] btn, output wire [0:0] wifi_gpio0, output wire [7:0] led);
  wire [7:0] value113;
  wire [7:0] value114;


  mod0 __mod0_value113(clk_25mhz, btn, value113);
  assign value114 = value113[7:0];

  initial begin
  end


  assign wifi_gpio0 = 1'b1;
  assign led = value114;
endmodule
