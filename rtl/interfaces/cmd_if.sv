interface cmd_if (
  input logic clk,
  input logic rst_n
);

  import accel_pkg::*;

  logic              cmd_valid;
  logic              cmd_ready;
  command_desc_t     cmd;
  logic              cmd_full;

  logic              rsp_valid;
  logic              rsp_ready;
  command_response_t rsp;
  logic              rsp_empty;

  property p_command_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) cmd_valid && !cmd_ready |=> cmd_valid && $stable(
        cmd
    );
  endproperty

  property p_response_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) rsp_valid && !rsp_ready |=> rsp_valid && $stable(
        rsp
    );
  endproperty

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {cmd_valid, cmd_ready, cmd_full, rsp_valid, rsp_ready, rsp_empty}
    );
  endproperty

  property p_valid_opcode_accepted;
    @(posedge clk) disable iff (!rst_n) cmd_valid && cmd_ready |-> is_valid_opcode(
        cmd.opcode
    );
  endproperty

  property p_no_command_accepted_when_full;
    @(posedge clk) disable iff (!rst_n) cmd_valid && cmd_ready |-> !cmd_full;
  endproperty

  property p_no_response_consumed_when_empty;
    @(posedge clk) disable iff (!rst_n) rsp_valid && rsp_ready |-> !rsp_empty;
  endproperty

  a_command_stable_while_stalled :
  assert property (p_command_stable_while_stalled);
  a_response_stable_while_stalled :
  assert property (p_response_stable_while_stalled);
  a_known_control :
  assert property (p_known_control);
  a_valid_opcode_accepted :
  assert property (p_valid_opcode_accepted);
  a_no_command_accepted_when_full :
  assert property (p_no_command_accepted_when_full);
  a_no_response_consumed_when_empty :
  assert property (p_no_response_consumed_when_empty);

  modport producer(
      input cmd_ready, cmd_full, rsp_valid, rsp, rsp_empty,
      output cmd_valid, cmd, rsp_ready
  );

  modport consumer(
      input cmd_valid, cmd, rsp_ready,
      output cmd_ready, cmd_full, rsp_valid, rsp, rsp_empty
  );

  modport monitor(
      input clk, rst_n, cmd_valid, cmd_ready, cmd, cmd_full, rsp_valid, rsp_ready, rsp, rsp_empty
  );

endinterface
