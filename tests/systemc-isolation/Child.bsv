package Child;
(* synthesize *)
module mkChild(ReadOnly#(Bit#(8)));
  Reg#(Bit#(8)) value <- mkReg(`INITIAL_VALUE);
  method Bit#(8) _read = value;
endmodule
endpackage
