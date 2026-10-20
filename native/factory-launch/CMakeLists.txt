cmake_minimum_required(VERSION 3.20)
project(factory_launch LANGUAGES CXX)

find_package(OpenSSL 3.0 REQUIRED COMPONENTS Crypto)

add_library(factory_capture src/capture.cpp)
target_include_directories(factory_capture PUBLIC include)
target_compile_features(factory_capture PUBLIC cxx_std_17)
target_compile_options(factory_capture PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(factory_capture PUBLIC OpenSSL::Crypto)

add_executable(factory-project-capture src/main.cpp)
target_link_libraries(factory-project-capture PRIVATE factory_capture)
target_compile_options(factory-project-capture PRIVATE -Wall -Wextra -Wpedantic -Werror)

include(CTest)
if(BUILD_TESTING)
  add_executable(factory-capture-test tests/capture_test.cpp)
  target_link_libraries(factory-capture-test PRIVATE factory_capture)
  target_compile_options(factory-capture-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME capture-contract COMMAND factory-capture-test
    $<TARGET_FILE:factory-project-capture> ${CMAKE_BINARY_DIR}/test-artifacts)
  set_tests_properties(capture-contract PROPERTIES TIMEOUT 30)
endif()
