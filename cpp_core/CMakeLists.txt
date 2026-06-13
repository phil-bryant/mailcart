cmake_minimum_required(VERSION 3.24)
project(mailcartcore LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Match the macOS app's platform floor (project.yml deploymentTarget macOS 13.0)
# so the linker does not warn about objects targeting a newer macOS than the app.
if(APPLE AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "" FORCE)
endif()

option(MAILCARTCORE_BUILD_TESTS "Build mailcartcore unit tests" ON)
option(MAILCARTCORE_BUILD_TOOLS "Build token CLI, API server, and oracle runner" ON)
option(MAILCARTCORE_SANITIZE "Build with ASan+UBSan" OFF)
# Requires a clang with the libFuzzer runtime (Apple clang lacks it; use brew
# LLVM via CMAKE_C/CXX_COMPILER). The t10 fuzz lane drives this.
option(MAILCARTCORE_BUILD_FUZZERS "Build libFuzzer targets (ASan+UBSan instrumented)" OFF)
# OFF for fuzz builds: fuzzing must not open sockets. Token refresh and Graph
# transport degrade to injected stubs when HTTP is disabled.
option(MAILCARTCORE_ENABLE_HTTP "Build the Graph/token HTTPS transports and API server" ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

add_compile_options(-Wall -Wextra -Wpedantic -Werror)
if(MAILCARTCORE_SANITIZE)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()
if(MAILCARTCORE_BUILD_FUZZERS)
  # Instrument the whole core for coverage-guided fuzzing; the fuzzer driver
  # itself is linked only into the fuzz executables below.
  add_compile_options(-fsanitize=fuzzer-no-link,address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

find_package(Threads REQUIRED)

include(FetchContent)
FetchContent_Declare(nlohmann_json
  URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
  DOWNLOAD_EXTRACT_TIMESTAMP ON)
FetchContent_MakeAvailable(nlohmann_json)

if(MAILCARTCORE_ENABLE_HTTP)
  find_package(OpenSSL REQUIRED)
  # Keep the link surface minimal: OpenSSL + zlib only.
  set(HTTPLIB_USE_BROTLI_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
  set(HTTPLIB_USE_ZSTD_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(httplib
    URL https://github.com/yhirose/cpp-httplib/archive/refs/tags/v0.18.3.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP ON)
  FetchContent_MakeAvailable(httplib)
endif()

add_library(mailcartcore STATIC
  src/mailcart.cpp
  src/mime_content.cpp
  src/outlook_mailcart.cpp
  src/outlook_client.cpp
  src/subprocess.cpp
  src/token.cpp
  src/search.cpp
  src/graph.cpp
  src/api.cpp)
target_include_directories(mailcartcore PUBLIC include)
target_link_libraries(mailcartcore
  PUBLIC nlohmann_json::nlohmann_json
  PRIVATE Threads::Threads)
if(MAILCARTCORE_ENABLE_HTTP)
  target_sources(mailcartcore PRIVATE src/http_transport.cpp)
  target_compile_definitions(mailcartcore PRIVATE MAILCARTCORE_ENABLE_HTTP=1)
  target_link_libraries(mailcartcore PRIVATE httplib::httplib OpenSSL::SSL OpenSSL::Crypto)
endif()

if(MAILCARTCORE_BUILD_TOOLS)
  add_executable(mailcart_oracle_runner tools/oracle_runner.cpp)
  target_link_libraries(mailcart_oracle_runner PRIVATE mailcartcore)

  if(MAILCARTCORE_ENABLE_HTTP)
    add_executable(mailcart_token tools/mailcart_token.cpp)
    target_link_libraries(mailcart_token PRIVATE mailcartcore)

    add_executable(mailcart_api tools/mailcart_api.cpp)
    target_link_libraries(mailcart_api PRIVATE mailcartcore httplib::httplib OpenSSL::SSL OpenSSL::Crypto)
    target_compile_definitions(mailcart_api PRIVATE
      MAILCART_OPENAPI_SPEC_PATH="${CMAKE_CURRENT_SOURCE_DIR}/openapi/openapi.json")
  endif()
endif()

if(MAILCARTCORE_BUILD_FUZZERS)
  foreach(fuzz_target fuzz_query_parse fuzz_aho_corasick fuzz_graph_payloads)
    add_executable(${fuzz_target} fuzz/${fuzz_target}.cpp)
    target_link_libraries(${fuzz_target} PRIVATE mailcartcore)
    target_compile_options(${fuzz_target} PRIVATE -fsanitize=fuzzer,address,undefined)
    target_link_options(${fuzz_target} PRIVATE -fsanitize=fuzzer,address,undefined)
  endforeach()
endif()

if(MAILCARTCORE_BUILD_TESTS)
  FetchContent_Declare(catch2
    URL https://github.com/catchorg/Catch2/archive/refs/tags/v3.7.1.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP ON)
  FetchContent_MakeAvailable(catch2)
  enable_testing()
  add_executable(mailcartcore_tests
    tests/test_outlook_core.cpp
    tests/test_token.cpp
    tests/test_search.cpp
    tests/test_api.cpp)
  target_link_libraries(mailcartcore_tests PRIVATE mailcartcore Catch2::Catch2WithMain)
  add_test(NAME mailcartcore_tests COMMAND mailcartcore_tests)
endif()
