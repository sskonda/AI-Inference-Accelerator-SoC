class soc_reference_model extends uvm_object;
  typedef logic [ELEMENT_WIDTH-1:0] element_t;
  typedef logic signed [ELEMENT_WIDTH-1:0] signed_element_t;

  localparam longint unsigned ELEMENT_MAXIMUM = (64'd1 << ELEMENT_WIDTH) - 1;
  localparam longint signed SIGNED_MAXIMUM = (64'sd1 << (ELEMENT_WIDTH - 1)) - 1;
  localparam longint signed SIGNED_MINIMUM = -(64'sd1 << (ELEMENT_WIDTH - 1));

  `uvm_object_utils(soc_reference_model)

  function new(string name = "soc_reference_model");
    super.new(name);
  endfunction

  static function longint signed signed_value(element_t value);
    signed_element_t converted = signed_element_t'(value);
    return longint'(converted);
  endfunction

  static function element_t convert_signed(longint signed value, bit saturate);
    if (saturate) begin
      if (value > SIGNED_MAXIMUM) begin
        value = SIGNED_MAXIMUM;
      end else if (value < SIGNED_MINIMUM) begin
        value = SIGNED_MINIMUM;
      end
    end
    return element_t'(value);
  endfunction

  static function element_t convert_unsigned(longint unsigned value, bit saturate);
    if (saturate && value > ELEMENT_MAXIMUM) begin
      value = ELEMENT_MAXIMUM;
    end
    return element_t'(value);
  endfunction

  static function void vector_operation(command_opcode_e opcode, input element_t source0[],
                                        input element_t source1[], bit signed_mode, bit saturate,
                                        output element_t result[]);
    result = new[source0.size()];
    foreach (source0[index]) begin
      longint signed   signed_lhs;
      longint signed   signed_rhs;
      longint unsigned unsigned_lhs;
      longint unsigned unsigned_rhs;
      element_t        rhs;

      if (opcode == CMD_OP_VECTOR_RELU) begin
        rhs = '0;
      end else if (opcode == CMD_OP_VECTOR_SCALE) begin
        rhs = source1[0];
      end else begin
        rhs = source1[index];
      end

      if (signed_mode) begin
        signed_lhs = signed_value(source0[index]);
        signed_rhs = signed_value(rhs);
        case (opcode)
          CMD_OP_VECTOR_ADD: result[index] = convert_signed(signed_lhs + signed_rhs, saturate);
          CMD_OP_VECTOR_MULTIPLY, CMD_OP_VECTOR_SCALE:
          result[index] = convert_signed(signed_lhs * signed_rhs, saturate);
          CMD_OP_VECTOR_RELU: result[index] = convert_signed(signed_lhs < 0 ? 0 : signed_lhs, 1'b0);
          CMD_OP_VECTOR_CLAMP:
          result[index] = convert_signed(
              signed_lhs < 0 || signed_rhs < 0 ?
                  0 : (signed_lhs < signed_rhs ? signed_lhs : signed_rhs),
              1'b0
          );
          default: result[index] = '0;
        endcase
      end else begin
        unsigned_lhs = source0[index];
        unsigned_rhs = rhs;
        case (opcode)
          CMD_OP_VECTOR_ADD:
          result[index] = convert_unsigned(unsigned_lhs + unsigned_rhs, saturate);
          CMD_OP_VECTOR_MULTIPLY, CMD_OP_VECTOR_SCALE:
          result[index] = convert_unsigned(unsigned_lhs * unsigned_rhs, saturate);
          CMD_OP_VECTOR_RELU: result[index] = source0[index];
          CMD_OP_VECTOR_CLAMP: result[index] = source0[index] < rhs ? source0[index] : rhs;
          default: result[index] = '0;
        endcase
      end
    end
  endfunction

  static function element_t reduction_operation(command_opcode_e opcode, input element_t source[],
                                                bit signed_mode, bit saturate);
    longint signed   signed_accumulator;
    longint unsigned unsigned_accumulator;

    if (opcode == CMD_OP_REDUCE_SUM) begin
      if (signed_mode) begin
        signed_accumulator = 0;
        foreach (source[index]) begin
          signed_accumulator += signed_value(source[index]);
        end
        return convert_signed(signed_accumulator, saturate);
      end
      unsigned_accumulator = 0;
      foreach (source[index]) begin
        unsigned_accumulator += source[index];
      end
      return convert_unsigned(unsigned_accumulator, saturate);
    end

    if (signed_mode) begin
      signed_accumulator = SIGNED_MINIMUM;
      foreach (source[index]) begin
        if (signed_value(source[index]) > signed_accumulator) begin
          signed_accumulator = signed_value(source[index]);
        end
      end
      return convert_signed(signed_accumulator, 1'b0);
    end

    unsigned_accumulator = 0;
    foreach (source[index]) begin
      if (source[index] > unsigned_accumulator) begin
        unsigned_accumulator = source[index];
      end
    end
    return element_t'(unsigned_accumulator);
  endfunction

  static function void gemm_operation(input element_t matrix_a[], input element_t matrix_b[],
                                      int unsigned rows, int unsigned columns, int unsigned inner,
                                      bit signed_mode, bit saturate, output element_t result[]);
    result = new[rows * columns];
    for (int unsigned row = 0; row < rows; row++) begin
      for (int unsigned column = 0; column < columns; column++) begin
        longint signed   signed_accumulator = 0;
        longint unsigned unsigned_accumulator = 0;
        for (int unsigned index = 0; index < inner; index++) begin
          if (signed_mode) begin
            signed_accumulator += signed_value(matrix_a[row*inner+index]) *
                signed_value(matrix_b[index*columns+column]);
          end else begin
            unsigned_accumulator += matrix_a[row*inner+index] * matrix_b[index*columns+column];
          end
        end
        result[row*columns+column] = signed_mode ? convert_signed(signed_accumulator, saturate) :
            convert_unsigned(unsigned_accumulator, saturate);
      end
    end
  endfunction
endclass
