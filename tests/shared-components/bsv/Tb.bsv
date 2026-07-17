package Tb;
import TopLib::*;
(* synthesize *)
module mkTb(Empty);
  rule done;
    $display("result=%0d", result(1));
    $finish(0);
  endrule
endmodule
endpackage
