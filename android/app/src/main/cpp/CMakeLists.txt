cmake_minimum_required(VERSION 3.10.2)

file(GLOB LIBSMB2_SRCS
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../ios/Runner/libsmb2/lib/*.c"
)

set(DCERPC_SRCS
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../ios/Runner/libsmb2/libdcerpc/dcerpc.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../ios/Runner/libsmb2/libdcerpc/dcerpc-srvsvc.c"
)

add_library(smb2jni SHARED
    smb2_jni.c
    ${LIBSMB2_SRCS}
    ${DCERPC_SRCS}
)

target_include_directories(smb2jni PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../ios/Runner/libsmb2/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../ios/Runner/libsmb2/include/smb2
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../ios/Runner/libsmb2/include/dcerpc
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../ios/Runner/libsmb2/lib
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../ios/Runner/libsmb2/libdcerpc
)

target_compile_definitions(smb2jni PRIVATE
    HAVE_CONFIG_H
    _U_=
    ANDROID
)

target_compile_options(smb2jni PRIVATE
    -std=gnu11
    -w
)

# Only the two dcerpc units need the prefix rename header.
set_source_files_properties(${DCERPC_SRCS} PROPERTIES
    COMPILE_OPTIONS "-include;${CMAKE_CURRENT_SOURCE_DIR}/../../../../../ios/Runner/libsmb2/lib/libsmb2-dcerpc-prefix.h"
)

find_library(log-lib log)
target_link_libraries(smb2jni ${log-lib})
