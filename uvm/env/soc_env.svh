class soc_env extends uvm_env;
  `uvm_component_utils(soc_env)

  soc_env_config config_h;
  axil_agent axil_agent_h;
  mem_agent memory_agent_h;
  irq_agent irq_agent_h;
  cmd_agent command_agent_h;
  soc_scoreboard scoreboard_h;
  soc_coverage coverage_h;
  soc_virtual_sequencer virtual_sequencer_h;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(soc_env_config)::get(this, "", "config", config_h)) begin
      `uvm_fatal(get_type_name(), "SoC environment configuration is not set")
    end
    config_h.bind_interfaces();
    uvm_config_db#(axil_agent_config)::set(this, "axil_agent_h", "config", config_h.axil_config);
    uvm_config_db#(mem_agent_config)::set(this, "memory_agent_h", "config", config_h.memory_config);
    uvm_config_db#(irq_agent_config)::set(this, "irq_agent_h", "config", config_h.irq_config);
    uvm_config_db#(cmd_agent_config)::set(this, "command_agent_h", "config",
                                          config_h.command_config);
    axil_agent_h = axil_agent::type_id::create("axil_agent_h", this);
    memory_agent_h = mem_agent::type_id::create("memory_agent_h", this);
    irq_agent_h = irq_agent::type_id::create("irq_agent_h", this);
    command_agent_h = cmd_agent::type_id::create("command_agent_h", this);
    scoreboard_h = soc_scoreboard::type_id::create("scoreboard_h", this);
    coverage_h = soc_coverage::type_id::create("coverage_h", this);
    virtual_sequencer_h = soc_virtual_sequencer::type_id::create("virtual_sequencer_h", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    axil_agent_h.monitor_h.analysis_port.connect(scoreboard_h.axil_export);
    axil_agent_h.monitor_h.analysis_port.connect(coverage_h.analysis_export);
    memory_agent_h.monitor_h.analysis_port.connect(scoreboard_h.memory_export);
    memory_agent_h.monitor_h.analysis_port.connect(coverage_h.memory_export);
    irq_agent_h.monitor_h.analysis_port.connect(scoreboard_h.irq_export);
    irq_agent_h.monitor_h.analysis_port.connect(coverage_h.irq_export);
    command_agent_h.monitor_h.analysis_port.connect(scoreboard_h.command_export);
    command_agent_h.monitor_h.analysis_port.connect(coverage_h.command_export);
    virtual_sequencer_h.axil_sequencer_h = axil_agent_h.sequencer_h;
    virtual_sequencer_h.memory_model = config_h.memory_config.memory;
    virtual_sequencer_h.scoreboard_h = scoreboard_h;
    virtual_sequencer_h.reset_vif = config_h.reset_vif;
  endfunction
endclass
