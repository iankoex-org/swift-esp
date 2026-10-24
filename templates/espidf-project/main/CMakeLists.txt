# ESP-IDF integration for a SwiftPM app built with a swift-esp SDK bundle.
#
#   eim shell v6.1
#   idf.py set-target esp32c6
#   idf.py build flash monitor
#
# Add the IDF components used by the app to REQUIRES (for example
# esp_driver_rmt, esp_wifi, bt). If a component's symbols are not pulled
# automatically, add a linker flag such as -Wl,--undefined=<symbol> or a
# linker group; see examples/wifi and examples/bluetooth.

idf_component_register(
    SRCS /dev/null           # no C sources; everything comes from the Swift package
    PRIV_INCLUDE_DIRS "."
    REQUIRES nvs_flash
)

if(NOT EXISTS "${COMPONENT_DIR}/Package.swift")
    message(FATAL_ERROR "Package.swift not found in ${COMPONENT_DIR}")
endif()

idf_build_get_property(arch IDF_TARGET_ARCH)
if("${arch}" STREQUAL "xtensa")
    idf_build_get_property(target IDF_TARGET)
    message(FATAL_ERROR "Swift SDK bundles only support RISC-V targets; '${target}' is Xtensa")
endif()

# Locate a swift.org toolchain (Xcode's toolchain cannot target riscv32).
# Prefer the toolchain selected by Swiftly (respects .swift-version).
find_program(SWIFTLY_EXECUTABLE swiftly)
if(SWIFTLY_EXECUTABLE)
    execute_process(
        COMMAND "${SWIFTLY_EXECUTABLE}" run which swift
        OUTPUT_VARIABLE SWIFT_EXECUTABLE
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET)
endif()
if(NOT SWIFT_EXECUTABLE)
    find_program(SWIFT_EXECUTABLE swift)
endif()
if(NOT SWIFT_EXECUTABLE)
    find_program(SWIFT_EXECUTABLE swift
        PATHS
            ~/Library/Developer/toolchains/swift-latest.xctoolchain/usr/bin
            ~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin
            /Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin
            /opt/swift/bin
        NO_DEFAULT_PATH)
endif()
if(NOT SWIFT_EXECUTABLE)
    message(FATAL_ERROR "swift.org toolchain not found; install one or set it on PATH")
endif()
get_filename_component(SWIFT_BIN "${SWIFT_EXECUTABLE}" DIRECTORY)

if(EXISTS "${SWIFT_BIN}/llvm-objcopy")
    set(SWIFT_OBJCOPY "${SWIFT_BIN}/llvm-objcopy")
else()
    find_program(SWIFT_OBJCOPY llvm-objcopy)
endif()
if(NOT SWIFT_OBJCOPY)
    message(FATAL_ERROR "llvm-objcopy not found")
endif()

# The installed SDK ID includes the Swift, ESP-IDF and bundle versions.
execute_process(
    COMMAND "${SWIFT_BIN}/swift" --version
    OUTPUT_VARIABLE _swift_version_output
    ERROR_QUIET)
string(REGEX MATCH "Swift version ([0-9]+\.[0-9]+(\.[0-9]+)?)" _ "${_swift_version_output}")
set(SWIFT_VERSION "${CMAKE_MATCH_1}")
if(SWIFT_VERSION MATCHES "^[0-9]+\.[0-9]+$")
    set(SWIFT_VERSION "${SWIFT_VERSION}.0")
endif()
if(NOT IDF_VERSION)
    if(DEFINED ENV{IDF_VERSION})
        set(IDF_VERSION "$ENV{IDF_VERSION}")
    elseif(EXISTS "$ENV{IDF_PATH}/version.txt")
        file(READ "$ENV{IDF_PATH}/version.txt" _idf_version)
        string(STRIP "${_idf_version}" IDF_VERSION)
    else()
        # EIM checkouts have no version.txt; version.cmake is authoritative.
        file(READ "$ENV{IDF_PATH}/tools/cmake/version.cmake" _idf_version_cmake)
        string(REGEX MATCH "IDF_VERSION_MAJOR[ \t]+([0-9]+)" _ "${_idf_version_cmake}")
        set(_idf_major "${CMAKE_MATCH_1}")
        string(REGEX MATCH "IDF_VERSION_MINOR[ \t]+([0-9]+)" _ "${_idf_version_cmake}")
        set(IDF_VERSION "${_idf_major}.${CMAKE_MATCH_1}")
    endif()
endif()
string(REGEX REPLACE "^v" "" IDF_VERSION "${IDF_VERSION}")
string(REGEX MATCH "^[0-9]+\.[0-9]+" IDF_VERSION "${IDF_VERSION}")
if(NOT SWIFT_VERSION OR NOT IDF_VERSION)
    message(FATAL_ERROR "could not derive the Swift SDK ID")
endif()
set(SWIFT_SDK_ID "swift-${SWIFT_VERSION}_${IDF_TARGET}-idf${IDF_VERSION}-0.1.0")
set(SWIFT_PACKAGE_DIR "${COMPONENT_DIR}")
set(SWIFT_ARCHIVE "${SWIFT_PACKAGE_DIR}/.build/riscv32-none-none-eabi/release/libApp.a")

add_custom_target(swift-build
    COMMAND rm -f "${SWIFT_ARCHIVE}"
    COMMAND "${SWIFT_BIN}/swift" build
        --package-path "${SWIFT_PACKAGE_DIR}"
        --configuration release
        --swift-sdk "${SWIFT_SDK_ID}"
        --build-system native
        -Xcc -I"${CMAKE_BINARY_DIR}/config"
    BYPRODUCTS "${SWIFT_ARCHIVE}"
)

add_custom_command(
    TARGET swift-build POST_BUILD
    COMMAND "${SWIFT_OBJCOPY}" --remove-section .swift_modhash "${SWIFT_ARCHIVE}"
)

add_dependencies(${COMPONENT_LIB} swift-build)
target_link_libraries(${COMPONENT_LIB} "${SWIFT_ARCHIVE}")
