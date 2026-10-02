package Top;
import Child::*;
(* synthesize *)
module mkTop(Empty);
  Reg#(Bit#(8)) value <- mkChild;
  rule count;
    value <= value + 1;
    if (value == 10) $finish(0);
  endrule
endmodule
endpackage
