package Incremental;
(* synthesize *)
module mkIncremental(Reg#(Bit#(8)));
  Reg#(Bit#(8)) value <- mkReg(0);
  return value;
endmodule
endpackage
