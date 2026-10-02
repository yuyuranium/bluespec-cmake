#include <systemc.h>
#include "mkFirst_systemc.h"
#include "mkSecond_systemc.h"
int sc_main(int, char**) {
  sc_clock clock("clock", 10, SC_NS);
  sc_signal<bool> reset_n, first_ready, second_ready;
  sc_signal<sc_bv<8>> first_value, second_value;
  mkFirst first("first");
  mkSecond second("second");
  first.CLK(clock);
  first.RST_N(reset_n);
  first._read(first_value);
  first.RDY__read(first_ready);
  second.CLK(clock);
  second.RST_N(reset_n);
  second._read(second_value);
  second.RDY__read(second_ready);
  reset_n = false;
  sc_start(20, SC_NS);
  reset_n = true;
  sc_start(20, SC_NS);
  std::cout << "First: " << first_value.read().to_uint() << ", second: "
            << second_value.read().to_uint() << std::endl;
  return first_ready.read() && second_ready.read() &&
                 first_value.read().to_uint() == 7 &&
                 second_value.read().to_uint() == 41
             ? 0 : 1;
}
