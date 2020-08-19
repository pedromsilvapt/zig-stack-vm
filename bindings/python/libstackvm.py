from ctypes import *
import atexit
import enum

lib = cdll.LoadLibrary("libstackvm.dll")

def declare( f, args, res ):
    f.argtypes = args
    f.restype = res

    return f

declare( lib.stackvm_allocator_init, [], c_void_p )
declare( lib.stackvm_allocator_deinit, [c_void_p], None )

global_allocator = lib.stackvm_allocator_init()
atexit.register(lambda: lib.stackvm_allocator_deinit(global_allocator))

class TextPosition(Structure):
    _fields_ = [('line', c_uint32),
                ('column', c_uint32),
                ('offset', c_uint32)]

    @staticmethod
    def init ( line = 0, column = 0, offset = 0 ):
        return lib.stackvm_textposition_init(line, column, offset)

declare( lib.stackvm_textposition_init, [c_uint32, c_uint32, c_uint32], TextPosition )
declare( lib.stackvm_textposition_init_empty, [], TextPosition )

class InstructionSpan(Structure):
    _fields_ = [('instruction', c_size_t),
                ('start', TextPosition),
                ('end', TextPosition)]
    
    @staticmethod
    def init ( instruction = 0, start = None, end = None ):
        return lib.stackvm_instructionspan_init(
            instruction, 
            start or TextPosition.init(), 
            end or TextPosition.init()
        )

declare( lib.stackvm_instructionspan_init, [c_size_t, TextPosition, TextPosition], InstructionSpan )
declare( lib.stackvm_instructionspan_init_empty, [], InstructionSpan )

class RedBlackTree_InstructionSpan(Structure):
    _fields_ = [('allocator', c_void_p),
                ('len', c_uint32),
                ('root', c_void_p)]

class SourceMap(Structure):
    _fields_ = [('instructions_positions', RedBlackTree_InstructionSpan),
                ('current_position', TextPosition),
                ('current_instruction', c_size_t)]

    @staticmethod
    def init ():
        return lib.stackvm_sourcemap_init(global_allocator)
    
    def deinit (self):
        return lib.stackvm_sourcemap_deinit(self)

    def find (self, bytecode_pos):
        result = InstructionSpan.init()

        if lib.stackvm_sourcemap_find(self, bytecode_pos, result):
            return result
        
        return None
    
    def move (self):
        return lib.stackvm_sourcemap_move(self)

declare( lib.stackvm_sourcemap_init, [c_void_p], SourceMap )
declare( lib.stackvm_sourcemap_deinit, [POINTER(SourceMap)], None )
declare( lib.stackvm_sourcemap_find, [POINTER(SourceMap), c_size_t, POINTER(InstructionSpan)], c_int )
declare( lib.stackvm_sourcemap_move, [POINTER(SourceMap)], SourceMap )

class Parser(Structure):
    _fields_ = [('parser', c_void_p),
                ('source', POINTER(c_ubyte)),
                ('source_len', c_size_t)]
    
    @staticmethod
    def init (source):
        buffer = source.encode()

        return lib.stackvm_parser_init(global_allocator, buffer, len(buffer))
    
    def deinit (self):
        lib.stackvm_parser_deinit(self)
    
    def get_position (self):
        return lib.stackvm_parser_get_position(self)

    def get_source_map (self):
        return lib.stackvm_parser_get_source_map(self)

    def get_err_message (self):
        err_len = c_size_t(1)

        err_ptr = lib.stackvm_parser_get_err_message(self, pointer(err_len))

        if err_len.value > 0:
            return create_string_buffer(err_ptr, err_len.value).value.decode()
        
        return None

    def get_current_line (self):
        err_len = c_size_t(1)

        err_ptr = lib.stackvm_parser_get_current_line(self, pointer(err_len))

        if err_len.value > 0:
            return create_string_buffer(err_ptr, err_len.value).value.decode()
        
        return None

    def get_source_span (self, start, end):
        err_len = c_size_t(1)

        err_ptr = lib.stackvm_parser_get_source_span(self, start, end, pointer(err_len))

        if err_len.value > 0:
            return create_string_buffer(err_ptr, err_len.value).value.decode()
        
        return None

    def parse (self):
        addr = lib.stackvm_parser_parse(self)

        if not addr:
            msg = self.get_err_message()
            pos = self.get_position()

            raise Exception( f"{msg} (line {pos.line + 1}, column {pos.column + 1})" )

        return Reader( addr )

declare( lib.stackvm_parser_init, [c_void_p, c_char_p, c_size_t], Parser )
declare( lib.stackvm_parser_deinit, [POINTER(Parser)], None )
declare( lib.stackvm_parser_get_position, [POINTER(Parser)], TextPosition )
declare( lib.stackvm_parser_get_source_map, [POINTER(Parser)], SourceMap )
declare( lib.stackvm_parser_get_err_message, [POINTER(Parser), POINTER(c_size_t)], c_char_p )
declare( lib.stackvm_parser_get_current_line, [POINTER(Parser), POINTER(c_size_t)], c_char_p )
declare( lib.stackvm_parser_get_source_span, [POINTER(Parser), TextPosition, TextPosition, POINTER(c_size_t)], c_char_p )
declare( lib.stackvm_parser_parse, [POINTER(Parser)], c_void_p )

class Reader:
    def __init__ ( self, ptr ):
        self.ptr = cast(ptr, POINTER(c_void_p))
    
    def __len__ ( self ):
        return lib.stackvm_reader_get_len(self.ptr)

    def deinit (self):
        lib.stackvm_reader_deinit(self.ptr)

    def destroy (self):
        lib.stackvm_reader_destroy(global_allocator, self.ptr)

declare( lib.stackvm_reader_deinit, [c_void_p], None )
declare( lib.stackvm_reader_destroy, [c_void_p, c_void_p], None )
declare( lib.stackvm_reader_get_len, [c_void_p], c_size_t )

class VirtualMachine:
    @staticmethod
    def init(reader):
        return VirtualMachine(lib.stackvm_init(global_allocator, reader.ptr))

    def __init__ ( self, ptr ):
        self.ptr = cast(ptr, POINTER(c_void_p))
        self.registers = Registers(self)
        self.stack = Stack(self)
    
    def deinit (self):
        lib.stackvm_deinit(self.ptr)

    @property
    def last_instruction (self):
        return lib.stackvm_get_last_instruction(self.ptr)

    @property
    def err_message (self):
        err_len = c_size_t(1)

        err_ptr = lib.stackvm_get_err_message(self.ptr, pointer(err_len))

        if err_len.value > 0:
            return create_string_buffer(err_ptr, err_len.value).value.decode()
        
        return None

    def execute (self):
        success = lib.stackvm_execute(self.ptr)

        if not success:
            raise Exception(self.err_message)

declare( lib.stackvm_init, [c_void_p], c_void_p )
declare( lib.stackvm_deinit, [c_void_p], None )
declare( lib.stackvm_execute, [c_void_p], c_bool )
declare( lib.stackvm_get_last_instruction, [c_void_p], c_size_t )
declare( lib.stackvm_get_err_message, [c_void_p, POINTER(c_size_t)], c_char_p )

class Registers:
    def __init__ (self, vm):
        self.vm = vm
    
    @property
    def frame_pointer (self):
        return lib.stackvm_registers_get_frame_pointer(self.vm.ptr)

    @frame_pointer.setter
    def frame_pointer (self, value):
        lib.stackvm_registers_set_frame_pointer(self.vm.ptr, value)
    
    @property
    def global_pointer (self):
        return lib.stackvm_registers_get_global_pointer(self.vm.ptr)

    @global_pointer.setter
    def global_pointer (self, value):
        lib.stackvm_registers_set_global_pointer(self.vm.ptr, value)
    
    @property
    def code_pointer (self):
        return lib.stackvm_registers_get_code_pointer(self.vm.ptr)

    @code_pointer.setter
    def code_pointer (self, value):
        lib.stackvm_registers_set_code_pointer(self.vm.ptr, value)
    
    @property
    def stack_pointer (self):
        return lib.stackvm_registers_get_stack_pointer(self.vm.ptr)

    @stack_pointer.setter
    def stack_pointer (self, value):
        lib.stackvm_registers_set_stack_pointer(self.vm.ptr, value)

declare( lib.stackvm_registers_get_frame_pointer, [c_void_p], c_size_t )
declare( lib.stackvm_registers_set_frame_pointer, [c_void_p, c_size_t], None )
declare( lib.stackvm_registers_get_global_pointer, [c_void_p], c_size_t )
declare( lib.stackvm_registers_set_global_pointer, [c_void_p, c_size_t], None )
declare( lib.stackvm_registers_get_code_pointer, [c_void_p], c_size_t )
declare( lib.stackvm_registers_set_code_pointer, [c_void_p, c_size_t], None )
declare( lib.stackvm_registers_get_stack_pointer, [c_void_p], c_size_t )
declare( lib.stackvm_registers_set_stack_pointer, [c_void_p, c_size_t], None )

class ValueType(enum.IntEnum):
    NONE = 0
    INTEGER = 1
    FLOAT = 2
    ADDRESS_HEAP = 3
    ADDRESS_STRING = 4
    ADDRESS_CODE = 5
    ADDRESS_STACK = 6

class ValueUnion(Union):
    _fields_ = [('integer', c_int32),
                ('float', c_double),
                ('size', c_size_t)]

class Value(Structure):
    _fields_ = [('kind', c_uint8), 
                ('_value', ValueUnion)]
    
    @staticmethod
    def init (type, value):
        if type == ValueType.NONE:
            raise Exception("Cannot create value of type NONE")
        elif type == ValueType.INTEGER:
            return lib.stackvm_value_int(value)
        elif type == ValueType.FLOAT:
            return lib.stackvm_value_float(value)
        else:
            return lib.stackvm_value_size(type, value)

    @property
    def value (self):
        if ValueType.INTEGER == self.kind:
            return self._value.integer
        elif ValueType.FLOAT == self.kind:
            return self._value.float
        else:
            return self._value.size

declare( lib.stackvm_value_int, [c_int32], Value )
declare( lib.stackvm_value_float, [c_double], Value )
declare( lib.stackvm_value_size, [c_uint8, c_size_t], Value )

class Stack:
    def __init__ ( self, vm ):
        self.vm = vm
    
    def __len__ (self):
        return lib.stackvm_stack_get_len(self.vm.ptr)

    def load (self, index):
        return lib.stackvm_stack_load(self.vm.ptr, index)

    def store (self, index, value):
        lib.stackvm_stack_store(self.vm.ptr, index, value)

    def store (self, index, value):
        if value.kind == ValueType.INTEGER:
            lib.stackvm_stack_store_int(self.vm.ptr, index, value.value)
        elif value.kind == ValueType.FLOAT:
            lib.stackvm_stack_store_float(self.vm.ptr, index, value.value)
        else:
            lib.stackvm_stack_store_address(self.vm.ptr, index, value.kind, value.value)

    def push (self, value):
        if value.kind == ValueType.INTEGER:
            lib.stackvm_stack_push_int(self.vm.ptr, value.value)
        elif value.kind == ValueType.FLOAT:
            lib.stackvm_stack_push_float(self.vm.ptr, value.value)
        else:
            lib.stackvm_stack_push_address(self.vm.ptr, value.kind, value.value)

    def pop (self):
        return lib.stackvm_stack_pop(self.vm.ptr)

declare( lib.stackvm_stack_get_len, [c_void_p], c_size_t )
declare( lib.stackvm_stack_load, [c_void_p, c_size_t], Value )
declare( lib.stackvm_stack_store_int, [c_void_p, c_size_t, c_int32], None )
declare( lib.stackvm_stack_store_float, [c_void_p, c_size_t, c_double], None )
declare( lib.stackvm_stack_store_address, [c_void_p, c_size_t, c_uint8, c_size_t], None )
declare( lib.stackvm_stack_push_int, [c_void_p, c_int32], None )
declare( lib.stackvm_stack_push_float, [c_void_p, c_double], None )
declare( lib.stackvm_stack_push_address, [c_void_p, c_uint8, c_size_t], None )
declare( lib.stackvm_stack_pop, [c_void_p], Value )
