// CESPCxx — C++ bridge target.
//
// Swift cannot import C++ declarations directly in Embedded mode. The pattern
// is to compile the C++ code in a target like this one and expose a plain C
// `extern "C"` surface that Swift imports. Add wrappers here for whichever
// C++ IDF/library API your app needs.

#ifndef CESP_CXX_H
#define CESP_CXX_H

#ifdef __cplusplus
extern "C" {
#endif

/// Adds two integers in C++; proves the C++ toolchain path and the bridge.
int cxx_add(int lhs, int rhs);

#ifdef __cplusplus
}
#endif

#endif /* CESP_CXX_H */
