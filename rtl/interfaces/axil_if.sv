interface axil_if #(
    parameter int unsigned ADDR_WIDTH = soc_pkg::AXIL_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH
) (
  input logic clk,
  input logic rst_n
);

  localparam int unsigned STRB_WIDTH = DATA_WIDTH / soc_pkg::BITS_PER_BYTE;

  logic                                awvalid;
  logic                                awready;
  logic [              ADDR_WIDTH-1:0] awaddr;

  logic                                wvalid;
  logic                                wready;
  logic [              DATA_WIDTH-1:0] wdata;
  logic [              STRB_WIDTH-1:0] wstrb;

  logic                                bvalid;
  logic                                bready;
  logic [soc_pkg::AXIL_RESP_WIDTH-1:0] bresp;

  logic                                arvalid;
  logic                                arready;
  logic [              ADDR_WIDTH-1:0] araddr;

  logic                                rvalid;
  logic                                rready;
  logic [              DATA_WIDTH-1:0] rdata;
  logic [soc_pkg::AXIL_RESP_WIDTH-1:0] rresp;

  initial begin : validate_parameters
    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % soc_pkg::BITS_PER_BYTE) != 0)) begin
      $fatal(1, "AXI-Lite data width must contain a positive whole number of bytes");
    end
    if (ADDR_WIDTH == 0) begin
      $fatal(1, "AXI-Lite address width must be positive");
    end
  end

  property p_aw_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) awvalid && !awready |=> awvalid && $stable(
        awaddr
    );
  endproperty

  property p_w_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) wvalid && !wready |=> wvalid && $stable(
        {wdata, wstrb}
    );
  endproperty

  property p_b_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) bvalid && !bready |=> bvalid && $stable(
        bresp
    );
  endproperty

  property p_ar_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) arvalid && !arready |=> arvalid && $stable(
        araddr
    );
  endproperty

  property p_r_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) rvalid && !rready |=> rvalid && $stable(
        {rdata, rresp}
    );
  endproperty

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready}
    );
  endproperty

  a_aw_stable_while_stalled :
  assert property (p_aw_stable_while_stalled);
  a_w_stable_while_stalled :
  assert property (p_w_stable_while_stalled);
  a_b_stable_while_stalled :
  assert property (p_b_stable_while_stalled);
  a_ar_stable_while_stalled :
  assert property (p_ar_stable_while_stalled);
  a_r_stable_while_stalled :
  assert property (p_r_stable_while_stalled);
  a_known_control :
  assert property (p_known_control);

  modport manager(
      input awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp,
      output awvalid, awaddr, wvalid, wdata, wstrb, bready, arvalid, araddr, rready
  );

  modport subordinate(
      input awvalid, awaddr, wvalid, wdata, wstrb, bready, arvalid, araddr, rready,
      output awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp
  );

  modport monitor(
      input clk, rst_n, awvalid, awready, awaddr, wvalid, wready, wdata, wstrb, bvalid, bready,
          bresp, arvalid, arready, araddr, rvalid, rready, rdata, rresp
  );

endinterface
