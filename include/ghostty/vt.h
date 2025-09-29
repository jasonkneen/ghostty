/**
 * @file vt.h
 *
 * libghostty-vt - Virtual terminal sequence parsing library
 * 
 * This library provides functionality for parsing and handling terminal
 * escape sequences as well as maintaining terminal state such as styles,
 * cursor position, screen, scrollback, and more.
 *
 * WARNING: This is an incomplete, work-in-progress API. It is not yet
 * stable and is definitely going to change. 
 */

/**
 * @mainpage libghostty-vt - Virtual Terminal Sequence Parser
 *
 * libghostty-vt is a C library which implements a modern terminal emulator,
 * extracted from the [Ghostty](https://ghostty.org) terminal emulator.
 *
 * libghostty-vt contains the logic for handling the core parts of a terminal
 * emulator: parsing terminal escape sequences and maintaining terminal state.
 * It can handle scrollback, line wrapping, reflow on resize, and more.
 *
 * @warning This library is currently in development and the API is not yet stable.
 * Breaking changes are expected in future versions. Use with caution in production code.
 *
 * @section groups_sec API Reference
 *
 * The API is organized into the following groups:
 * - @ref osc "OSC Parser" - Parse OSC (Operating System Command) sequences
 * - @ref allocator "Memory Management" - Memory management and custom allocators
 *
 */

#ifndef GHOSTTY_VT_H
#define GHOSTTY_VT_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

//-------------------------------------------------------------------
// Types

/**
 * Opaque handle to an OSC parser instance.
 * 
 * This handle represents an OSC (Operating System Command) parser that can
 * be used to parse the contents of OSC sequences. This isn't a full VT
 * parser; it is only the OSC parser component. This is useful if you have
 * a parser already and want to only extract and handle OSC sequences.
 *
 * @ingroup osc
 */
typedef struct GhosttyOscParser *GhosttyOscParser;

/**
 * Opaque handle to a single OSC command.
 * 
 * This handle represents a parsed OSC (Operating System Command) command.
 * The command can be queried for its type and associated data using
 * `ghostty_osc_command_type` and `ghostty_osc_command_data`.
 *
 * @ingroup osc
 */
typedef struct GhosttyOscCommand *GhosttyOscCommand;

/**
 * Result codes for libghostty-vt operations.
 */
typedef enum {
    /** Operation completed successfully */
    GHOSTTY_SUCCESS = 0,
    /** Operation failed due to failed allocation */
    GHOSTTY_OUT_OF_MEMORY = -1,
} GhosttyResult;

/**
 * OSC command types.
 *
 * @ingroup osc
 */
typedef enum {
  GHOSTTY_OSC_COMMAND_INVALID = 0,
  GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_TITLE = 1,
  GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_ICON = 2,
  GHOSTTY_OSC_COMMAND_PROMPT_START = 3,
  GHOSTTY_OSC_COMMAND_PROMPT_END = 4,
  GHOSTTY_OSC_COMMAND_END_OF_INPUT = 5,
  GHOSTTY_OSC_COMMAND_END_OF_COMMAND = 6,
  GHOSTTY_OSC_COMMAND_CLIPBOARD_CONTENTS = 7,
  GHOSTTY_OSC_COMMAND_REPORT_PWD = 8,
  GHOSTTY_OSC_COMMAND_MOUSE_SHAPE = 9,
  GHOSTTY_OSC_COMMAND_COLOR_OPERATION = 10,
  GHOSTTY_OSC_COMMAND_KITTY_COLOR_PROTOCOL = 11,
  GHOSTTY_OSC_COMMAND_SHOW_DESKTOP_NOTIFICATION = 12,
  GHOSTTY_OSC_COMMAND_HYPERLINK_START = 13,
  GHOSTTY_OSC_COMMAND_HYPERLINK_END = 14,
  GHOSTTY_OSC_COMMAND_CONEMU_SLEEP = 15,
  GHOSTTY_OSC_COMMAND_CONEMU_SHOW_MESSAGE_BOX = 16,
  GHOSTTY_OSC_COMMAND_CONEMU_CHANGE_TAB_TITLE = 17,
  GHOSTTY_OSC_COMMAND_CONEMU_PROGRESS_REPORT = 18,
  GHOSTTY_OSC_COMMAND_CONEMU_WAIT_INPUT = 19,
  GHOSTTY_OSC_COMMAND_CONEMU_GUIMACRO = 20,
} GhosttyOscCommandType;

/**
 * OSC command data types.
 * 
 * These values specify what type of data to extract from an OSC command
 * using `ghostty_osc_command_data`.
 *
 * @ingroup osc
 */
typedef enum {
  /** Invalid data type. Never results in any data extraction. */
  GHOSTTY_OSC_DATA_INVALID = 0,
  
  /** 
   * Window title string data.
   *
   * Valid for: GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_TITLE
   *
   * Output type: const char ** (pointer to null-terminated string)
   *
   * Lifetime: Valid until the next call to any ghostty_osc_* function with 
   * the same parser instance. Memory is owned by the parser.
   */
  GHOSTTY_OSC_DATA_CHANGE_WINDOW_TITLE_STR = 1,
} GhosttyOscCommandData;

//-------------------------------------------------------------------
// Allocator Interface

/** @defgroup allocator Memory Management
 *
 * libghostty-vt does require memory allocation for various operations,
 * but is resilient to allocation failures and will gracefully handle
 * out-of-memory situations by returning error codes.
 *
 * The exact memory management semantics are documented in the relevant
 * functions and data structures.
 *
 * libghostty-vt uses explicit memory allocation via an allocator
 * interface provided by GhosttyAllocator. The interface is based on the
 * [Zig](https://ziglang.org) allocator interface, since this has been
 * shown to be a flexible and powerful interface in practice and enables
 * a wide variety of allocation strategies.
 *
 * **For the common case, you can pass NULL as the allocator for any
 * function that accepts one,** and libghostty will use a default allocator.
 * The default allocator will be libc malloc/free if libc is linked. 
 * Otherwise, a custom allocator is used (currently Zig's SMP allocator)
 * that doesn't require any external dependencies.
 *
 * ## Basic Usage
 *
 * For simple use cases, you can ignore this interface entirely by passing NULL
 * as the allocator parameter to functions that accept one. This will use the
 * default allocator (typically libc malloc/free, if libc is linked, but
 * we provide our own default allocator if libc isn't linked).
 *
 * To use a custom allocator:
 * 1. Implement the GhosttyAllocatorVtable function pointers
 * 2. Create a GhosttyAllocator struct with your vtable and context
 * 3. Pass the allocator to functions that accept one
 *
 * @{
 */

/**
 * Function table for custom memory allocator operations.
 * 
 * This vtable defines the interface for a custom memory allocator. All
 * function pointers must be valid and non-NULL.
 *
 * @ingroup allocator
 *
 * If you're not going to use a custom allocator, you can ignore all of
 * this. All functions that take an allocator pointer allow NULL to use a
 * default allocator.
 *
 * The interface is based on the Zig allocator interface. I'll say up front
 * that it is easy to look at this interface and think "wow, this is really
 * overcomplicated". The reason for this complexity is well thought out by
 * the Zig folks, and it enables a diverse set of allocation strategies
 * as shown by the Zig ecosystem. As a consolation, please note that many
 * of the arguments are only needed for advanced use cases and can be
 * safely ignored in simple implementations. For example, if you look at 
 * the Zig implementation of the libc allocator in `lib/std/heap.zig`
 * (search for CAllocator), you'll see it is very simple.
 *
 * We chose to align with the Zig allocator interface because:
 *
 *   1. It is a proven interface that serves a wide variety of use cases
 *      in the real world via the Zig ecosystem. It's shown to work.
 *
 *   2. Our core implementation itself is Zig, and this lets us very
 *      cheaply and easily convert between C and Zig allocators.
 *
 * NOTE(mitchellh): In the future, we can have default implementations of
 * resize/remap and allow those to be null.
 */
typedef struct {
    /**
     * Return a pointer to `len` bytes with specified `alignment`, or return
     * `NULL` indicating the allocation failed.
     *
     * @param ctx The allocator context
     * @param len Number of bytes to allocate
     * @param alignment Required alignment for the allocation. Guaranteed to
     *   be a power of two between 1 and 16 inclusive.
     * @param ret_addr First return address of the allocation call stack (0 if not provided)
     * @return Pointer to allocated memory, or NULL if allocation failed
     */
    void* (*alloc)(void *ctx, size_t len, uint8_t alignment, uintptr_t ret_addr);
    
    /**
     * Attempt to expand or shrink memory in place.
     *
     * `memory_len` must equal the length requested from the most recent
     * successful call to `alloc`, `resize`, or `remap`. `alignment` must
     * equal the same value that was passed as the `alignment` parameter to
     * the original `alloc` call.
     *
     * `new_len` must be greater than zero.
     *
     * @param ctx The allocator context
     * @param memory Pointer to the memory block to resize
     * @param memory_len Current size of the memory block
     * @param alignment Alignment (must match original allocation)
     * @param new_len New requested size
     * @param ret_addr First return address of the allocation call stack (0 if not provided)
     * @return true if resize was successful in-place, false if relocation would be required
     */
    bool (*resize)(void *ctx, void *memory, size_t memory_len, uint8_t alignment, size_t new_len, uintptr_t ret_addr);
    
    /**
     * Attempt to expand or shrink memory, allowing relocation.
     *
     * `memory_len` must equal the length requested from the most recent
     * successful call to `alloc`, `resize`, or `remap`. `alignment` must
     * equal the same value that was passed as the `alignment` parameter to
     * the original `alloc` call.
     *
     * A non-`NULL` return value indicates the resize was successful. The
     * allocation may have same address, or may have been relocated. In either
     * case, the allocation now has size of `new_len`. A `NULL` return value
     * indicates that the resize would be equivalent to allocating new memory,
     * copying the bytes from the old memory, and then freeing the old memory.
     * In such case, it is more efficient for the caller to perform the copy.
     *
     * `new_len` must be greater than zero.
     *
     * @param ctx The allocator context
     * @param memory Pointer to the memory block to remap
     * @param memory_len Current size of the memory block
     * @param alignment Alignment (must match original allocation)
     * @param new_len New requested size
     * @param ret_addr First return address of the allocation call stack (0 if not provided)
     * @return Pointer to resized memory (may be relocated), or NULL if manual copy is needed
     */
    void* (*remap)(void *ctx, void *memory, size_t memory_len, uint8_t alignment, size_t new_len, uintptr_t ret_addr);
    
    /**
     * Free and invalidate a region of memory.
     *
     * `memory_len` must equal the length requested from the most recent
     * successful call to `alloc`, `resize`, or `remap`. `alignment` must
     * equal the same value that was passed as the `alignment` parameter to
     * the original `alloc` call.
     *
     * @param ctx The allocator context
     * @param memory Pointer to the memory block to free
     * @param memory_len Size of the memory block
     * @param alignment Alignment (must match original allocation)
     * @param ret_addr First return address of the allocation call stack (0 if not provided)
     */
    void (*free)(void *ctx, void *memory, size_t memory_len, uint8_t alignment, uintptr_t ret_addr);
} GhosttyAllocatorVtable;

/**
 * Custom memory allocator.
 *
 * For functions that take an allocator pointer, a NULL pointer indicates
 * that the default allocator should be used. The default allocator will 
 * be libc malloc/free if we're linking to libc. If libc isn't linked,
 * a custom allocator is used (currently Zig's SMP allocator).
 *
 * @ingroup allocator
 *
 * Usage example:
 * @code
 * GhosttyAllocator allocator = {
 *     .vtable = &my_allocator_vtable,
 *     .ctx = my_allocator_state
 * };
 * @endcode
 */
typedef struct {
    /**
     * Opaque context pointer passed to all vtable functions.
     * This allows the allocator implementation to maintain state
     * or reference external resources needed for memory management.
     */
    void *ctx;

    /**
     * Pointer to the allocator's vtable containing function pointers
     * for memory operations (alloc, resize, remap, free).
     */
    const GhosttyAllocatorVtable *vtable;
} GhosttyAllocator;

/** @} */ // end of allocator group

//-------------------------------------------------------------------
// Functions

/** @defgroup osc OSC Parser
 *
 * OSC (Operating System Command) sequence parser and command handling.
 *
 * The parser operates in a streaming fashion, processing input byte-by-byte
 * to handle OSC sequences that may arrive in fragments across multiple reads.
 * This interface makes it easy to integrate into most environments and avoids
 * over-allocating buffers.
 *
 * ## Basic Usage
 *
 * 1. Create a parser instance with ghostty_osc_new()
 * 2. Feed bytes to the parser using ghostty_osc_next() 
 * 3. Finalize parsing with ghostty_osc_end() to get the command
 * 4. Query command type and extract data using ghostty_osc_command_type()
 *    and ghostty_osc_command_data()
 * 5. Free the parser with ghostty_osc_free() when done
 *
 * @{
 */

/**
 * Create a new OSC parser instance.
 * 
 * Creates a new OSC (Operating System Command) parser using the provided
 * allocator. The parser must be freed using ghostty_vt_osc_free() when
 * no longer needed.
 * 
 * @param allocator Pointer to the allocator to use for memory management, or NULL to use the default allocator
 * @param parser Pointer to store the created parser handle
 * @return GHOSTTY_SUCCESS on success, or an error code on failure
 */
GhosttyResult ghostty_osc_new(const GhosttyAllocator *allocator, GhosttyOscParser *parser);

/**
 * Free an OSC parser instance.
 * 
 * Releases all resources associated with the OSC parser. After this call,
 * the parser handle becomes invalid and must not be used.
 * 
 * @param parser The parser handle to free (may be NULL)
 */
void ghostty_osc_free(GhosttyOscParser parser);

/**
 * Reset an OSC parser instance to its initial state.
 * 
 * Resets the parser state, clearing any partially parsed OSC sequences
 * and returning the parser to its initial state. This is useful for
 * reusing a parser instance or recovering from parse errors.
 * 
 * @param parser The parser handle to reset, must not be null.
 */
void ghostty_osc_reset(GhosttyOscParser parser);

/**
 * Parse the next byte in an OSC sequence.
 * 
 * Processes a single byte as part of an OSC sequence. The parser maintains
 * internal state to track the progress through the sequence. Call this
 * function for each byte in the sequence data.
 *
 * When finished pumping the parser with bytes, call ghostty_osc_end
 * to get the final result.
 * 
 * @param parser The parser handle, must not be null.
 * @param byte The next byte to parse
 */
void ghostty_osc_next(GhosttyOscParser parser, uint8_t byte);

/**
 * Finalize OSC parsing and retrieve the parsed command.
 * 
 * Call this function after feeding all bytes of an OSC sequence to the parser
 * using ghostty_osc_next() with the exception of the terminating character
 * (ESC or ST). This function finalizes the parsing process and returns the 
 * parsed OSC command.
 *
 * The return value is never NULL. Invalid commands will return a command
 * with type GHOSTTY_OSC_COMMAND_INVALID.
 * 
 * The terminator parameter specifies the byte that terminated the OSC sequence
 * (typically 0x07 for BEL or 0x5C for ST after ESC). This information is
 * preserved in the parsed command so that responses can use the same terminator
 * format for better compatibility with the calling program. For commands that
 * do not require a response, this parameter is ignored and the resulting
 * command will not retain the terminator information.
 * 
 * The returned command handle is valid until the next call to any 
 * `ghostty_osc_*` function with the same parser instance with the exception
 * of command introspection functions such as `ghostty_osc_command_type`.
 * 
 * @param parser The parser handle, must not be null.
 * @param terminator The terminating byte of the OSC sequence (0x07 for BEL, 0x5C for ST)
 * @return Handle to the parsed OSC command
 */
GhosttyOscCommand ghostty_osc_end(GhosttyOscParser parser, uint8_t terminator);

/**
 * Get the type of an OSC command.
 * 
 * Returns the type identifier for the given OSC command. This can be used
 * to determine what kind of command was parsed and what data might be
 * available from it.
 * 
 * @param command The OSC command handle to query (may be NULL)
 * @return The command type, or GHOSTTY_OSC_COMMAND_INVALID if command is NULL
 */
GhosttyOscCommandType ghostty_osc_command_type(GhosttyOscCommand command);

/**
 * Extract data from an OSC command.
 * 
 * Extracts typed data from the given OSC command based on the specified
 * data type. The output pointer must be of the appropriate type for the
 * requested data kind. Valid command types, output types, and memory
 * safety information are documented in the `GhosttyOscCommandData` enum.
 *
 * @param command The OSC command handle to query (may be NULL)
 * @param data The type of data to extract
 * @param out Pointer to store the extracted data (type depends on data parameter)
 * @return true if data extraction was successful, false otherwise
 */
bool ghostty_osc_command_data(GhosttyOscCommand command, GhosttyOscCommandData data, void *out);

/** @} */ // end of osc group

#ifdef __cplusplus
}
#endif

#endif /* GHOSTTY_VT_H */
