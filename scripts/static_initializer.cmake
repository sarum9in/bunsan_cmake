set(BUNSAN_STATIC_INITIALIZER_REGEX "BUNSAN_STATIC_INITIALIZER\\(([0-9a-zA-Z_]*),")
set(BUNSAN_STATIC_INITIALIZER_BODY_INDENT "    ")
set(BUNSAN_STATIC_INITIALIZER_SOURCE bunsan_static_initializer)

macro(bunsan_static_initializer_name target name)
    string(MAKE_C_IDENTIFIER ${target}_initializer ${name})
endmacro()

macro(bunsan_static_initializer_external_name target name)
    bunsan_static_initializer_name(${target} ${name})
    set(${name} ${${name}}_external)
endmacro()

macro(bunsan_static_initializer_external_header_name target name)
    set(${name} ${target}_external.hpp)
endmacro()

function(bunsan_initializer_configure)
    set(options)
    set(one_value_args EXTERNAL_INCLUDE FUNCTION MODIFIER OUTPUT)
    set(multi_value_args CALLS DEPENDS EXTERN_CALLS)
    cmake_parse_arguments(ARG "${options}" "${one_value_args}" "${multi_value_args}" ${ARGN})

    set(BUNSAN_STATIC_INITIALIZER_FUNCTION ${ARG_FUNCTION})
    set(BUNSAN_STATIC_INITIALIZER_FORWARD)
    set(BUNSAN_STATIC_INITIALIZER_MODIFIER ${ARG_MODIFIER})
    if(ARG_EXTERNAL_INCLUDE)
        set(BUNSAN_STATIC_INITIALIZER_EXTERNAL_INCLUDE
            "#include \"${ARG_EXTERNAL_INCLUDE}\"")
    endif()
    set(BUNSAN_STATIC_INITIALIZER_BODY "{")
    foreach(call ${ARG_EXTERN_CALLS})
        string(CONCAT BUNSAN_STATIC_INITIALIZER_FORWARD
            "${BUNSAN_STATIC_INITIALIZER_FORWARD}\n"
            "extern \"C\" void ${call}();"
        )
    endforeach()
    foreach(call ${ARG_CALLS} ${ARG_EXTERN_CALLS})
        string(CONCAT BUNSAN_STATIC_INITIALIZER_BODY
            "${BUNSAN_STATIC_INITIALIZER_BODY}\n"
            "${BUNSAN_STATIC_INITIALIZER_BODY_INDENT}${call}();"
        )
    endforeach()
    set(BUNSAN_STATIC_INITIALIZER_BODY "${BUNSAN_STATIC_INITIALIZER_BODY}\n}")
    bunsan_add_configured_file(
        INPUT ${BunsanCMake_MODULE_ROOT}/StaticInitializer.cpp.in
        OUTPUT ${ARG_OUTPUT}
        VARIABLES
            BUNSAN_STATIC_INITIALIZER_BODY
            BUNSAN_STATIC_INITIALIZER_EXTERNAL_INCLUDE
            BUNSAN_STATIC_INITIALIZER_FORWARD
            BUNSAN_STATIC_INITIALIZER_FUNCTION
            BUNSAN_STATIC_INITIALIZER_MODIFIER
        DEPENDS ${ARG_DEPENDS}
    )
endfunction()

# TODO add support for generated files
function(bunsan_add_static_initializer_self target source)
    bunsan_static_initializer_name(${target} function)
    set(source_dir ${CMAKE_CURRENT_BINARY_DIR}/${BUNSAN_STATIC_INITIALIZER_SOURCE})
    set(source_path ${source_dir}/${target}_self.cpp)
    bunsan_static_initializer_external_header_name(${target} external_name)

    set(calls)

    bunsan_static_initializer_external_name(${target} external_call)

    foreach(source ${ARGN})
        if(NOT IS_ABSOLUTE ${source})
            set(source ${CMAKE_CURRENT_SOURCE_DIR}/${source})
        endif()
        get_filename_component(ext ${source} EXT)
        # skip headers
        if(NOT ext STREQUAL .h AND
           NOT ext STREQUAL .hpp)
            file(STRINGS ${source} initializers REGEX ${BUNSAN_STATIC_INITIALIZER_REGEX})
            foreach(initializer ${initializers})
                string(REGEX REPLACE "^${BUNSAN_STATIC_INITIALIZER_REGEX}$" "\\1"
                                     call ${initializer})
                bunsan_static_initializer_name(${call} call)
                list(APPEND calls ${call})
            endforeach()
        endif()
    endforeach()

    bunsan_initializer_configure(
        OUTPUT ${source_path}
        MODIFIER "extern \"C\""
        FUNCTION ${function}
        EXTERNAL_INCLUDE ${external_name}
        EXTERN_CALLS ${calls}
        CALLS ${external_call}
        DEPENDS ${ARGN} ${source_dir}/${external_name}
    )

    set(${source} ${source_path} PARENT_SCOPE)
endfunction()

function(bunsan_add_static_initializer_self_call target source)
    bunsan_static_initializer_name(${target} BUNSAN_STATIC_INITIALIZER_FUNCTION)
    set(source_dir ${CMAKE_CURRENT_BINARY_DIR}/${BUNSAN_STATIC_INITIALIZER_SOURCE})
    set(source_path ${source_dir}/${target}_self_call.cpp)

    configure_file(${BunsanCMake_MODULE_ROOT}/StaticInitializerCall.cpp.in
                   ${source_path} @ONLY)

    set(${source} ${source_path} PARENT_SCOPE)
endfunction()

function(bunsan_add_static_initializer_external)
    foreach(target ${ARGN})
        bunsan_static_initializer_external_name(${target} function)
        set(source_dir ${CMAKE_CURRENT_BINARY_DIR}/${BUNSAN_STATIC_INITIALIZER_SOURCE})
        bunsan_static_initializer_external_header_name(${target} source_name)
        set(source_path ${source_dir}/${source_name})

        set(calls)
        get_target_property(dependencies ${target} INTERFACE_LINK_LIBRARIES)
        if(dependencies)
            foreach(dependency ${dependencies})
                if(TARGET ${dependency})
                    get_target_property(bunsan_target ${dependency} BUNSAN_TARGET)
                    if(bunsan_target)
                        bunsan_static_initializer_name(${dependency} call)
                        list(APPEND calls ${call})
                    endif()
                endif()
            endforeach()
        endif()

        bunsan_initializer_configure(
            OUTPUT ${source_path}
            MODIFIER "static"
            FUNCTION ${function}
            EXTERN_CALLS ${calls}
        )
    endforeach()
endfunction()
