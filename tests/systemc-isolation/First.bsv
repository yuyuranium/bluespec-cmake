package First;
import Child::*;
(* synthesize *)
module mkFirst(ReadOnly#(Bit#(8)));
  let child <- mkChild;
  return child;
endmodule
endpackage
