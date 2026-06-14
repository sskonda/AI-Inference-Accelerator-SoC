module command_queue #(
    parameter int unsigned DEPTH = soc_pkg::DEFAULT_COMMAND_QUEUE_DEPTH,
    parameter int unsigned AGE_WIDTH = accel_pkg::STARVATION_COUNTER_WIDTH,
    parameter int unsigned COUNT_WIDTH = soc_pkg::width_for_count(DEPTH)
) (
  input logic clk,
  input logic rst_n,

  input  logic                     push_valid,
  output logic                     push_ready,
  input  accel_pkg::command_desc_t push_command,

  input  logic                                         select_enable,
  input  accel_pkg::scheduler_policy_e                 policy,
  input  logic                         [AGE_WIDTH-1:0] starvation_threshold,
  output logic                                         pop_valid,
  input  logic                                         pop_ready,
  output accel_pkg::command_desc_t                     pop_command,
  output logic                                         selected_starved,

  output logic                   full,
  output logic                   empty,
  output logic [COUNT_WIDTH-1:0] occupancy,
  output logic [COUNT_WIDTH-1:0] high_water
);

  import accel_pkg::*;
  import soc_pkg::*;

  localparam int unsigned INDEX_WIDTH = width_for_index(DEPTH);
  localparam logic [AGE_WIDTH-1:0] MAXIMUM_AGE = {AGE_WIDTH{1'b1}};
  localparam logic [INDEX_WIDTH-1:0] LAST_INDEX = INDEX_WIDTH'(DEPTH - 1);

  typedef logic [AGE_WIDTH-1:0] age_t;
  typedef logic [INDEX_WIDTH-1:0] index_t;

  command_desc_t             entries           [DEPTH];
  logic          [DEPTH-1:0] valid_entries;
  age_t                      entry_age         [DEPTH];

  index_t                    round_robin_index;
  logic                      selection_locked;
  index_t                    locked_index;

  logic                      selected_found;
  index_t                    selected_index;
  age_t                      selected_age;
  logic                      free_found;
  index_t                    free_index;
  logic                      push_fire;
  logic                      pop_fire;

  function automatic index_t wrapped_index(input index_t base, input int unsigned offset);
    int unsigned sum;

    sum = int'(base) + offset;
    if (sum >= DEPTH) begin
      sum -= DEPTH;
    end
    return index_t'(sum);
  endfunction

  initial begin : validate_parameters
    if ((DEPTH == 0) || (AGE_WIDTH == 0)) begin
      $fatal(1, "Command queue depth and age width must be positive");
    end
    if (COUNT_WIDTH != width_for_count(DEPTH)) begin
      $fatal(1, "Command queue count width does not match depth");
    end
  end

  always_comb begin
    full = occupancy == COUNT_WIDTH'(DEPTH);
    empty = occupancy == '0;
    push_ready = !full;
    push_fire = push_valid && push_ready;

    free_found = 1'b0;
    free_index = '0;
    for (int unsigned slot = 0; slot < DEPTH; slot++) begin
      if (!free_found && !valid_entries[slot]) begin
        free_found = 1'b1;
        free_index = index_t'(slot);
      end
    end

    selected_found = 1'b0;
    selected_index = '0;
    selected_age = '0;
    selected_starved = 1'b0;

    if (selection_locked) begin
      selected_found = valid_entries[locked_index];
      selected_index = locked_index;
      selected_age = entry_age[locked_index];
      selected_starved = (starvation_threshold != '0) &&
          (entry_age[locked_index] >= starvation_threshold);
    end else if (policy == SCHED_PRIORITY_FIRST) begin
      for (int unsigned slot = 0; slot < DEPTH; slot++) begin
        if (valid_entries[slot] && (starvation_threshold != '0) &&
            (entry_age[slot] >= starvation_threshold) &&
            (!selected_found || !selected_starved || (entry_age[slot] > selected_age))) begin
          selected_found = 1'b1;
          selected_index = index_t'(slot);
          selected_age = entry_age[slot];
          selected_starved = 1'b1;
        end
      end

      if (!selected_starved) begin
        selected_found = 1'b0;
        selected_index = '0;
        selected_age   = '0;
        for (int unsigned slot = 0; slot < DEPTH; slot++) begin
          if (valid_entries[slot] &&
              (!selected_found ||
               (entries[slot].priority_level > entries[selected_index].priority_level) ||
               ((entries[slot].priority_level == entries[selected_index].priority_level) &&
                (entry_age[slot] > selected_age)))) begin
            selected_found = 1'b1;
            selected_index = index_t'(slot);
            selected_age   = entry_age[slot];
          end
        end
      end
    end else begin
      for (int unsigned offset = 0; offset < DEPTH; offset++) begin
        if (!selected_found && valid_entries[wrapped_index(round_robin_index, offset)]) begin
          selected_found = 1'b1;
          selected_index = wrapped_index(round_robin_index, offset);
          selected_age   = entry_age[wrapped_index(round_robin_index, offset)];
        end
      end
    end

    pop_valid   = selected_found && (select_enable || selection_locked);
    pop_command = entries[selected_index];
  end

  assign pop_fire = pop_valid && pop_ready;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_entries <= '0;
      occupancy <= '0;
      high_water <= '0;
      round_robin_index <= '0;
      selection_locked <= 1'b0;
      locked_index <= '0;
    end else begin
      if (pop_fire) begin
        valid_entries[selected_index] <= 1'b0;
        if (selected_index == LAST_INDEX) begin
          round_robin_index <= '0;
        end else begin
          round_robin_index <= selected_index + 1'b1;
        end
      end

      if (push_fire) begin
        entries[free_index] <= push_command;
        valid_entries[free_index] <= 1'b1;
        entry_age[free_index] <= '0;
      end

      for (int unsigned slot = 0; slot < DEPTH; slot++) begin
        if (valid_entries[slot] && !(pop_fire && (selected_index == index_t'(slot))) &&
            (entry_age[slot] != MAXIMUM_AGE)) begin
          entry_age[slot] <= entry_age[slot] + 1'b1;
        end
      end

      unique case ({
        push_fire, pop_fire
      })
        2'b10: begin
          occupancy <= occupancy + 1'b1;
          if ((occupancy + 1'b1) > high_water) begin
            high_water <= occupancy + 1'b1;
          end
        end
        2'b01:   occupancy <= occupancy - 1'b1;
        default: occupancy <= occupancy;
      endcase

      if (pop_valid && !pop_ready) begin
        selection_locked <= 1'b1;
        locked_index <= selected_index;
      end else if (pop_fire) begin
        selection_locked <= 1'b0;
      end
    end
  end

  property p_output_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) pop_valid && !pop_ready |=> pop_valid && $stable(
        pop_command
    );
  endproperty

  property p_input_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) push_valid && !push_ready |=> push_valid && $stable(
        push_command
    );
  endproperty

  property p_no_overflow;
    @(posedge clk) disable iff (!rst_n) push_fire |-> !full;
  endproperty

  property p_no_underflow;
    @(posedge clk) disable iff (!rst_n) pop_fire |-> !empty;
  endproperty

  property p_selected_entry_is_valid;
    @(posedge clk) disable iff (!rst_n) pop_valid |-> valid_entries[selected_index];
  endproperty

  property p_occupancy_in_range;
    @(posedge clk) disable iff (!rst_n) occupancy <= COUNT_WIDTH'(DEPTH);
  endproperty

  property p_high_water_tracks_occupancy;
    @(posedge clk) disable iff (!rst_n) high_water >= occupancy;
  endproperty

  property p_policy_is_legal;
    @(posedge clk) disable iff (!rst_n) policy inside {SCHED_ROUND_ROBIN, SCHED_PRIORITY_FIRST};
  endproperty

  property p_reset_clears_queue;
    @(posedge clk) !rst_n |=> empty && !full && (occupancy == '0) && (high_water == '0);
  endproperty

  a_output_stable_while_stalled :
  assert property (p_output_stable_while_stalled);
  a_input_stable_while_stalled :
  assert property (p_input_stable_while_stalled);
  a_no_overflow :
  assert property (p_no_overflow);
  a_no_underflow :
  assert property (p_no_underflow);
  a_selected_entry_is_valid :
  assert property (p_selected_entry_is_valid);
  a_occupancy_in_range :
  assert property (p_occupancy_in_range);
  a_high_water_tracks_occupancy :
  assert property (p_high_water_tracks_occupancy);
  a_policy_is_legal :
  assert property (p_policy_is_legal);
  a_reset_clears_queue :
  assert property (p_reset_clears_queue);

  generate
    for (genvar level = 0; level <= DEPTH; level++) begin : gen_occupancy_coverage
      c_occupancy_level :
      cover property (@(posedge clk) disable iff (!rst_n) occupancy == COUNT_WIDTH'(level));
    end
  endgenerate

  c_round_robin_selection :
  cover property (@(posedge clk) disable iff (!rst_n) pop_fire && (policy == SCHED_ROUND_ROBIN));
  c_priority_selection :
  cover property (@(posedge clk) disable iff (!rst_n) pop_fire &&
                  (policy == SCHED_PRIORITY_FIRST) && !selected_starved);
  c_starvation_selection :
  cover property (@(posedge clk) disable iff (!rst_n) pop_fire && selected_starved);
  c_full_to_not_full :
  cover property (@(posedge clk) disable iff (!rst_n) $past(full) && !full);
  c_empty_to_not_empty :
  cover property (@(posedge clk) disable iff (!rst_n) $past(empty) && !empty);

endmodule
