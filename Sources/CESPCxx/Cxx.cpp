#include "CESPCxx.h"

namespace swift_esp {

// Keep the C++ side free of exceptions/RTTI/existentials: Embedded Swift
// firmware is built with -fno-exceptions and there is no C++ runtime.
class Adder {
public:
    constexpr int add(int lhs, int rhs) const { return lhs + rhs; }
};

}  // namespace swift_esp

extern "C" int cxx_add(int lhs, int rhs) {
    const swift_esp::Adder adder;
    return adder.add(lhs, rhs);
}
