package TopLib;
import Base::*;
import Left::*;
import Right::*;
function Byte result(Byte value);
  return right(left(value));
endfunction
endpackage
