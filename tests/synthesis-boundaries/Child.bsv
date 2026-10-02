package Child;
(* synthesize *)
module mkChild(Reg#(Bit#(`CHILD_WIDTH)));
  Reg#(Bit#(`CHILD_WIDTH)) value <- mkReg(0);
  return value;
endmodule
endpackage
