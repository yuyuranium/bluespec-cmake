package Second;
import Child::*;
(* synthesize *)
module mkSecond(ReadOnly#(Bit#(8)));
  let child <- mkChild;
  return child;
endmodule
endpackage
