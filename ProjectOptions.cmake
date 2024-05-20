include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(cmaketest_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(cmaketest_setup_options)
  option(cmaketest_ENABLE_HARDENING "Enable hardening" ON)
  option(cmaketest_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    cmaketest_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    cmaketest_ENABLE_HARDENING
    OFF)

  cmaketest_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR cmaketest_PACKAGING_MAINTAINER_MODE)
    option(cmaketest_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(cmaketest_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(cmaketest_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(cmaketest_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(cmaketest_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(cmaketest_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(cmaketest_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(cmaketest_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(cmaketest_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(cmaketest_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(cmaketest_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(cmaketest_ENABLE_PCH "Enable precompiled headers" OFF)
    option(cmaketest_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(cmaketest_ENABLE_IPO "Enable IPO/LTO" ON)
    option(cmaketest_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(cmaketest_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(cmaketest_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(cmaketest_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(cmaketest_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(cmaketest_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(cmaketest_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(cmaketest_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(cmaketest_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(cmaketest_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(cmaketest_ENABLE_PCH "Enable precompiled headers" OFF)
    option(cmaketest_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      cmaketest_ENABLE_IPO
      cmaketest_WARNINGS_AS_ERRORS
      cmaketest_ENABLE_USER_LINKER
      cmaketest_ENABLE_SANITIZER_ADDRESS
      cmaketest_ENABLE_SANITIZER_LEAK
      cmaketest_ENABLE_SANITIZER_UNDEFINED
      cmaketest_ENABLE_SANITIZER_THREAD
      cmaketest_ENABLE_SANITIZER_MEMORY
      cmaketest_ENABLE_UNITY_BUILD
      cmaketest_ENABLE_CLANG_TIDY
      cmaketest_ENABLE_CPPCHECK
      cmaketest_ENABLE_COVERAGE
      cmaketest_ENABLE_PCH
      cmaketest_ENABLE_CACHE)
  endif()

  cmaketest_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (cmaketest_ENABLE_SANITIZER_ADDRESS OR cmaketest_ENABLE_SANITIZER_THREAD OR cmaketest_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(cmaketest_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(cmaketest_global_options)
  if(cmaketest_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    cmaketest_enable_ipo()
  endif()

  cmaketest_supports_sanitizers()

  if(cmaketest_ENABLE_HARDENING AND cmaketest_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR cmaketest_ENABLE_SANITIZER_UNDEFINED
       OR cmaketest_ENABLE_SANITIZER_ADDRESS
       OR cmaketest_ENABLE_SANITIZER_THREAD
       OR cmaketest_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${cmaketest_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${cmaketest_ENABLE_SANITIZER_UNDEFINED}")
    cmaketest_enable_hardening(cmaketest_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(cmaketest_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(cmaketest_warnings INTERFACE)
  add_library(cmaketest_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  cmaketest_set_project_warnings(
    cmaketest_warnings
    ${cmaketest_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(cmaketest_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    cmaketest_configure_linker(cmaketest_options)
  endif()

  include(cmake/Sanitizers.cmake)
  cmaketest_enable_sanitizers(
    cmaketest_options
    ${cmaketest_ENABLE_SANITIZER_ADDRESS}
    ${cmaketest_ENABLE_SANITIZER_LEAK}
    ${cmaketest_ENABLE_SANITIZER_UNDEFINED}
    ${cmaketest_ENABLE_SANITIZER_THREAD}
    ${cmaketest_ENABLE_SANITIZER_MEMORY})

  set_target_properties(cmaketest_options PROPERTIES UNITY_BUILD ${cmaketest_ENABLE_UNITY_BUILD})

  if(cmaketest_ENABLE_PCH)
    target_precompile_headers(
      cmaketest_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(cmaketest_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    cmaketest_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(cmaketest_ENABLE_CLANG_TIDY)
    cmaketest_enable_clang_tidy(cmaketest_options ${cmaketest_WARNINGS_AS_ERRORS})
  endif()

  if(cmaketest_ENABLE_CPPCHECK)
    cmaketest_enable_cppcheck(${cmaketest_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(cmaketest_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    cmaketest_enable_coverage(cmaketest_options)
  endif()

  if(cmaketest_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(cmaketest_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(cmaketest_ENABLE_HARDENING AND NOT cmaketest_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR cmaketest_ENABLE_SANITIZER_UNDEFINED
       OR cmaketest_ENABLE_SANITIZER_ADDRESS
       OR cmaketest_ENABLE_SANITIZER_THREAD
       OR cmaketest_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    cmaketest_enable_hardening(cmaketest_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
