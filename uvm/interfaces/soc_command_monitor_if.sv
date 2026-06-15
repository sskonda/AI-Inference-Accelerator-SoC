interface soc_command_monitor_if (
  input logic clk,
  input logic rst_n
);

  logic                                                            command_completed;
  logic                       [   accel_pkg::COMMAND_ID_WIDTH-1:0] command_id;
  accel_pkg::command_opcode_e                                      opcode;
  logic                                                            error;
  logic                       [reg_pkg::QUEUE_OCCUPANCY_WIDTH-1:0] queue_occupancy;

  clocking monitor_cb @(posedge clk);
    default input #1step;
    input command_completed, command_id, opcode, error, queue_occupancy;
  endclocking

endinterface
