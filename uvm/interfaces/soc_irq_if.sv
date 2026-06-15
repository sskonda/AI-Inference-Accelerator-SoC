interface soc_irq_if (
  input logic clk,
  input logic rst_n
);

  logic irq;

  clocking monitor_cb @(posedge clk);
    default input #1step;
    input irq;
  endclocking

endinterface
