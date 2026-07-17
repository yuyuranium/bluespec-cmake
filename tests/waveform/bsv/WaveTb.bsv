package WaveTb;
(* synthesize *)
module mkWaveTb(Empty);
  Reg#(Bit#(8)) count <- mkReg(0);
  rule step;
    count <= count + 1;
    if (count == 8) begin
      $display("count=%0d", count);
      $finish(0);
    end
  endrule
endmodule
endpackage
